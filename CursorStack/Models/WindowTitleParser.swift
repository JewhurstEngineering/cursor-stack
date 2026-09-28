import Foundation

enum WindowTitleParser {
    /// App name and macOS's dirty-window marker. Neither is the project folder.
    /// A dirty Cursor window ends in "Modified" instead of "Cursor".
    private static let ignoredTokens: Set<String> = ["cursor", "modified", "visual studio code"]

    static func projectDisplayName(from title: String) -> String {
        meaningfulComponents(from: title).last ?? "Untitled"
    }

    /// The project folder name inside a Cursor window title.
    static func projectToken(from title: String) -> String? {
        meaningfulComponents(from: title).last
    }

    private static func meaningfulComponents(from title: String) -> [String] {
        var trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [" — Cursor", " – Cursor", " - Cursor", " — Visual Studio Code", " - Visual Studio Code"]
        for suffix in suffixes where trimmed.hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }

        while trimmed.hasPrefix("●") || trimmed.hasPrefix("•") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let separators = [" — ", " – ", " - "]
        var parts = [trimmed]
        for separator in separators {
            let split = trimmed.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if split.count >= 2 {
                parts = split
                break
            }
        }

        return parts.filter { part in
            !part.isEmpty && !ignoredTokens.contains(part.lowercased())
        }
    }
}
