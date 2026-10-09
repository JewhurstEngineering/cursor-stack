import ApplicationServices
import Foundation

@MainActor
protocol AttentionSignalProvider: AnyObject {
    func startMonitoring(window: ManagedCursorWindow)
    func stopMonitoring(window: ManagedCursorWindow)
    func poll(window: ManagedCursorWindow) -> AttentionObservation?
    var onStateChanged: ((UUID, AttentionObservation) -> Void)? { get set }
}

@MainActor
final class AccessibilityAttentionProvider: AttentionSignalProvider {
    var onStateChanged: ((UUID, AttentionObservation) -> Void)?
    private var monitored = Set<UUID>()
    private var regions: [UUID: AXUIElement] = [:]
    private var retryAfter: [UUID: Date] = [:]
    private var enhancedPIDs = Set<pid_t>()
    /// Full tree walks are expensive, so each poll only locates a few windows
    /// that do not already have a cached composer region.
    private var locatesRemaining = 0

    func startMonitoring(window: ManagedCursorWindow) {
        monitored.insert(window.id)
    }

    func stopMonitoring(window: ManagedCursorWindow) {
        monitored.remove(window.id)
        regions[window.id] = nil
        retryAfter[window.id] = nil
    }

    @discardableResult
    private func enableChatAccessibility(pid: pid_t) -> Bool {
        guard enhancedPIDs.insert(pid).inserted else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        return true
    }

    func beginCycle() {
        locatesRemaining = 3
    }

    /// Drop a cached composer region and its retry wait so the next poll walks the tree again.
    func invalidate(windowID: UUID) {
        regions[windowID] = nil
        retryAfter[windowID] = nil
    }

    func poll(window: ManagedCursorWindow) -> AttentionObservation? {
        poll(window: window, publish: true)
    }

    func poll(window: ManagedCursorWindow, publish: Bool) -> AttentionObservation? {
        guard monitored.contains(window.id) else { return nil }
        let justEnabled = enableChatAccessibility(pid: window.pid)
        if let region = regions[window.id], ChatControlScanner.isAlive(region) {
            return report(Self.observation(from: ChatControlScanner.readLabels(in: region)), for: window, publish: publish)
        }
        regions[window.id] = nil

        if !justEnabled, let retry = retryAfter[window.id], retry > Date() {
            return report(Self.unreadable(), for: window, publish: publish)
        }
        guard locatesRemaining > 0 else {
            return report(Self.unreadable(), for: window, publish: publish)
        }
        locatesRemaining -= 1

        guard let located = ChatControlScanner.locateRegion(in: window.element) else {
            retryAfter[window.id] = Date().addingTimeInterval(20)
            return report(Self.unreadable(), for: window, publish: publish)
        }
        retryAfter[window.id] = nil
        regions[window.id] = located.region
        return report(Self.observation(from: located.read), for: window, publish: publish)
    }

    nonisolated static func interpret(labels: [String], regionReadable: Bool) -> AttentionObservation {
        if labels.contains(where: { ChatControlLabel.classify($0) == .attention }) {
            return AttentionObservation(state: .attention, confidence: 0.9, source: .accessibility)
        }
        if labels.contains(where: { ChatControlLabel.classify($0) == .working }) {
            return AttentionObservation(state: .working, confidence: 0.85, source: .accessibility)
        }
        if regionReadable {
            return AttentionObservation(state: .idle, confidence: 0.8, source: .accessibility)
        }
        return unreadable()
    }

    private func report(
        _ observation: AttentionObservation,
        for window: ManagedCursorWindow,
        publish: Bool
    ) -> AttentionObservation {
        if CSLog.debugEnabled {
            CSLog.attention.debug("chat control \(window.displayName, privacy: .public): \(observation.state.rawValue, privacy: .public)")
        }
        if publish {
            onStateChanged?(window.id, observation)
        }
        return observation
    }

    private nonisolated static func observation(from read: ChatControlScanner.Read) -> AttentionObservation {
        let activity = read.labels.contains { ChatControlLabel.classify($0) != nil }
        return interpret(labels: read.labels, regionReadable: read.finished || activity)
    }

    private nonisolated static func unreadable() -> AttentionObservation {
        AttentionObservation(state: .unknown, confidence: 0.1, source: .accessibility)
    }
}

@MainActor
final class WindowMetadataAttentionProvider: AttentionSignalProvider {
    var onStateChanged: ((UUID, AttentionObservation) -> Void)?
    private var monitored = Set<UUID>()

    func startMonitoring(window: ManagedCursorWindow) {
        monitored.insert(window.id)
    }

    func stopMonitoring(window: ManagedCursorWindow) {
        monitored.remove(window.id)
    }

    func poll(window: ManagedCursorWindow) -> AttentionObservation? {
        guard monitored.contains(window.id) else { return nil }
        let observation = Self.interpret(title: window.title)
        onStateChanged?(window.id, observation)
        return observation
    }

    nonisolated static func interpret(title: String) -> AttentionObservation {
        _ = title
        return AttentionObservation(state: .unknown, confidence: 0.05, source: .metadata)
    }
}

@MainActor
final class AttentionCoordinator: ObservableObject {
    @Published private(set) var states: [UUID: AttentionState] = [:]

    private let accessibilityProvider = AccessibilityAttentionProvider()
    private let metadataProvider = WindowMetadataAttentionProvider()
    private let visualProvider = VisualAttentionProvider()
    private let composerReader = ComposerActivityReader()
    private let claudeReader = ClaudeCodeActivityReader()
    private var composerReadInFlight = false
    private var claudeReadInFlight = false
    private var finishedChats = Set<UUID>()
    /// Windows whose spinner came from the live control, not from an open composer run.
    /// A later unread tree must not clear that just because composer still says idle.
    private var liveSignals = Set<UUID>()
    /// Set by a manual refresh so that window is walked first, ahead of the locate budget.
    private var forcedWindowID: UUID?
    private var tracking: [UUID: AttentionTrackingState] = [:]
    private var monitoredWindows: [UUID: ManagedCursorWindow] = [:]

    var onNotify: ((ManagedCursorWindow, AttentionState) -> Void)?
    var settings: AppSettings = AppSettings()
    var isWindowSelected: ((UUID) -> Bool)?

    func configure() {
        let handler: (UUID, AttentionObservation) -> Void = { [weak self] id, observation in
            self?.handle(windowID: id, observation: observation)
        }
        accessibilityProvider.onStateChanged = handler
        metadataProvider.onStateChanged = handler
        visualProvider.onStateChanged = handler
    }

    func applySettings(_ settings: AppSettings) {
        self.settings = settings
        for window in monitoredWindows.values {
            if settings.enableVisualDetection {
                visualProvider.startMonitoring(window: window)
            } else {
                visualProvider.stopMonitoring(window: window)
            }
        }
    }

    func start(window: ManagedCursorWindow) {
        if monitoredWindows[window.id] == nil {
            monitoredWindows[window.id] = window
            accessibilityProvider.startMonitoring(window: window)
            metadataProvider.startMonitoring(window: window)
            if tracking[window.id] == nil {
                tracking[window.id] = AttentionTrackingState()
            }
        }
        if settings.enableVisualDetection {
            visualProvider.startMonitoring(window: window)
        }
    }

    func stop(window: ManagedCursorWindow) {
        accessibilityProvider.stopMonitoring(window: window)
        metadataProvider.stopMonitoring(window: window)
        visualProvider.stopMonitoring(window: window)
        monitoredWindows[window.id] = nil
        liveSignals.remove(window.id)
        finishedChats.remove(window.id)
    }

    func prune(keeping ids: Set<UUID>) {
        for id in Array(monitoredWindows.keys) where !ids.contains(id) {
            if let window = monitoredWindows[id] {
                stop(window: window)
            }
        }
    }

    func poll(selectedWindowID: UUID?) {
        guard settings.detectAttention else {
            clearClaudeBusy()
            return
        }
        pollComposer(selectedWindowID: selectedWindowID)
        pollClaude()
    }

    /// Forget a stuck read for one window and check it on the next pass.
    /// A cached region, a 20-second retry, and a held live spinner all get dropped.
    func refresh(windowID: UUID, selectedWindowID: UUID?) {
        guard monitoredWindows[windowID] != nil else { return }
        liveSignals.remove(windowID)
        accessibilityProvider.invalidate(windowID: windowID)
        forcedWindowID = windowID
        poll(selectedWindowID: selectedWindowID)
    }

    private func pollComposer(selectedWindowID: UUID?) {
        guard !composerReadInFlight else { return }
        composerReadInFlight = true
        let selected = selectedWindowID
        composerReader.load { [weak self] snapshot in
            guard let self else { return }
            self.composerReadInFlight = false
            self.apply(snapshot, selectedWindowID: selected)
        }
    }

    private func pollClaude() {
        guard !claudeReadInFlight else { return }
        claudeReadInFlight = true
        claudeReader.load { [weak self] snapshot in
            guard let self else { return }
            self.claudeReadInFlight = false
            self.applyClaude(snapshot)
        }
    }

    private func applyClaude(_ snapshot: ClaudeCodeSnapshot) {
        guard snapshot.readable else { return }
        for window in monitoredWindows.values {
            let busy = ClaudeCodeActivity.matches(title: window.title, sessions: snapshot.sessions)
            guard window.claudeBusy != busy else { continue }
            window.claudeBusy = busy
            window.objectWillChange.send()
            if CSLog.debugEnabled {
                CSLog.attention.debug("claude \(window.displayName, privacy: .public): \(busy ? "busy" : "idle", privacy: .public)")
            }
        }
    }

    private func clearClaudeBusy() {
        for window in monitoredWindows.values where window.claudeBusy {
            window.claudeBusy = false
            window.objectWillChange.send()
        }
    }

    private func apply(_ snapshot: ComposerActivitySnapshot, selectedWindowID: UUID?) {
        let forced = forcedWindowID
        forcedWindowID = nil
        accessibilityProvider.beginCycle()
        for window in windowsOrderedForScan(selectedFirst: selectedWindowID, forced: forced) {
            let composer = snapshot.readable ? ComposerActivity.state(
                matching: window.title,
                workspaces: snapshot.workspaces,
                headers: snapshot.headers
            ) : nil
            // An open run already recorded in composer does not need a tree walk.
            // Idle and unknown do: the visible Stop / Thinking control is often the
            // only sign that this window is actually generating.
            let live: AttentionObservation?
            if composer == .working || composer == .attention {
                live = nil
            } else {
                live = accessibilityProvider.poll(window: window, publish: false)
            }
            let resolved = AttentionSignals.resolve(composer: composer, live: live)
            if live?.state == .unknown, liveSignals.contains(window.id), composer != .working, composer != .attention {
                continue
            }
            if let resolved {
                let previous = states[window.id] ?? .unknown
                let shown = FinishedChatSignal.resolve(
                    live: resolved,
                    previous: previous,
                    holding: finishedChats.contains(window.id)
                )
                if shown.holding {
                    finishedChats.insert(window.id)
                } else {
                    finishedChats.remove(window.id)
                }
                if CSLog.debugEnabled {
                    CSLog.attention.debug("composer \(window.displayName, privacy: .public): \(shown.state.rawValue, privacy: .public)")
                }
                let fromLiveControl = live?.state == shown.state && (shown.state == .working || shown.state == .attention || shown.state == .error)
                if fromLiveControl {
                    liveSignals.insert(window.id)
                } else if shown.state != .working && shown.state != .attention && shown.state != .error {
                    liveSignals.remove(window.id)
                }
                handle(windowID: window.id, observation: AttentionObservation(
                    state: shown.state,
                    confidence: fromLiveControl ? (live?.confidence ?? 0.85) : 0.9,
                    source: fromLiveControl ? .accessibility : .composer
                ))
            }
            let covered = resolved == .working || resolved == .attention || resolved == .error
            if composer == nil, !covered, settings.enableVisualDetection, window.id != selectedWindowID {
                _ = visualProvider.poll(window: window)
            }
        }
    }

    private func windowsOrderedForScan(selectedFirst selectedWindowID: UUID?, forced forcedWindowID: UUID?) -> [ManagedCursorWindow] {
        let windows = Array(monitoredWindows.values)
        let order = Self.scanOrder(ids: windows.map(\.id), forced: forcedWindowID, selected: selectedWindowID)
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        return order.compactMap { byID[$0] }
    }

    /// The refreshed window is first, then the selected one, so a manual check is not spent on other tabs.
    nonisolated static func scanOrder(ids: [UUID], forced: UUID?, selected: UUID?) -> [UUID] {
        ids.sorted { lhs, rhs in
            rank(lhs, forced: forced, selected: selected) < rank(rhs, forced: forced, selected: selected)
        }
    }

    private nonisolated static func rank(_ id: UUID, forced: UUID?, selected: UUID?) -> Int {
        if id == forced { return 0 }
        if id == selected { return 1 }
        return 2
    }

    func markViewedIfAppropriate(_ window: ManagedCursorWindow) {
        guard finishedChats.contains(window.id), states[window.id] == .completed else { return }
        finishedChats.remove(window.id)
        handle(windowID: window.id, observation: AttentionObservation(
            state: .idle,
            confidence: 0.9,
            source: .composer
        ))
    }

    private func handle(windowID: UUID, observation: AttentionObservation) {
        guard let window = monitoredWindows[windowID] else { return }
        let previous = states[windowID] ?? .unknown

        if observation.state == .unknown, previous != .unknown {
            return
        }
        if observation.confidence < 0.4, observation.state != .attention, observation.state != .error {
            return
        }
        if states[windowID] == observation.state {
            return
        }

        states[windowID] = observation.state
        window.attentionState = observation.state
        window.objectWillChange.send()

        var current = tracking[windowID] ?? AttentionTrackingState()
        let selected = isWindowSelected?(windowID) ?? false
        let shouldNotify = AttentionDeduplicator.shouldNotify(
            tracking: &current,
            newState: observation.state,
            notifySelected: settings.notifyForSelectedTab,
            isSelected: selected
        )
        tracking[windowID] = current

        if shouldNotify {
            onNotify?(window, observation.state)
        }
    }
}
