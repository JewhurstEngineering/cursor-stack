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

    func startMonitoring(window: ManagedCursorWindow) {
        monitored.insert(window.id)
    }

    func stopMonitoring(window: ManagedCursorWindow) {
        monitored.remove(window.id)
    }

    func poll(window: ManagedCursorWindow) -> AttentionObservation? {
        guard monitored.contains(window.id) else { return nil }
        let hints = AXTreeInspector.collectAttentionHints(from: window.element)
        if CSLog.debugEnabled {
            CSLog.attention.debug("AX hints for \(window.displayName, privacy: .public): \(hints.joined(separator: " | "), privacy: .public)")
        }
        let observation = Self.interpret(hints: hints, title: window.title)
        onStateChanged?(window.id, observation)
        return observation
    }

    nonisolated static func interpret(hints: [String], title: String) -> AttentionObservation {
        let blob = (hints.joined(separator: " ") + " " + title).lowercased()
        if blob.contains("error") || blob.contains("failed") {
            return AttentionObservation(state: .error, confidence: 0.6, source: .accessibility)
        }
        if blob.contains("unread")
            || blob.contains("needs")
            || blob.contains("waiting")
            || blob.contains("action required")
            || blob.contains("keep") && blob.contains("undo") {
            return AttentionObservation(state: .attention, confidence: 0.75, source: .accessibility)
        }
        if blob.contains("stop generating") || blob.contains("generating") || (blob.contains("agent") && blob.contains("running")) {
            return AttentionObservation(state: .working, confidence: 0.5, source: .accessibility)
        }
        if blob.contains("complete") || blob.contains("finished") {
            return AttentionObservation(state: .completed, confidence: 0.4, source: .accessibility)
        }
        return AttentionObservation(state: .unknown, confidence: 0.1, source: .accessibility)
    }
}

@MainActor
final class WindowMetadataAttentionProvider: AttentionSignalProvider {
    var onStateChanged: ((UUID, AttentionObservation) -> Void)?
    private var monitored = Set<UUID>()
    private var lastTitles: [UUID: String] = [:]

    func startMonitoring(window: ManagedCursorWindow) {
        monitored.insert(window.id)
        lastTitles[window.id] = window.title
    }

    func stopMonitoring(window: ManagedCursorWindow) {
        monitored.remove(window.id)
        lastTitles[window.id] = nil
    }

    func poll(window: ManagedCursorWindow) -> AttentionObservation? {
        guard monitored.contains(window.id) else { return nil }
        let previous = lastTitles[window.id]
        lastTitles[window.id] = window.title
        var observation = Self.interpret(title: window.title)
        if let previous, previous != window.title, observation.state == .attention {
            observation.confidence = min(1, observation.confidence + 0.15)
        }
        onStateChanged?(window.id, observation)
        return observation
    }

    nonisolated static func interpret(title: String) -> AttentionObservation {
        let lower = title.lowercased()
        if title.contains("●") || title.contains("•") || lower.contains("(1)") || lower.contains("unread") {
            return AttentionObservation(state: .attention, confidence: 0.55, source: .metadata)
        }
        return AttentionObservation(state: .unknown, confidence: 0.05, source: .metadata)
    }
}

@MainActor
final class AttentionCoordinator: ObservableObject {
    @Published private(set) var states: [UUID: AttentionState] = [:]

    private let accessibilityProvider = AccessibilityAttentionProvider()
    private let metadataProvider = WindowMetadataAttentionProvider()
    private let visualProvider = VisualAttentionProvider()
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
        for window in monitoredWindows.values {
            _ = metadataProvider.poll(window: window)
            let isSelected = window.id == selectedWindowID
            if !isSelected {
                _ = accessibilityProvider.poll(window: window)
            }
            if settings.enableVisualDetection, !isSelected {
                _ = visualProvider.poll(window: window)
            }
        }
    }

    func markViewedIfAppropriate(_ window: ManagedCursorWindow) {
        if window.attentionState == .attention || window.attentionState == .error {
            // Edge-triggered providers cannot confirm the underlying signal disappeared.
            window.attentionState = .idle
            states[window.id] = .idle
            var current = tracking[window.id] ?? AttentionTrackingState()
            current.currentState = .idle
            current.lastNotifiedState = nil
            tracking[window.id] = current
            window.objectWillChange.send()
        }
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
