import AppKit

@MainActor
final class MenuBarController: NSObject {
    private weak var app: ApplicationController?
    private var item: NSStatusItem?

    init(app: ApplicationController) {
        super.init()
        self.app = app
    }

    func reload() {
        guard let app else { return }
        if !app.settingsStore.settings.showMenuBarIcon {
            item?.statusBar?.removeStatusItem(item!)
            item = nil
            return
        }
        if item == nil {
            item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        guard let button = item?.button else { return }

        let hasAttention = app.groupManager.groups
            .flatMap(\.windows)
            .contains { $0.attentionState.showsTabDot }
        let image = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "CursorStack")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.title = hasAttention ? "CS•" : "CS"
        button.toolTip = "CursorStack"
        item?.isVisible = true

        let menu = NSMenu()
        menu.addItem(header("CursorStack"))

        if !app.permissionGranted {
            menu.addItem(menuItem("Grant Accessibility Permission…", #selector(grantPermission)))
        }

        if app.groupManager.groups.isEmpty {
            menu.addItem(menuItem("Manage Windows…", #selector(showPicker)))
        }

        for group in app.groupManager.groups {
            menu.addItem(.separator())
            menu.addItem(header(group.name))
            for window in group.windows {
                let prefix = window.attentionState.showsTabDot ? "● " : (window.id == group.activeWindowID ? "✓ " : "    ")
                let item = NSMenuItem(
                    title: "\(prefix)\(window.displayName)",
                    action: #selector(activateFromMenu(_:)),
                    keyEquivalent: ""
                )
                item.representedObject = MenuTarget(groupID: group.id, windowID: window.id)
                item.target = self
                menu.addItem(item)
            }
        }

        let attentionWindows = app.groupManager.groups.flatMap(\.windows).filter { $0.attentionState.showsTabDot }
        if !attentionWindows.isEmpty {
            menu.addItem(.separator())
            menu.addItem(header("Needs Attention"))
            for window in attentionWindows {
                if let group = app.groupManager.group(containing: window.id) {
                    let item = NSMenuItem(title: "● \(window.displayName)", action: #selector(activateFromMenu(_:)), keyEquivalent: "")
                    item.representedObject = MenuTarget(groupID: group.id, windowID: window.id)
                    item.target = self
                    menu.addItem(item)
                }
            }
        }

        menu.addItem(.separator())
        menu.addItem(menuItem("Manage Windows…", #selector(showPicker)))
        menu.addItem(menuItem("Window Lab", #selector(showLab)))
        menu.addItem(menuItem("Settings…", #selector(showSettings)))
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit CursorStack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        item?.menu = menu
    }

    private func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func menuItem(_ title: String, _ selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func grantPermission() {
        app?.requestAccessibility()
    }

    @objc private func showPicker() {
        app?.showWindowPicker(addingTo: nil)
    }

    @objc private func showLab() {
        app?.showWindowLab()
    }

    @objc private func showSettings() {
        app?.showSettings()
    }

    @objc private func activateFromMenu(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? MenuTarget else { return }
        app?.activate(windowID: target.windowID, in: target.groupID)
    }
}

final class MenuTarget: NSObject {
    let groupID: UUID
    let windowID: UUID
    init(groupID: UUID, windowID: UUID) {
        self.groupID = groupID
        self.windowID = windowID
    }
}
