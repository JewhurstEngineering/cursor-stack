import AppKit
import Foundation

struct DiscoveredCursorApp {
    var runningApplication: NSRunningApplication
    var pid: pid_t { runningApplication.processIdentifier }
    var name: String { runningApplication.localizedName ?? "Cursor" }
    var bundleIdentifier: String { runningApplication.bundleIdentifier ?? "" }
}

enum CursorAppIdentity {
    static let editorBundleIDs: Set<String> = [
        "com.todesktop.230313mzl4w4u92"
    ]

    static func matches(
        bundleID: String?,
        localizedName: String?,
        bundleFileName: String?,
        activationPolicy: NSApplication.ActivationPolicy,
        excludingBundleID: String?
    ) -> Bool {
        if let excludingBundleID, bundleID == excludingBundleID {
            return false
        }
        guard activationPolicy == .regular else {
            return false
        }

        let bundle = (bundleID ?? "").lowercased()
        let name = (localizedName ?? "").lowercased()
        let file = (bundleFileName ?? "").lowercased()

        if name.contains("cursorstack") || bundle.contains("cursorstack") {
            return false
        }
        if bundle.hasPrefix("com.apple.") || bundle.hasSuffix(".xpc") {
            return false
        }
        if bundle.contains(".helper") || name.contains("helper") || file.contains("helper") {
            return false
        }
        if editorBundleIDs.contains(bundle) {
            return true
        }
        if file == "cursor.app" {
            return true
        }
        if name == "cursor" {
            return true
        }
        if name.hasPrefix("cursor ") {
            return true
        }
        return false
    }
}

final class CursorDiscoveryService {
    func cursorApplications() -> [DiscoveredCursorApp] {
        NSWorkspace.shared.runningApplications.compactMap { app in
            guard isCursor(app) else { return nil }
            return DiscoveredCursorApp(runningApplication: app)
        }
    }

    func isCursor(_ app: NSRunningApplication) -> Bool {
        CursorAppIdentity.matches(
            bundleID: app.bundleIdentifier,
            localizedName: app.localizedName,
            bundleFileName: app.bundleURL?.lastPathComponent,
            activationPolicy: app.activationPolicy,
            excludingBundleID: Bundle.main.bundleIdentifier
        )
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
