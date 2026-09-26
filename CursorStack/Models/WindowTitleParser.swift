import Foundation

enum WindowTitleParser {
    static func projectDisplayName(from title: String) -> String {
        var trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [" — Cursor", " – Cursor", " - Cursor", " — Visual Studio Code", " - Visual Studio Code"]
        for suffix in suffixes where trimmed.hasSuffix(suffix) {
            trimmed = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
        }

        while trimmed.hasPrefix("●") || trimmed.hasPrefix("•") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }

        let separators = [" — ", " – ", " - "]
        for separator in separators {
            let parts = trimmed.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if parts.count >= 2 {
                let candidate = parts[parts.count - 1]
                if candidate.lowercased() != "cursor" {
                    return candidate
                }
                return parts[parts.count - 2]
            }
        }

        if trimmed.isEmpty {
            return "Untitled"
        }
        return trimmed
    }

    /// The project folder name inside a Cursor window title.
    /// A dirty window ends in "Modified" instead of "Cursor", so the last
    /// component is not always the project.
    static func projectToken(from title: String) -> String? {
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

        let ignored: Set<String> = ["cursor", "modified", "visual studio code"]
        let kept = parts.filter { !ignored.contains($0.lowercased()) }
        return kept.last
    }
}
