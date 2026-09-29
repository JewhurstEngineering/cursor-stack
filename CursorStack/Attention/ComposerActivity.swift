import Foundation
import SQLite3

struct ComposerWorkspace: Equatable, Sendable {
    var id: String
    var folderName: String
}

struct ComposerChatHeader: Equatable, Sendable {
    var workspaceID: String
    var blocking: Bool
    var hasUnfinishedRun: Bool
    var checkpoint: Date?
    var updated: Date?
}

struct ComposerActivitySnapshot: Equatable, Sendable {
    var workspaces: [ComposerWorkspace]
    var headers: [ComposerChatHeader]
    var readable: Bool

    static let empty = ComposerActivitySnapshot(workspaces: [], headers: [], readable: false)
}

enum ComposerActivity {
    /// An open run can sit on a tool call without a new checkpoint for a few minutes.
    static let runningWindow: TimeInterval = 240
    /// A question can wait without new tokens. Older than this is a stuck flag.
    static let waitingWindow: TimeInterval = 12 * 60 * 60

    /// nil when the window title does not name a known Cursor workspace.
    static func state(
        matching title: String,
        workspaces: [ComposerWorkspace],
        headers: [ComposerChatHeader],
        now: Date = Date()
    ) -> AttentionState? {
        guard let token = WindowTitleParser.projectToken(from: title) else { return nil }
        let ids = Set(
            workspaces
                .filter { $0.folderName.compare(token, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
                .map(\.id)
        )
        guard !ids.isEmpty else { return nil }
        return activity(of: headers.filter { ids.contains($0.workspaceID) }, now: now)
    }

    static func activity(of headers: [ComposerChatHeader], now: Date = Date()) -> AttentionState {
        if headers.contains(where: { $0.blocking && touched($0, within: waitingWindow, now: now) }) {
            return .attention
        }
        if headers.contains(where: { isRunning($0, now: now) }) {
            return .working
        }
        return .idle
    }

    private static func isRunning(_ header: ComposerChatHeader, now: Date) -> Bool {
        guard header.hasUnfinishedRun, let checkpoint = header.checkpoint else { return false }
        let age = now.timeIntervalSince(checkpoint)
        return age > -60 && age < runningWindow
    }

    private static func touched(_ header: ComposerChatHeader, within window: TimeInterval, now: Date) -> Bool {
        let latest = [header.checkpoint, header.updated].compactMap { $0 }.max()
        guard let latest else { return false }
        let age = now.timeIntervalSince(latest)
        return age > -60 && age < window
    }
}

enum FinishedChatSignal {
    /// A run that was spinning and then stopped is done. Hold that until the tab is opened.
    static func resolve(live: AttentionState, previous: AttentionState, holding: Bool) -> (state: AttentionState, holding: Bool) {
        switch live {
        case .working:
            return (.working, false)
        case .attention, .error:
            return (live, false)
        case .idle, .completed:
            if previous == .working || holding {
                return (.completed, true)
            }
            return (.idle, false)
        case .unknown:
            return (previous, holding)
        }
    }
}

final class ComposerActivityReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.jewhurst.CursorStack.composer", qos: .utility)
    private let databaseURL: URL
    private let workspaceStorageURL: URL
    private var folderCache: (at: Date, workspaces: [ComposerWorkspace])?
    private let folderTTL: TimeInterval = 30

    init(cursorSupportURL: URL? = nil) {
        let root = cursorSupportURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cursor/User", isDirectory: true)
        databaseURL = root.appendingPathComponent("globalStorage/state.vscdb")
        workspaceStorageURL = root.appendingPathComponent("workspaceStorage", isDirectory: true)
    }

    func load(_ completion: @escaping @MainActor (ComposerActivitySnapshot) -> Void) {
        queue.async {
            let snapshot = self.read()
            Task { @MainActor in
                completion(snapshot)
            }
        }
    }

    private func read() -> ComposerActivitySnapshot {
        let workspaces = cachedWorkspaces()
        guard let headers = readHeaders() else {
            return ComposerActivitySnapshot(workspaces: workspaces, headers: [], readable: false)
        }
        return ComposerActivitySnapshot(workspaces: workspaces, headers: headers, readable: true)
    }

    private func cachedWorkspaces() -> [ComposerWorkspace] {
        if let folderCache, Date().timeIntervalSince(folderCache.at) < folderTTL {
            return folderCache.workspaces
        }
        let workspaces = loadWorkspaces()
        folderCache = (Date(), workspaces)
        return workspaces
    }

    private func loadWorkspaces() -> [ComposerWorkspace] {
        guard let directories = try? FileManager.default.contentsOfDirectory(
            at: workspaceStorageURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var workspaces: [ComposerWorkspace] = []
        for directory in directories {
            let file = directory.appendingPathComponent("workspace.json")
            guard
                let data = try? Data(contentsOf: file),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let folder = json["folder"] as? String,
                let url = URL(string: folder)
            else { continue }
            let name = url.lastPathComponent
            guard !name.isEmpty else { continue }
            workspaces.append(ComposerWorkspace(id: directory.lastPathComponent, folderName: name))
        }
        return workspaces
    }

    private func readHeaders() -> [ComposerChatHeader]? {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databaseURL.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            if let db { sqlite3_close(db) }
            return nil
        }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT workspaceId,
               json_extract(value, '$.hasBlockingPendingActions'),
               json_extract(value, '$.unfinishedRunAt'),
               json_extract(value, '$.conversationCheckpointLastUpdatedAt'),
               json_extract(value, '$.lastUpdatedAt')
        FROM composerHeaders
        WHERE isArchived = 0 AND isSubagent = 0
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        var headers: [ComposerChatHeader] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let rawID = sqlite3_column_text(statement, 0) else { continue }
            headers.append(ComposerChatHeader(
                workspaceID: String(cString: rawID),
                blocking: sqlite3_column_type(statement, 1) != SQLITE_NULL && sqlite3_column_int(statement, 1) != 0,
                hasUnfinishedRun: sqlite3_column_type(statement, 2) != SQLITE_NULL,
                checkpoint: Self.date(statement, 3),
                updated: Self.date(statement, 4)
            ))
        }
        return headers
    }

    private static func date(_ statement: OpaquePointer, _ index: Int32) -> Date? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        let milliseconds = sqlite3_column_double(statement, index)
        guard milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
