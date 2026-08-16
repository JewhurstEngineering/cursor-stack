import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var shared: AppDelegate?
    private(set) var controller: ApplicationController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("CursorStack: applicationDidFinishLaunching")
        AppDelegate.shared = self
        let controller = ApplicationController()
        self.controller = controller
        buildMenu()
        controller.start()
        NSApp.activate()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.handleReopen()
        return true
    }

    @objc func showAbout() {
        let credits = NSAttributedString(
            string: "Groups Cursor windows into a tabbed stack.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "CursorStack",
            .credits: credits
        ])
    }

    @objc func showSettings() {
        MainActor.assumeIsolated {
            controller?.showSettings()
        }
    }

    @objc func showWindowPicker() {
        MainActor.assumeIsolated {
            controller?.showWindowPicker(addingTo: nil)
        }
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "About CursorStack", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit CursorStack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        let groupItem = NSMenuItem()
        mainMenu.addItem(groupItem)
        let groupMenu = NSMenu(title: "Group")
        let manage = NSMenuItem(title: "Manage Windows…", action: #selector(showWindowPicker), keyEquivalent: "n")
        manage.target = self
        groupMenu.addItem(manage)
        groupItem.submenu = groupMenu

        NSApp.mainMenu = mainMenu
    }
}
