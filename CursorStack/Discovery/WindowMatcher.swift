import Foundation

enum WindowMatcher {
    struct ScoredMatch {
        var persistedID: UUID
        var runtimeIndex: Int
        var score: Int
    }

    static func score(persisted: PersistedWindowReference, title: String, projectDisplayName: String) -> Int {
        let persistedProject = persisted.projectDisplayName.lowercased()
        let persistedTitle = persisted.lastTitle.lowercased()
        let liveTitle = title.lowercased()
        let liveProject = projectDisplayName.lowercased()

        if !persistedProject.isEmpty, persistedProject == liveProject {
            return 100
        }
        if !persistedTitle.isEmpty, persistedTitle == liveTitle {
            return 90
        }
        if !persistedProject.isEmpty, liveTitle.contains(persistedProject) {
            return 80
        }
        if !persistedTitle.isEmpty, liveTitle.contains(persistedTitle) || persistedTitle.contains(liveTitle) {
            return 60
        }
        if let alias = persisted.alias?.lowercased(), !alias.isEmpty, liveTitle.contains(alias) || liveProject == alias {
            return 70
        }
        return 0
    }

    static func match(
        persisted: [PersistedWindowReference],
        live: [(title: String, projectDisplayName: String)]
    ) -> [UUID: Int] {
        var assignments: [UUID: Int] = [:]
        var usedLive = Set<Int>()

        var scored: [ScoredMatch] = []
        for ref in persisted {
            for (index, window) in live.enumerated() {
                let value = score(persisted: ref, title: window.title, projectDisplayName: window.projectDisplayName)
                if value >= 60 {
                    scored.append(ScoredMatch(persistedID: ref.id, runtimeIndex: index, score: value))
                }
            }
        }

        for match in scored.sorted(by: { $0.score > $1.score }) {
            if assignments[match.persistedID] != nil { continue }
            if usedLive.contains(match.runtimeIndex) { continue }
            assignments[match.persistedID] = match.runtimeIndex
            usedLive.insert(match.runtimeIndex)
        }

        return assignments
    }
}
