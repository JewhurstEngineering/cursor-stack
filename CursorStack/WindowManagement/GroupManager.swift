import AppKit
import Foundation

@MainActor
protocol GroupManagerDelegate: AnyObject {
    var tabHeight: CGFloat { get }
    func groupManager(_ manager: GroupManager, didCreate group: RuntimeWindowGroup)
    func groupManager(_ manager: GroupManager, didRemove groupID: UUID)
    func groupManagerNeedsPersistence(_ manager: GroupManager)
    func groupManager(_ manager: GroupManager, didDetectNewWindow window: ManagedCursorWindow)
}

@MainActor
final class GroupManager: ObservableObject {
    @Published private(set) var groups: [RuntimeWindowGroup] = []
    @Published private(set) var ungroupedWindows: [ManagedCursorWindow] = []

    weak var delegate: GroupManagerDelegate?

    private let accessibility: AccessibilityService
    private let discovery: CursorDiscoveryService
    private let persistDebouncer = Debouncer(delay: 0.4)
    private let fitDebouncer = Debouncer(delay: 0.24)
    private var knownElementTokens = Set<UInt>()
    private var consecutiveMisses: [UUID: Int] = [:]
    private(set) var persistEmptyGroups = false

    init(accessibility: AccessibilityService, discovery: CursorDiscoveryService) {
        self.accessibility = accessibility
        self.discovery = discovery
    }

    var allManagedWindows: [ManagedCursorWindow] {
        groups.flatMap(\.windows) + ungroupedWindows
    }

    func groupedIDs() -> Set<UUID> {
        Set(groups.flatMap { $0.windows.map(\.id) })
    }

    func createGroup(name: String, windows: [ManagedCursorWindow], frame: CGRect? = nil) {
        let unique = windows.filter { window in
            !groups.contains { group in group.windows.contains { $0.id == window.id } }
        }
        guard unique.count >= 1 else { return }

        let requestedFrame = frame ?? unique.first(where: { $0.isFocused || $0.isMain })?.frame ?? unique[0].frame
        let canonical = frameLeavingTabRoom(requestedFrame)
        let group = RuntimeWindowGroup(
            name: name,
            windows: unique,
            activeWindowID: unique.first(where: { $0.isFocused || $0.isMain })?.id ?? unique[0].id,
            synchronizedFrame: canonical,
            isPaused: false
        )

        ungroupedWindows.removeAll { candidate in unique.contains { $0.id == candidate.id } }
        groups.append(group)

        applyCanonicalFrame(in: group, raising: group.activeWindow)
        delegate?.groupManager(self, didCreate: group)
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    func restore(persisted: [CursorWindowGroup], live: [ManagedCursorWindow]) {
        groups.removeAll()
        ungroupedWindows = live
        var remaining = live

        for record in persisted {
            let liveTuples = remaining.map { (title: $0.title, projectDisplayName: $0.projectDisplayName) }
            let assignments = WindowMatcher.match(persisted: record.members, live: liveTuples)
            var members: [ManagedCursorWindow] = []
            var groupUnresolved: [PersistedWindowReference] = []

            for member in record.members {
                if let index = assignments[member.id] {
                    let window = remaining[index]
                    let restored = ManagedCursorWindow(id: member.id, snapshot: window.snapshot, alias: member.alias)
                    members.append(restored)
                } else {
                    groupUnresolved.append(member)
                }
            }

            remaining.removeAll { candidate in
                members.contains { AXHelpers.equal($0.element, candidate.element) }
            }

            guard !members.isEmpty || !groupUnresolved.isEmpty else { continue }
            let restoredFrame = safeRestoreFrame(
                persisted: record.frame.cgRect,
                liveMembers: members
            )
            let group = RuntimeWindowGroup(
                id: record.id,
                name: record.name,
                windows: members,
                activeWindowID: record.activeMemberID,
                synchronizedFrame: restoredFrame,
                isPaused: record.settings.isPaused
            )
            if let bestLive = bestVisibleLiveWindow(in: members) {
                group.activeWindowID = bestLive.id
            }
            groups.append(group)
            group.unresolved = groupUnresolved
            if !members.isEmpty {
                applyCanonicalFrame(in: group, raising: group.activeWindow)
            }
            delegate?.groupManager(self, didCreate: group)
        }

        ungroupedWindows = remaining
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    func activate(windowID: UUID, in groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }),
              let window = group.windows.first(where: { $0.id == windowID }) else { return }
        guard AXHelpers.isAlive(window.element) else {
            window.isUnavailable = true
            objectWillChange.send()
            return
        }

        if !group.isPaused && !group.isFullScreenPaused {
            applyFrameIfNeeded(group.synchronizedFrame, to: window)
        }

        FocusCoordinator.activate(window: window, discovery: discovery, accessibility: accessibility)
        group.activeWindowID = window.id
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    func cycle(in group: RuntimeWindowGroup, delta: Int) {
        let live = group.liveWindows
        guard !live.isEmpty else { return }
        let currentIndex = live.firstIndex(where: { $0.id == group.activeWindowID }) ?? 0
        let nextIndex = (currentIndex + delta + live.count) % live.count
        activate(windowID: live[nextIndex].id, in: group.id)
    }

    func activateNumberedTab(_ number: Int) {
        guard let group = preferredGroup(), number >= 1, number <= group.liveWindows.count else { return }
        activate(windowID: group.liveWindows[number - 1].id, in: group.id)
    }

    func preferredGroup() -> RuntimeWindowGroup? {
        if let focused = groups.first(where: { $0.activeWindow?.isFocused == true }) {
            return focused
        }
        return groups.first
    }

    func handleFrameChange(pid: pid_t, element: AXUIElement) {
        guard let window = findWindow(pid: pid, element: element),
              let group = group(containing: window.id) else { return }

        guard let newFrame = try? accessibility.frame(of: window.snapshot) else { return }
        window.frame = newFrame

        if group.isApplyingSynchronizedFrame { return }
        if let until = group.suppressAXUntil, Date() < until { return }

        let screen = NSScreen.screens.first { $0.frame.intersects(newFrame) } ?? NSScreen.main
        if let screen, ScreenCoordinateConverter.looksFullScreen(newFrame, screenFrame: screen.frame) {
            group.isFullScreenPaused = true
            group.objectWillChange.send()
            return
        } else if group.isFullScreenPaused {
            group.isFullScreenPaused = false
        }

        if group.isPaused || group.isFullScreenPaused {
            group.objectWillChange.send()
            return
        }

        if window.id != group.activeWindowID,
           ScreenCoordinateConverter.framesApproximatelyEqual(
               newFrame,
               group.synchronizedFrame,
               tolerance: 3
           ) {
            // Delayed AX echo from synchronizing a background member.
            return
        }

        // Only the visible member can be dragged by the user. If focus
        // notification delivery lags behind the move notification, promote it
        // instead of forcing it back to the old canonical frame.
        group.activeWindowID = window.id
        group.synchronizedFrame = newFrame
        group.isApplyingSynchronizedFrame = true
        group.suppressAXUntil = Date().addingTimeInterval(0.5)
        for member in group.liveWindows where member.id != window.id {
            applyFrameIfNeeded(newFrame, to: member)
        }
        group.isApplyingSynchronizedFrame = false
        persistDebouncer.run { [weak self] in
            guard let self else { return }
            self.delegate?.groupManagerNeedsPersistence(self)
        }
        fitDebouncer.run { [weak self] in
            self?.ensureTabRoom(for: group.id)
        }
        group.objectWillChange.send()
    }

    func synchronizeFrame(_ frame: CGRect, in groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        guard !group.isPaused, !group.isFullScreenPaused else { return }
        group.synchronizedFrame = frameLeavingTabRoom(frame)
        applyCanonicalFrame(in: group, raising: nil)
        delegate?.groupManagerNeedsPersistence(self)
    }

    func ensureTabRoomForAllGroups() {
        for group in groups {
            ensureTabRoom(for: group.id)
        }
    }

    func pause(_ groupID: UUID, paused: Bool) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        group.isPaused = paused
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
    }

    func maximize(_ groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        let screen = NSScreen.screens.max {
            $0.frame.intersection(group.synchronizedFrame).width * $0.frame.intersection(group.synchronizedFrame).height
                < $1.frame.intersection(group.synchronizedFrame).width * $1.frame.intersection(group.synchronizedFrame).height
        } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let tabHeight = delegate?.tabHeight ?? 36
        let content = ScreenCoordinateConverter.maximizedContentFrame(visibleFrame: visible, tabHeight: tabHeight)
        if !ScreenCoordinateConverter.framesApproximatelyEqual(group.synchronizedFrame, content, tolerance: 8) {
            group.frameBeforeMaximize = group.synchronizedFrame
        }
        group.isPaused = false
        synchronizeFrame(content, in: groupID)
        if let active = group.activeWindow {
            FocusCoordinator.activate(window: active, discovery: discovery, accessibility: accessibility)
        }
    }

    func toggleMaximize(_ groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        let screen = NSScreen.screens.max {
            $0.frame.intersection(group.synchronizedFrame).width * $0.frame.intersection(group.synchronizedFrame).height
                < $1.frame.intersection(group.synchronizedFrame).width * $1.frame.intersection(group.synchronizedFrame).height
        } ?? NSScreen.main
        let tabHeight = delegate?.tabHeight ?? 36
        if let visible = screen?.visibleFrame {
            let maximized = ScreenCoordinateConverter.maximizedContentFrame(visibleFrame: visible, tabHeight: tabHeight)
            if ScreenCoordinateConverter.framesApproximatelyEqual(group.synchronizedFrame, maximized, tolerance: 8),
               let restored = group.frameBeforeMaximize {
                synchronizeFrame(restored, in: groupID)
                return
            }
        }
        maximize(groupID)
    }

    func minimizeGroup(_ groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        for window in group.liveWindows {
            try? accessibility.minimize(window.snapshot)
            window.isMinimized = true
        }
        group.objectWillChange.send()
        objectWillChange.send()
    }

    func restoreGroup(_ groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        for window in group.liveWindows {
            try? accessibility.deminimize(window.snapshot)
            window.isMinimized = false
        }
        group.isPaused = false
        group.isFullScreenPaused = false
        applyCanonicalFrame(in: group, raising: group.activeWindow)
        group.objectWillChange.send()
        objectWillChange.send()
    }

    func closeActiveWindow(in groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }),
              let active = group.activeWindow else { return }
        closeCursorWindow(active.id)
    }

    func moveGroup(_ groupID: UUID, matchingTabPanel panelFrame: CGRect) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        guard !group.isApplyingSynchronizedFrame else { return }
        let height = max(group.synchronizedFrame.height, 200)
        let newFrame = ScreenCoordinateConverter.windowFrame(
            matchingTabPanel: panelFrame,
            windowHeight: height
        )
        group.synchronizedFrame = frameLeavingTabRoom(newFrame)
        applyCanonicalFrame(in: group, raising: nil)
    }

    func renameGroup(_ groupID: UUID, to name: String) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        group.name = name
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
    }

    func renameTab(_ windowID: UUID, alias: String?) {
        guard let window = allManagedWindows.first(where: { $0.id == windowID }) else { return }
        window.alias = alias
        window.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
    }

    func moveWindow(_ windowID: UUID, from sourceGroupID: UUID, to destinationGroupID: UUID, at index: Int) {
        guard sourceGroupID != destinationGroupID else {
            reorder(in: destinationGroupID, moving: windowID, to: index)
            return
        }
        guard let source = groups.first(where: { $0.id == sourceGroupID }),
              let destination = groups.first(where: { $0.id == destinationGroupID }),
              let windowIndex = source.windows.firstIndex(where: { $0.id == windowID }) else { return }
        let window = source.windows.remove(at: windowIndex)
        if source.windows.isEmpty && source.unresolved.isEmpty {
            removeGroup(sourceGroupID)
        } else if source.activeWindowID == windowID {
            source.activeWindowID = source.liveWindows.first?.id
            source.objectWillChange.send()
        }
        let clamped = max(0, min(index, destination.windows.count))
        destination.windows.insert(window, at: clamped)
        applyFrameIfNeeded(destination.synchronizedFrame, to: window)
        destination.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    func reconnect(persisted: PersistedWindowReference, to window: ManagedCursorWindow, in groupID: UUID, applyFrame: Bool = true) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        ungroupedWindows.removeAll { $0.id == window.id }
        groups.forEach { other in
            other.windows.removeAll { $0.id == window.id }
        }
        let restored = ManagedCursorWindow(id: persisted.id, snapshot: window.snapshot, alias: persisted.alias)
        group.windows.append(restored)
        group.unresolved.removeAll { $0.id == persisted.id }
        consecutiveMisses[restored.id] = 0
        knownElementTokens.insert(CFHash(restored.element))
        if applyFrame {
            applyFrameIfNeeded(group.synchronizedFrame, to: restored)
        }
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    func forgetUnresolved(_ persistedID: UUID, in groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        let before = group.unresolved.count
        group.unresolved.removeAll { $0.id == persistedID }
        guard group.unresolved.count != before else { return }
        finishForgettingUnresolved(in: group)
    }

    func forgetAllUnresolved(in groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }),
              !group.unresolved.isEmpty else { return }
        group.unresolved.removeAll()
        finishForgettingUnresolved(in: group)
    }

    private func finishForgettingUnresolved(in group: RuntimeWindowGroup) {
        if group.windows.isEmpty && group.unresolved.isEmpty {
            removeGroup(group.id)
            return
        }
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    func reorder(in groupID: UUID, moving windowID: UUID, to index: Int) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        let ids = GroupLogic.reorder(ids: group.windows.map(\.id), moving: windowID, to: index)
        group.windows = ids.compactMap { id in group.windows.first { $0.id == id } }
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
    }

    func detach(windowID: UUID, from groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }),
              let index = group.windows.firstIndex(where: { $0.id == windowID }) else { return }
        let window = group.windows.remove(at: index)
        ungroupedWindows.append(window)

        if group.windows.isEmpty && group.unresolved.isEmpty {
            removeGroup(groupID)
            return
        }

        if group.activeWindowID == windowID {
            group.activeWindowID = group.liveWindows.first?.id
        }
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    func add(windows: [ManagedCursorWindow], to groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        for window in windows {
            guard !group.windows.contains(where: { $0.id == window.id }) else { continue }
            group.windows.append(window)
            ungroupedWindows.removeAll { $0.id == window.id }
            applyFrameIfNeeded(group.synchronizedFrame, to: window)
        }
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    func ungroupAll(_ groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        ungroupedWindows.append(contentsOf: group.windows)
        removeGroup(groupID)
    }

    func showAllWindows(_ groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        group.isPaused = true
        let screen = NSScreen.screens.first { $0.frame.intersects(group.synchronizedFrame) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? group.synchronizedFrame
        let count = max(group.liveWindows.count, 1)
        let width = max(320, visible.width / CGFloat(count))
        for (index, window) in group.liveWindows.enumerated() {
            let frame = CGRect(
                x: visible.minX + CGFloat(index) * width,
                y: visible.minY,
                width: width,
                height: visible.height
            )
            applyFrameIfNeeded(frame, to: window)
        }
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
    }

    func closeCursorWindow(_ windowID: UUID) {
        guard let window = allManagedWindows.first(where: { $0.id == windowID }) else { return }
        try? accessibility.close(window.snapshot)
    }

    func handleWindowClosed(element: AXUIElement) {
        guard let window = allManagedWindows.first(where: { AXHelpers.equal($0.element, element) }) else { return }
        if group(containing: window.id) != nil {
            window.isUnavailable = true
            consecutiveMisses[window.id] = max(consecutiveMisses[window.id] ?? 0, GroupMembershipPolicy.missThreshold - 1)
            objectWillChange.send()
            return
        }
        markClosed(window)
    }

    func handleMiniaturize(element: AXUIElement, minimized: Bool) {
        guard let window = allManagedWindows.first(where: { AXHelpers.equal($0.element, element) }),
              let group = group(containing: window.id) else { return }
        window.isMinimized = minimized
        if window.id == group.activeWindowID {
            for member in group.liveWindows where member.id != window.id {
                if minimized {
                    try? accessibility.minimize(member.snapshot)
                } else {
                    try? accessibility.deminimize(member.snapshot)
                }
            }
            if !minimized {
                applyCanonicalFrame(in: group, raising: window)
            }
        }
        group.objectWillChange.send()
    }

    func handleFocusChange(pid: pid_t, element: AXUIElement) {
        refreshFromAccessibility()
        if let window = findWindow(pid: pid, element: element),
           let group = group(containing: window.id) {
            if group.activeWindowID != window.id {
                group.activeWindowID = window.id
                group.objectWillChange.send()
                delegate?.groupManagerNeedsPersistence(self)
            }
        }
    }

    func ingestLiveWindows(_ snapshots: [AXWindowSnapshot]) {
        var unmatched = snapshots
        var membershipChanged = false
        let managed = allManagedWindows

        for window in managed {
            if let index = unmatched.firstIndex(where: { AXHelpers.equal($0.element, window.element) }) {
                window.apply(unmatched.remove(at: index))
                consecutiveMisses[window.id] = 0
            } else if !window.isClosed {
                let misses = (consecutiveMisses[window.id] ?? 0) + 1
                consecutiveMisses[window.id] = misses
                window.isUnavailable = true
                if GroupMembershipPolicy.shouldParkAsUnresolved(consecutiveMisses: misses) {
                    if group(containing: window.id) != nil {
                        parkAsUnresolved(window, persist: false)
                        membershipChanged = true
                    } else {
                        markClosed(window)
                    }
                }
            }
        }

        if reconnectUnresolved(using: &unmatched) {
            membershipChanged = true
        }
        if reconnectUngroupedWindows() {
            membershipChanged = true
        }

        for snapshot in unmatched {
            let token = CFHash(snapshot.element)
            if knownElementTokens.contains(token) { continue }
            knownElementTokens.insert(token)
            let window = ManagedCursorWindow(snapshot: snapshot)
            ungroupedWindows.append(window)
            delegate?.groupManager(self, didDetectNewWindow: window)
        }

        if membershipChanged {
            delegate?.groupManagerNeedsPersistence(self)
        }
        objectWillChange.send()
    }

    @discardableResult
    func refreshFromAccessibility() -> WindowRefreshOutcome {
        let apps = discovery.cursorApplications()
        if apps.isEmpty {
            if groups.contains(where: { !$0.windows.isEmpty }) {
                parkAllGroupedWindowsAsUnresolved()
            }
            return .cursorMissing
        }

        var snapshots: [AXWindowSnapshot] = []
        var enumeratedAny = false
        for app in apps {
            do {
                snapshots.append(contentsOf: try accessibility.windows(for: app.pid))
                enumeratedAny = true
            } catch {
                CSLog.ax.error("Skipping pid \(app.pid); window enumeration failed")
            }
        }
        if !enumeratedAny {
            CSLog.ax.error("Skipping ingest; window enumeration failed for every Cursor process")
            return .unavailable
        }
        ingestLiveWindows(snapshots)
        return .enumerated(snapshots.count)
    }

    func persistableGroups() -> [CursorWindowGroup] {
        groups.map(\.persisted)
    }

    func group(containing windowID: UUID) -> RuntimeWindowGroup? {
        groups.first { group in group.windows.contains { $0.id == windowID } }
    }

    func removeGroup(_ groupID: UUID) {
        groups.removeAll { $0.id == groupID }
        persistEmptyGroups = groups.isEmpty
        delegate?.groupManager(self, didRemove: groupID)
        delegate?.groupManagerNeedsPersistence(self)
        persistEmptyGroups = false
        objectWillChange.send()
    }

    private func parkAllGroupedWindowsAsUnresolved() {
        let windows = groups.flatMap(\.windows)
        guard !windows.isEmpty else { return }
        for window in windows {
            parkAsUnresolved(window, persist: false)
        }
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    private func parkAsUnresolved(_ window: ManagedCursorWindow, persist: Bool) {
        knownElementTokens.remove(CFHash(window.element))
        consecutiveMisses[window.id] = nil
        guard let group = group(containing: window.id) else {
            ungroupedWindows.removeAll { $0.id == window.id }
            return
        }
        let reference = window.persistedReference()
        if !group.unresolved.contains(where: { $0.id == reference.id }) {
            group.unresolved.append(reference)
        }
        let next = GroupLogic.nextActiveID(
            afterClosing: window.id,
            orderedIDs: group.windows.map(\.id),
            current: group.activeWindowID
        )
        group.windows.removeAll { $0.id == window.id }
        group.activeWindowID = group.windows.isEmpty ? nil : next
        group.objectWillChange.send()
        if persist {
            delegate?.groupManagerNeedsPersistence(self)
        }
        objectWillChange.send()
    }

    @discardableResult
    private func reconnectUnresolved(using unmatched: inout [AXWindowSnapshot]) -> Bool {
        let pending = groups.flatMap { group in group.unresolved.map { (groupID: group.id, ref: $0) } }
        guard !pending.isEmpty, !unmatched.isEmpty else { return false }

        let live = unmatched.map { (title: $0.title, projectDisplayName: $0.projectDisplayName) }
        let assignments = WindowMatcher.match(persisted: pending.map(\.ref), live: live)
        var used = Set<Int>()
        var reconnected = false

        for item in pending {
            guard let liveIndex = assignments[item.ref.id], !used.contains(liveIndex) else { continue }
            used.insert(liveIndex)
            let snapshot = unmatched[liveIndex]
            guard let group = groups.first(where: { $0.id == item.groupID }) else { continue }
            let restored = ManagedCursorWindow(id: item.ref.id, snapshot: snapshot, alias: item.ref.alias)
            group.windows.append(restored)
            group.unresolved.removeAll { $0.id == item.ref.id }
            if group.activeWindowID == nil {
                group.activeWindowID = restored.id
            }
            consecutiveMisses[restored.id] = 0
            knownElementTokens.insert(CFHash(restored.element))
            group.objectWillChange.send()
            reconnected = true
        }

        if !used.isEmpty {
            unmatched = unmatched.enumerated().compactMap { used.contains($0.offset) ? nil : $0.element }
        }
        return reconnected
    }

    @discardableResult
    private func reconnectUngroupedWindows() -> Bool {
        let pending = groups.flatMap { group in group.unresolved.map { (groupID: group.id, ref: $0) } }
        guard !pending.isEmpty, !ungroupedWindows.isEmpty else { return false }

        let live = ungroupedWindows.map { (title: $0.title, projectDisplayName: $0.projectDisplayName) }
        let assignments = WindowMatcher.match(persisted: pending.map(\.ref), live: live)
        var pairs: [(PersistedWindowReference, ManagedCursorWindow, UUID)] = []
        var used = Set<Int>()
        for item in pending {
            guard let index = assignments[item.ref.id],
                  !used.contains(index),
                  index < ungroupedWindows.count else { continue }
            used.insert(index)
            pairs.append((item.ref, ungroupedWindows[index], item.groupID))
        }
        for (ref, window, groupID) in pairs {
            reconnect(persisted: ref, to: window, in: groupID, applyFrame: false)
        }
        return !pairs.isEmpty
    }

    private func markClosed(_ window: ManagedCursorWindow) {
        window.isClosed = true
        window.isUnavailable = true
        knownElementTokens.remove(CFHash(window.element))
        consecutiveMisses[window.id] = nil
        guard group(containing: window.id) != nil else {
            ungroupedWindows.removeAll { $0.id == window.id }
            objectWillChange.send()
            return
        }
        parkAsUnresolved(window, persist: true)
    }

    private func applyCanonicalFrame(in group: RuntimeWindowGroup, raising active: ManagedCursorWindow?) {
        guard !group.isPaused, !group.isFullScreenPaused else { return }
        group.isApplyingSynchronizedFrame = true
        group.suppressAXUntil = Date().addingTimeInterval(0.5)
        defer { group.isApplyingSynchronizedFrame = false }
        for window in group.liveWindows {
            applyFrameIfNeeded(group.synchronizedFrame, to: window)
        }
        if let active {
            FocusCoordinator.activate(window: active, discovery: discovery, accessibility: accessibility)
        }
        group.objectWillChange.send()
    }

    private func ensureTabRoom(for groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }),
              !group.isPaused,
              !group.isFullScreenPaused else { return }
        let fitted = frameLeavingTabRoom(group.synchronizedFrame)
        guard !ScreenCoordinateConverter.framesApproximatelyEqual(
            fitted,
            group.synchronizedFrame,
            tolerance: 1
        ) else { return }

        group.synchronizedFrame = fitted
        applyCanonicalFrame(in: group, raising: nil)
        delegate?.groupManagerNeedsPersistence(self)
    }

    private func frameLeavingTabRoom(_ frame: CGRect) -> CGRect {
        let screen = NSScreen.screens.max {
            $0.frame.intersection(frame).standardizedArea
                < $1.frame.intersection(frame).standardizedArea
        } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return frame }
        return ScreenCoordinateConverter.contentFrameLeavingTabRoom(
            frame,
            tabHeight: delegate?.tabHeight ?? 36,
            visibleFrame: visibleFrame
        )
    }

    private func safeRestoreFrame(
        persisted: CGRect,
        liveMembers: [ManagedCursorWindow]
    ) -> CGRect {
        if let bestLive = bestVisibleLiveWindow(in: liveMembers) {
            if CSLog.debugEnabled {
                CSLog.group.info(
                    "Restore using live frame \(String(describing: bestLive.frame), privacy: .public) instead of persisted \(String(describing: persisted), privacy: .public)"
                )
            }
            return frameLeavingTabRoom(bestLive.frame)
        }

        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let recovered = ScreenCoordinateConverter.recoveredFrame(
            persisted,
            visibleFrames: visibleFrames
        )
        if CSLog.debugEnabled,
           !ScreenCoordinateConverter.framesApproximatelyEqual(persisted, recovered) {
            CSLog.group.info(
                "Recovered off-screen group frame \(String(describing: persisted), privacy: .public) to \(String(describing: recovered), privacy: .public)"
            )
        }
        return frameLeavingTabRoom(recovered)
    }

    private func bestVisibleLiveWindow(
        in windows: [ManagedCursorWindow]
    ) -> ManagedCursorWindow? {
        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let best = windows.max { lhs, rhs in
            let lhsScore = ScreenCoordinateConverter.visibleFraction(
                of: lhs.frame,
                in: visibleFrames
            ) + ((lhs.isFocused || lhs.isMain) ? 0.01 : 0)
            let rhsScore = ScreenCoordinateConverter.visibleFraction(
                of: rhs.frame,
                in: visibleFrames
            ) + ((rhs.isFocused || rhs.isMain) ? 0.01 : 0)
            return lhsScore < rhsScore
        }
        guard let best,
              ScreenCoordinateConverter.visibleFraction(
                  of: best.frame,
                  in: visibleFrames
              ) >= 0.1 else {
            return nil
        }
        return best
    }

    private func applyFrameIfNeeded(_ frame: CGRect, to window: ManagedCursorWindow) {
        if ScreenCoordinateConverter.framesApproximatelyEqual(window.frame, frame) {
            return
        }
        do {
            try accessibility.setFrame(frame, of: window.snapshot)
            window.frame = frame
        } catch {
            CSLog.ax.error("Failed to set frame for \(window.displayName, privacy: .public)")
        }
    }

    private func findWindow(pid: pid_t, element: AXUIElement) -> ManagedCursorWindow? {
        allManagedWindows.first { window in
            window.pid == pid && AXHelpers.equal(window.element, element)
        } ?? allManagedWindows.first { AXHelpers.equal($0.element, element) }
    }
}

private extension CGRect {
    var standardizedArea: CGFloat {
        let rect = standardized
        return max(0, rect.width) * max(0, rect.height)
    }
}
