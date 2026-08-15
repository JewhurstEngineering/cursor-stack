import Foundation

@MainActor
final class GroupStore {
    private let url: URL

    init(fileManager: FileManager = .default) {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CursorStack", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        url = root.appendingPathComponent("groups.json")
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

    func save(_ groups: [CursorWindowGroup]) {
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
