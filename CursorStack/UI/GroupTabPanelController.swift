import AppKit
import SwiftUI

@MainActor
final class GroupTabPanelController: NSObject {
    let groupID: UUID
    private let panel: NSPanel
    private let hosting: NSHostingView<TabStripView>
    private weak var app: ApplicationController?

    init(group: RuntimeWindowGroup, app: ApplicationController) {
        self.groupID = group.id
        self.app = app
        let root = TabStripView(groupID: group.id, app: app)
        let hosting = NSHostingView(rootView: root)
        self.hosting = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 36),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 2)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.contentView = hosting
        panel.isMovableByWindowBackground = false
        self.panel = panel
        super.init()
        align(to: group.synchronizedFrame, tabHeight: app.settingsStore.settings.tabHeight)
        panel.orderFrontRegardless()
    }

    func align(to windowFrame: CGRect, tabHeight: CGFloat) {
        let screen = NSScreen.screens.max {
            $0.frame.intersection(windowFrame).area < $1.frame.intersection(windowFrame).area
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? windowFrame
        let frame = ScreenCoordinateConverter.tabPanelFrame(
            windowFrame: windowFrame,
            height: tabHeight,
            visibleFrame: visible
        )
        panel.setFrame(frame, display: true)
        if let app {
            hosting.rootView = TabStripView(groupID: groupID, app: app)
        }
        panel.orderFrontRegardless()
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
