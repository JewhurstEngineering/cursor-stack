import Foundation

@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { persist() }
    }

    private let url: URL

    init(fileManager: FileManager = .default) {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("CursorStack", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        url = root.appendingPathComponent("settings.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
            if settings.tabHeight > 40 {
                settings.tabHeight = 36
            }
        } else {
            settings = AppSettings()
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(settings)
            try data.write(to: url, options: [.atomic])
        } catch {
            CSLog.general.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
