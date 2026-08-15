import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    func apply(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            CSLog.general.error("Launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }
}
