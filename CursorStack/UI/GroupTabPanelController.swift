import AppKit
import SwiftUI

final class MovableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

@MainActor
final class GroupTabPanelController: NSObject, NSWindowDelegate {
    let groupID: UUID
    private let panel: NSPanel
    private let hosting: MovableHostingView<TabStripView>
    private weak var app: ApplicationController?
    private var isAligning = false
    private var endMoveWork: DispatchWorkItem?
    private(set) var isUserMoving = false

    init(group: RuntimeWindowGroup, app: ApplicationController) {
        self.groupID = group.id
        self.app = app
        let root = TabStripView(groupID: group.id, app: app)
        let hosting = MovableHostingView(rootView: root)
        self.hosting = hosting

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 44),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 2)
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.isOpaque = true
        panel.backgroundColor = .windowBackgroundColor
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = false
        panel.isMovableByWindowBackground = true
        panel.contentView = hosting
        self.panel = panel
        super.init()
        panel.delegate = self
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
        isAligning = true
        panel.setFrame(frame, display: true)
        isAligning = false
        if let app {
            hosting.rootView = TabStripView(groupID: groupID, app: app)
        }
        panel.orderFrontRegardless()
    }

    func setHidden(_ hidden: Bool) {
        if hidden {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.close()
    }

    func windowWillMove(_ notification: Notification) {
        isUserMoving = true
    }

    func windowDidMove(_ notification: Notification) {
        guard !isAligning, let app else { return }
        isUserMoving = true
        app.groupManager.moveGroup(groupID, matchingTabPanel: panel.frame)
        endMoveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.isUserMoving = false
            self.app?.persistGroupsAfterPanelMove()
        }
        endMoveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
