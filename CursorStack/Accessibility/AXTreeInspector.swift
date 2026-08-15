import ApplicationServices
import Foundation

enum AXTreeInspector {
    static func dump(element: AXUIElement, maxDepth: Int = 8, maxChildren: Int = 40) -> String {
        var lines: [String] = []
        walk(element, depth: 0, maxDepth: maxDepth, maxChildren: maxChildren, into: &lines)
        return lines.joined(separator: "\n")
    }

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        maxChildren: Int,
        into lines: inout [String]
    ) {
        let indent = String(repeating: "  ", count: depth)
        let role = AXHelpers.stringAttribute(element, kAXRoleAttribute as String) ?? "?"
        let subrole = AXHelpers.stringAttribute(element, kAXSubroleAttribute as String)
        let title = AXHelpers.stringAttribute(element, kAXTitleAttribute as String)
        let description = AXHelpers.stringAttribute(element, kAXDescriptionAttribute as String)
        let value = stringifiedValue(AXHelpers.copyAttribute(element, kAXValueAttribute as String))
        let help = AXHelpers.stringAttribute(element, kAXHelpAttribute as String)

        var parts = ["\(indent)\(role)"]
        if let subrole, !subrole.isEmpty { parts.append("subrole=\(subrole)") }
        if let title, !title.isEmpty { parts.append("title=\(sanitize(title))") }
        if let description, !description.isEmpty { parts.append("desc=\(sanitize(description))") }
        if let value, !value.isEmpty { parts.append("value=\(sanitize(value))") }
        if let help, !help.isEmpty { parts.append("help=\(sanitize(help))") }
        lines.append(parts.joined(separator: " "))

        guard depth < maxDepth else { return }
        guard let children = AXHelpers.copyAttribute(element, kAXChildrenAttribute as String) as? [AXUIElement] else {
            return
        }
        for child in children.prefix(maxChildren) {
            walk(child, depth: depth + 1, maxDepth: maxDepth, maxChildren: maxChildren, into: &lines)
        }
        if children.count > maxChildren {
            lines.append("\(indent)  … \(children.count - maxChildren) more children omitted")
        }
    }

    private static func stringifiedValue(_ value: AnyObject?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func sanitize(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        if collapsed.count > 120 {
            return String(collapsed.prefix(120)) + "…"
        }
        return collapsed
    }

    static func attentionHints(in dump: String) -> [String] {
        let keywords = [
            "unread", "attention", "badge", "notification", "agent",
            "needs", "complete", "finished", "error", "waiting", "running"
        ]
        return dump
            .components(separatedBy: "\n")
            .filter { line in
                let lower = line.lowercased()
                return keywords.contains { lower.contains($0) }
            }
    }
}
