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
            "stop generation",
            "waiting for approval",
            "waiting for review",
            "waiting for response",
            "answer question",
            "prompt input actions",
            "add agents, context"
        ]
        return dump
            .components(separatedBy: "\n")
            .filter { line in
                let lower = line.lowercased()
                return keywords.contains { lower.contains($0) }
            }
    }
}

enum ChatControlMatch {
    case working
    case attention
}

enum ChatControlLabel {
    static func classify(_ raw: String) -> ChatControlMatch? {
        let label = normalized(raw)
        guard !label.isEmpty, label.count <= 120 else { return nil }
        if label == "stop generation" || label.hasPrefix("stop generation") {
            return .working
        }
        if label == "stop" || label == "working" || label == "working..." || label == "working…" {
            return .working
        }
        if label.hasPrefix("generating responses") {
            return .working
        }
        if label.range(of: #"^\d+ working$"#, options: .regularExpression) != nil {
            return .working
        }
        if label == "answer question" || label.hasPrefix("answer questions") {
            return .attention
        }
        if attentionPhrases.contains(where: { matchesPhrase(label, $0) }) {
            return .attention
        }
        return nil
    }

    private static func matchesPhrase(_ label: String, _ phrase: String) -> Bool {
        guard label.hasPrefix(phrase) else { return false }
        let rest = label.dropFirst(phrase.count)
        guard let next = rest.first else { return true }
        return next == " " || next == "." || next == "…" || next == ":"
    }

    static func isComposerAnchor(_ raw: String) -> Bool {
        let label = normalized(raw)
        guard !label.isEmpty, label.count <= 120 else { return false }
        if label == "prompt input actions" || label == "prompt actions" {
            return true
        }
        return label == "add agents, context, tools" || label.hasPrefix("add agents, context")
    }

    private static let attentionPhrases = [
        "waiting for approval",
        "waiting for review",
        "waiting for response"
    ]

    private static func normalized(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

enum ChatControlScanner {
    struct Read {
        var labels: [String]
        var finished: Bool
    }

    private static let skipDescend: Set<String> = [
        "AXTextArea", "AXTextField", "AXOutline", "AXTable"
    ]

    static func isAlive(_ element: AXUIElement) -> Bool {
        AXUIElementSetMessagingTimeout(element, 0.4)
        return AXHelpers.stringAttribute(element, kAXRoleAttribute as String) != nil
    }

    static func locateRegion(in root: AXUIElement) -> (region: AXUIElement, read: Read)? {
        guard let anchor = findBestAnchor(in: root) else { return nil }
        let region = container(around: anchor, stoppingBefore: root)
        var read = readLabels(in: region)
        for label in controlLabels(of: anchor) where !read.labels.contains(label) {
            read.labels.append(label)
        }
        return (region, read)
    }

    static func readLabels(in region: AXUIElement, maxNodes: Int = 400) -> Read {
        AXUIElementSetMessagingTimeout(region, 0.4)
        var labels: [String]? = []
        var visited = 0
        var finished = true
        var ignoredAnchor: AXUIElement?
        var ignoredRank: Int?
        walk(
            region,
            depth: 0,
            maxDepth: 14,
            maxNodes: maxNodes,
            limitTimeout: false,
            visited: &visited,
            labels: &labels,
            finished: &finished,
            bestAnchor: &ignoredAnchor,
            bestRank: &ignoredRank
        )
        return Read(labels: labels ?? [], finished: finished)
    }

    private static func findBestAnchor(in root: AXUIElement) -> AXUIElement? {
        let found = search(root)
        if found.anchor == nil, CSLog.debugEnabled {
            let sample = found.sample.joined(separator: " | ")
            CSLog.attention.debug("chat locate missed after \(found.visited) nodes: \(sample, privacy: .public)")
        }
        return found.anchor
    }

    private static func search(_ root: AXUIElement) -> (anchor: AXUIElement?, visited: Int, sample: [String]) {
        var queue: [(element: AXUIElement, depth: Int)] = [(root, 0)]
        var cursor = 0
        var visited = 0
        var bestAnchor: AXUIElement?
        var bestRank = 0
        var sample: [String] = []
        let maxNodes = 2500

        while cursor < queue.count, visited < maxNodes {
            let item = queue[cursor]
            cursor += 1
            if item.depth > 0 {
                AXUIElementSetMessagingTimeout(item.element, 0.25)
            }
            visited += 1

            let role = AXHelpers.stringAttribute(item.element, kAXRoleAttribute as String) ?? ""
            let names = controlLabels(role: role, element: item.element)
            let rank = rank(of: names, role: role)
            if rank > bestRank {
                bestRank = rank
                bestAnchor = item.element
            }
            if sample.count < 12 {
                for name in names where sample.count < 12 && (role.contains("Button") || ChatControlLabel.classify(name) != nil) {
                    sample.append(name)
                }
            }
            if bestRank >= 100 {
                break
            }

            let keepDescending = bestRank < 90 && item.depth < 22 && !skipDescend.contains(role)
            guard keepDescending else { continue }
            let kids = children(of: item.element)
            for child in kids.reversed() where queue.count < maxNodes {
                queue.append((child, item.depth + 1))
            }
        }

        let anchor = bestRank >= 40 ? bestAnchor : nil
        return (anchor, visited, sample)
    }

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        maxNodes: Int,
        limitTimeout: Bool,
        visited: inout Int,
        labels: inout [String]?,
        finished: inout Bool,
        bestAnchor: inout AXUIElement?,
        bestRank: inout Int?
    ) {
        if limitTimeout {
            AXUIElementSetMessagingTimeout(element, 0.4)
        }
        guard visited < maxNodes, depth <= maxDepth else {
            finished = false
            return
        }
        visited += 1

        let role = AXHelpers.stringAttribute(element, kAXRoleAttribute as String) ?? ""
        let names = controlLabels(role: role, element: element)
        if var collected = labels {
            for name in names where !collected.contains(name) {
                collected.append(name)
            }
            labels = collected
        }
        if var rankValue = bestRank {
            let rank = rank(of: names, role: role)
            if rank > rankValue {
                rankValue = rank
                bestAnchor = element
            }
            bestRank = rankValue
            if rankValue >= 100 {
                return
            }
        }

        guard depth < maxDepth, !skipDescend.contains(role) else { return }
        let kids = children(of: element)
        let visible = kids.count > 80 ? Array(kids.suffix(80)) : kids
        if kids.count > 80 {
            finished = false
        }
        for child in visible.reversed() {
            walk(
                child,
                depth: depth + 1,
                maxDepth: maxDepth,
                maxNodes: maxNodes,
                limitTimeout: true,
                visited: &visited,
                labels: &labels,
                finished: &finished,
                bestAnchor: &bestAnchor,
                bestRank: &bestRank
            )
            if visited >= maxNodes || (bestRank ?? 0) >= 100 {
                if visited >= maxNodes {
                    finished = false
                }
                return
            }
        }
    }

    private static func container(around anchor: AXUIElement, stoppingBefore root: AXUIElement) -> AXUIElement {
        var current = anchor
        for _ in 0..<8 {
            guard let parent = parent(of: current), !same(parent, root) else { break }
            let role = AXHelpers.stringAttribute(parent, kAXRoleAttribute as String) ?? ""
            if role == "AXWindow" || role == "AXWebArea" { break }
            if children(of: parent).count > 35 { break }
            current = parent
        }
        return current
    }

    private static func rank(of labels: [String], role: String) -> Int {
        var best = 0
        for label in labels {
            switch ChatControlLabel.classify(label) {
            case .attention:
                best = max(best, 100)
            case .working:
                let lower = label.lowercased()
                if lower.hasPrefix("stop generation") {
                    best = max(best, 95)
                } else if role == "AXButton" || role == "AXMenuButton" {
                    best = max(best, 90)
                } else {
                    best = max(best, 85)
                }
            case nil:
                if ChatControlLabel.isComposerAnchor(label) {
                    best = max(best, 40)
                }
            }
        }
        return best
    }

    private static func controlLabels(of element: AXUIElement) -> [String] {
        let role = AXHelpers.stringAttribute(element, kAXRoleAttribute as String) ?? ""
        return controlLabels(role: role, element: element)
    }

    private static func controlLabels(role: String, element: AXUIElement) -> [String] {
        if role == "AXTextArea" || role == "AXTextField" || role == "AXOutline" || role == "AXTable" {
            return []
        }
        var labels: [String] = []
        if let title = AXHelpers.stringAttribute(element, kAXTitleAttribute as String) {
            appendControl(&labels, title)
        }
        if let description = AXHelpers.stringAttribute(element, kAXDescriptionAttribute as String) {
            appendControl(&labels, description)
        }
        if let help = AXHelpers.stringAttribute(element, kAXHelpAttribute as String) {
            appendControl(&labels, help)
        }
        return labels
    }

    private static func appendControl(_ labels: inout [String], _ raw: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 120 else { return }
        if !labels.contains(trimmed) {
            labels.append(trimmed)
        }
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        AXHelpers.copyAttribute(element, kAXChildrenAttribute as String) as? [AXUIElement] ?? []
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        guard let value = AXHelpers.copyAttribute(element, kAXParentAttribute as String) else { return nil }
        return value as! AXUIElement
    }

    private static func same(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool {
        CFEqual(lhs, rhs)
    }
}
