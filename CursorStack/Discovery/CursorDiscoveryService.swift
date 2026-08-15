import AppKit
import Foundation

struct DiscoveredCursorApp {
    var runningApplication: NSRunningApplication
    var pid: pid_t { runningApplication.processIdentifier }
    var name: String { runningApplication.localizedName ?? "Cursor" }
    var bundleIdentifier: String { runningApplication.bundleIdentifier ?? "" }
}

final class CursorDiscoveryService {
    func cursorApplications() -> [DiscoveredCursorApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard isCursor(app) else { return nil }
            return DiscoveredCursorApp(runningApplication: app)
        }
    }

    func isCursor(_ app: NSRunningApplication) -> Bool {
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return false
        }
        let bundle = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        if name == "cursorstack" || bundle.contains("cursorstack") {
            return false
        }
        if name == "cursor" {
            return true
        }
        if bundle.contains("cursor") {
            return true
        }
        if bundle.hasPrefix("com.todesktop."), name.contains("cursor") {
            return true
        }
        if let url = app.bundleURL, url.lastPathComponent.lowercased() == "cursor.app" {
            return true
        }
        return false
    }

    func activateCursor(pid: pid_t) {
        let app = NSRunningApplication(processIdentifier: pid)
        app?.activate(options: [.activateIgnoringOtherApps])
    }

    func openCursor() {
        if let existing = cursorApplications().first, let url = existing.runningApplication.bundleURL {
            NSWorkspace.shared.open(url)
            return
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
            NSWorkspace.shared.open(url)
            return
        }
        NSWorkspace.shared.launchApplication("Cursor")
    }
}
