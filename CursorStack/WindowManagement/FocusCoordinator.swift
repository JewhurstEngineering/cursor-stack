import Foundation

enum FocusCoordinator {
    @MainActor
    static func activate(
        window: ManagedCursorWindow,
        discovery: CursorDiscoveryService,
        accessibility: AccessibilityService
    ) {
        discovery.activateCursor(pid: window.pid)
        do {
            try accessibility.raise(window.snapshot)
            try accessibility.focus(window.snapshot)
        } catch {
            CSLog.ax.error("Failed to raise \(window.displayName, privacy: .public)")
        }
    }
}
