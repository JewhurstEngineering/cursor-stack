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
    private var didRelocateThisCycle = false

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
        didRelocateThisCycle = false
    }

    func poll(window: ManagedCursorWindow) -> AttentionObservation? {
        guard monitored.contains(window.id) else { return nil }
        let justEnabled = enableChatAccessibility(pid: window.pid)
        if let region = regions[window.id], ChatControlScanner.isAlive(region) {
            return publish(Self.observation(from: ChatControlScanner.readLabels(in: region)), for: window)
        }
        regions[window.id] = nil

        if !justEnabled, let retry = retryAfter[window.id], retry > Date() {
            return publish(Self.unreadable(), for: window)
        }
        guard !didRelocateThisCycle else {
            return publish(Self.unreadable(), for: window)
        }
        didRelocateThisCycle = true

        guard let located = ChatControlScanner.locateRegion(in: window.element) else {
            retryAfter[window.id] = Date().addingTimeInterval(20)
            return publish(Self.unreadable(), for: window)
        }
        retryAfter[window.id] = nil
        regions[window.id] = located.region
        return publish(Self.observation(from: located.read), for: window)
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

    private func publish(_ observation: AttentionObservation, for window: ManagedCursorWindow) -> AttentionObservation {
        if CSLog.debugEnabled {
            CSLog.attention.debug("chat control \(window.displayName, privacy: .public): \(observation.state.rawValue, privacy: .public)")
        }
        onStateChanged?(window.id, observation)
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
    private var composerReadInFlight = false
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
    }

    func prune(keeping ids: Set<UUID>) {
        for id in Array(monitoredWindows.keys) where !ids.contains(id) {
            if let window = monitoredWindows[id] {
                stop(window: window)
            }
        }
    }

    func poll(selectedWindowID: UUID?) {
        guard settings.detectAttention else { return }
        guard !composerReadInFlight else { return }
        composerReadInFlight = true
        let selected = selectedWindowID
        composerReader.load { [weak self] snapshot in
            guard let self else { return }
            self.composerReadInFlight = false
            self.apply(snapshot, selectedWindowID: selected)
        }
    }

    private func apply(_ snapshot: ComposerActivitySnapshot, selectedWindowID: UUID?) {
        accessibilityProvider.beginCycle()
        for window in monitoredWindows.values {
            if snapshot.readable, let state = ComposerActivity.state(
                matching: window.title,
                workspaces: snapshot.workspaces,
                headers: snapshot.headers
            ) {
                if CSLog.debugEnabled {
                    CSLog.attention.debug("composer \(window.displayName, privacy: .public): \(state.rawValue, privacy: .public)")
                }
                handle(windowID: window.id, observation: AttentionObservation(
                    state: state,
                    confidence: 0.9,
                    source: .composer
                ))
                continue
            }
            _ = accessibilityProvider.poll(window: window)
            if settings.enableVisualDetection, window.id != selectedWindowID {
                _ = visualProvider.poll(window: window)
            }
        }
    }

    func markViewedIfAppropriate(_ window: ManagedCursorWindow) {
        // The tab mark follows the live chat control, including after this window is selected.
        _ = window
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
