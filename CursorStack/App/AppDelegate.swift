import AppKit
import Sparkle
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    static weak var shared: AppDelegate?
    private(set) var controller: ApplicationController!
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("CursorStack: applicationDidFinishLaunching")
        AppDelegate.shared = self
        let controller = ApplicationController()
        self.controller = controller
        buildMenu()
        controller.start()
        NSApp.activate()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        MainActor.assumeIsolated {
            controller?.recheckAccessibilityPermission()
        }
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

    @objc func checkForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(sender)
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

    @objc func showGroupOrganizer() {
        MainActor.assumeIsolated {
            controller?.showGroupOrganizer()
        }
    }

    @objc func activateWindowFromGroupMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget else { return }
        MainActor.assumeIsolated {
            controller?.activate(windowID: target.windowID, in: target.groupID)
        }
    }

    @objc func addWindowsToCurrentStack() {
        MainActor.assumeIsolated {
            guard let group = controller?.groupManager.preferredGroup() else { return }
            controller?.showWindowPicker(addingTo: group.id)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Group" else { return }
        MainActor.assumeIsolated {
            populateGroupMenu(menu)
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
        let checkForUpdates = NSMenuItem(
            title: "Check for Updates…",
            action: #selector(checkForUpdates(_:)),
            keyEquivalent: ""
        )
        checkForUpdates.target = self
        appMenu.addItem(checkForUpdates)
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
        groupMenu.delegate = self
        groupMenu.addItem(disabledItem("Loading stacks…"))
        groupItem.submenu = groupMenu

        let settingsRootItem = NSMenuItem()
        mainMenu.addItem(settingsRootItem)
        let settingsMenu = NSMenu(title: "Settings")
        let openSettings = NSMenuItem(
            title: "Open Settings…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        openSettings.target = self
        settingsMenu.addItem(openSettings)
        settingsRootItem.submenu = settingsMenu

        NSApp.mainMenu = mainMenu
    }

    @MainActor
    private func populateGroupMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let groups = controller?.groupManager.groups ?? []
        let current = controller?.groupManager.preferredGroup()

        let newStack = NSMenuItem(
            title: "New Stack…",
            action: #selector(showWindowPicker),
            keyEquivalent: "n"
        )
        newStack.target = self
        newStack.image = NSImage(
            systemSymbolName: "plus.rectangle.on.rectangle",
            accessibilityDescription: nil
        )
        menu.addItem(newStack)

        let manageGroups = NSMenuItem(
            title: "Manage Groups and Tab Order…",
            action: #selector(showGroupOrganizer),
            keyEquivalent: ""
        )
        manageGroups.target = self
        manageGroups.image = NSImage(
            systemSymbolName: "list.bullet",
            accessibilityDescription: nil
        )
        menu.addItem(manageGroups)
        menu.addItem(.separator())

        if let current {
            menu.addItem(sectionHeader("Current Stack"))
            append(group: current, to: menu)

            let others = groups.filter { $0.id != current.id }
            if !others.isEmpty {
                menu.addItem(.separator())
                menu.addItem(sectionHeader("Other Stacks"))
                for group in others {
                    append(group: group, to: menu)
                }
            }

            menu.addItem(.separator())
            let addWindows = NSMenuItem(
                title: "Add Windows to \(current.name)…",
                action: #selector(addWindowsToCurrentStack),
                keyEquivalent: ""
            )
            addWindows.target = self
            menu.addItem(addWindows)
        } else {
            menu.addItem(disabledItem("No current stack"))
        }
    }

    @MainActor
    private func append(group: RuntimeWindowGroup, to menu: NSMenu) {
        let groupItem: NSMenuItem
        if let active = group.activeWindow {
            groupItem = NSMenuItem(
                title: group.name,
                action: #selector(activateWindowFromGroupMenu(_:)),
                keyEquivalent: ""
            )
            groupItem.target = self
            groupItem.representedObject = MenuTarget(
                groupID: group.id,
                windowID: active.id
            )
        } else {
            groupItem = disabledItem(group.name)
        }
        groupItem.image = NSImage(
            systemSymbolName: "rectangle.stack.fill",
            accessibilityDescription: nil
        )
        menu.addItem(groupItem)

        for window in group.windows {
            let title = window.attentionState.showsTabDot
                ? "● \(window.displayName)"
                : window.displayName
            let item = NSMenuItem(
                title: title,
                action: #selector(activateWindowFromGroupMenu(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = MenuTarget(
                groupID: group.id,
                windowID: window.id
            )
            item.indentationLevel = 1
            item.state = window.id == group.activeWindowID ? .on : .off
            item.isEnabled = !window.isUnavailable
            menu.addItem(item)
        }

        for unresolved in group.unresolved {
            let item = disabledItem(
                "\(unresolved.alias ?? unresolved.projectDisplayName) — reconnect needed"
            )
            item.indentationLevel = 1
            menu.addItem(item)
        }
    }

    private func sectionHeader(_ title: String) -> NSMenuItem {
        let item = disabledItem(title.uppercased())
        item.attributedTitle = NSAttributedString(
            string: title.uppercased(),
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .semibold),
                .foregroundColor: NSColor.secondaryLabelColor
            ]
        )
        return item
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
