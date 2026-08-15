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
    private let resizeDebouncer = Debouncer(delay: 0.03)
    private var knownElementTokens = Set<UInt>()

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

        let canonical = frame ?? unique.first(where: { $0.isFocused || $0.isMain })?.frame ?? unique[0].frame
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

            for member in record.members {
                if let index = assignments[member.id] {
                    let window = remaining[index]
                    let restored = ManagedCursorWindow(id: member.id, snapshot: window.snapshot, alias: member.alias)
                    members.append(restored)
                } else {
                    // Keep an unavailable placeholder so the user can reconnect.
                    continue
                }
            }

            remaining.removeAll { candidate in
                members.contains { AXHelpers.equal($0.element, candidate.element) }
            }

            guard !members.isEmpty else { continue }
            let group = RuntimeWindowGroup(
                id: record.id,
                name: record.name,
                windows: members,
                activeWindowID: record.activeMemberID,
                synchronizedFrame: record.frame.cgRect,
                isPaused: record.settings.isPaused
            )
            groups.append(group)
            applyCanonicalFrame(in: group, raising: group.activeWindow)
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

        guard window.id == group.activeWindowID else {
            applyFrameIfNeeded(group.synchronizedFrame, to: window)
            return
        }

        group.synchronizedFrame = newFrame
        let generation = group.synchronizationGeneration &+ 1
        group.synchronizationGeneration = generation
        resizeDebouncer.run { [weak self] in
            guard let self else { return }
            guard generation == group.synchronizationGeneration else { return }
            self.synchronizeFrame(newFrame, in: group.id)
        }
        group.objectWillChange.send()
    }

    func synchronizeFrame(_ frame: CGRect, in groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        guard !group.isPaused, !group.isFullScreenPaused else { return }
        group.synchronizedFrame = frame
        applyCanonicalFrame(in: group, raising: nil)
        delegate?.groupManagerNeedsPersistence(self)
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
        let tabHeight = delegate?.tabHeight ?? 44
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
        let tabHeight = delegate?.tabHeight ?? 44
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

    func closeActiveWindow(in groupID: UUID) {
        guard let group = groups.first(where: { $0.id == groupID }),
              let active = group.activeWindow else { return }
        closeCursorWindow(active.id)
    }

    func moveGroup(_ groupID: UUID, matchingTabPanel panelFrame: CGRect) {
        guard let group = groups.first(where: { $0.id == groupID }) else { return }
        guard !group.isApplyingSynchronizedFrame else { return }
        let height = max(group.synchronizedFrame.height, 200)
        let newFrame = CGRect(
            x: panelFrame.minX,
            y: panelFrame.minY - height,
            width: panelFrame.width,
            height: height
        )
        group.synchronizedFrame = newFrame
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

        if group.windows.isEmpty {
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
        if let window = allManagedWindows.first(where: { AXHelpers.equal($0.element, element) }) {
            markClosed(window)
        }
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

        for window in allManagedWindows {
            if let index = unmatched.firstIndex(where: { AXHelpers.equal($0.element, window.element) }) {
                window.apply(unmatched.remove(at: index))
            } else if !window.isClosed {
                window.isUnavailable = true
            }
        }

        for snapshot in unmatched {
            let token = CFHash(snapshot.element)
            if knownElementTokens.contains(token) { continue }
            knownElementTokens.insert(token)
            let window = ManagedCursorWindow(snapshot: snapshot)
            ungroupedWindows.append(window)
            delegate?.groupManager(self, didDetectNewWindow: window)
        }

        for group in groups {
            let closed = group.windows.filter { window in
                !snapshots.contains { AXHelpers.equal($0.element, window.element) }
            }
            for window in closed {
                markClosed(window)
            }
        }

        objectWillChange.send()
    }

    func refreshFromAccessibility() {
        var snapshots: [AXWindowSnapshot] = []
        for app in discovery.cursorApplications() {
            if let windows = try? accessibility.windows(for: app.pid) {
                snapshots.append(contentsOf: windows)
            }
        }
        ingestLiveWindows(snapshots)
    }

    func persistableGroups() -> [CursorWindowGroup] {
        groups.map(\.persisted)
    }

    func group(containing windowID: UUID) -> RuntimeWindowGroup? {
        groups.first { group in group.windows.contains { $0.id == windowID } }
    }

    func removeGroup(_ groupID: UUID) {
        groups.removeAll { $0.id == groupID }
        delegate?.groupManager(self, didRemove: groupID)
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    private func markClosed(_ window: ManagedCursorWindow) {
        window.isClosed = true
        window.isUnavailable = true
        guard let group = group(containing: window.id) else {
            ungroupedWindows.removeAll { $0.id == window.id }
            objectWillChange.send()
            return
        }
        let next = GroupLogic.nextActiveID(
            afterClosing: window.id,
            orderedIDs: group.windows.map(\.id),
            current: group.activeWindowID
        )
        group.windows.removeAll { $0.id == window.id }
        if group.windows.isEmpty {
            removeGroup(group.id)
            return
        }
        group.activeWindowID = next
        if let next, let nextWindow = group.windows.first(where: { $0.id == next }) {
            FocusCoordinator.activate(window: nextWindow, discovery: discovery, accessibility: accessibility)
        }
        group.objectWillChange.send()
        delegate?.groupManagerNeedsPersistence(self)
        objectWillChange.send()
    }

    private func applyCanonicalFrame(in group: RuntimeWindowGroup, raising active: ManagedCursorWindow?) {
        guard !group.isPaused, !group.isFullScreenPaused else { return }
        group.isApplyingSynchronizedFrame = true
        defer { group.isApplyingSynchronizedFrame = false }
        for window in group.liveWindows {
            applyFrameIfNeeded(group.synchronizedFrame, to: window)
        }
        if let active {
            FocusCoordinator.activate(window: active, discovery: discovery, accessibility: accessibility)
        }
        group.objectWillChange.send()
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
