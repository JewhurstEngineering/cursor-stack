import Foundation

@MainActor
final class GroupStore {
    private let url: URL

    convenience init(fileManager: FileManager = .default) {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CursorStack", isDirectory: true)
        self.init(directory: root, fileManager: fileManager)
    }

    init(directory: URL, fileManager: FileManager = .default) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("groups.json")
    }

    func load() -> [CursorWindowGroup] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try JSONDecoder().decode([CursorWindowGroup].self, from: data)
        } catch {
            CSLog.general.error("Failed to load groups: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    func save(_ groups: [CursorWindowGroup], allowingEmpty: Bool = false) {
        if groups.isEmpty, !allowingEmpty, !load().isEmpty {
            CSLog.general.error("Refusing to overwrite saved groups with an empty list")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(groups)
            try data.write(to: url, options: [.atomic])
        } catch {
            CSLog.general.error("Failed to save groups: \(error.localizedDescription, privacy: .public)")
        }
    }

    func reset() {
        try? FileManager.default.removeItem(at: url)
    }
}
