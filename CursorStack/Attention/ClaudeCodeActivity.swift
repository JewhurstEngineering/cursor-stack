import Foundation

struct ClaudeCodeSession: Equatable, Sendable {
    var folderName: String
    var status: String
    var statusUpdated: Date?
}

struct ClaudeCodeSnapshot: Equatable, Sendable {
    var sessions: [ClaudeCodeSession]
    var readable: Bool

    static let empty = ClaudeCodeSnapshot(sessions: [], readable: false)
}

enum ClaudeCodeActivity {
    static let cursorEntrypoint = "claude-vscode"

    /// A busy session that has not reported in recently is stuck, same window as a Cursor run.
    static func isBusy(_ session: ClaudeCodeSession, now: Date = Date()) -> Bool {
        guard session.status == "busy", let updated = session.statusUpdated else { return false }
        let age = now.timeIntervalSince(updated)
        return age > -60 && age < ComposerActivity.runningWindow
    }

    static func matches(title: String, sessions: [ClaudeCodeSession], now: Date = Date()) -> Bool {
        guard let token = WindowTitleParser.projectToken(from: title) else { return false }
        return sessions.contains { session in
            isBusy(session, now: now)
                && session.folderName.compare(token, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    static func session(from data: Data) -> ClaudeCodeSession? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            json["entrypoint"] as? String == cursorEntrypoint,
            let cwd = json["cwd"] as? String
        else { return nil }
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        guard !folder.isEmpty, folder != "/" else { return nil }
        return ClaudeCodeSession(
            folderName: folder,
            status: json["status"] as? String ?? "",
            statusUpdated: date(from: json["statusUpdatedAt"])
        )
    }

    private static func date(from value: Any?) -> Date? {
        let milliseconds: Double
        if let number = value as? NSNumber {
            milliseconds = number.doubleValue
        } else if let number = value as? Double {
            milliseconds = number
        } else if let number = value as? Int {
            milliseconds = Double(number)
        } else {
            return nil
        }
        guard milliseconds > 0 else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }
}

final class ClaudeCodeActivityReader: @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.jewhurst.CursorStack.claude", qos: .utility)
    private let sessionsURL: URL

    init(claudeDirectory: URL? = nil) {
        let root = claudeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)
        sessionsURL = root.appendingPathComponent("sessions", isDirectory: true)
    }

    func load(_ completion: @escaping @MainActor (ClaudeCodeSnapshot) -> Void) {
        queue.async {
            let snapshot = self.read()
            Task { @MainActor in
                completion(snapshot)
            }
        }
    }

    private func read() -> ClaudeCodeSnapshot {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return ClaudeCodeSnapshot(sessions: [], readable: false)
        }

        var sessions: [ClaudeCodeSession] = []
        for file in files where file.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: file),
                let session = ClaudeCodeActivity.session(from: data)
            else { continue }
            sessions.append(session)
        }
        return ClaudeCodeSnapshot(sessions: sessions, readable: true)
    }
}
