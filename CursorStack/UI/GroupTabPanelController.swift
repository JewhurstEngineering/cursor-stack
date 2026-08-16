import AppKit
import SwiftUI

final class MovableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { true }
}

final class TabChromeWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class GroupTabPanelController: NSObject, NSWindowDelegate {
    let groupID: UUID
    private let window: TabChromeWindow
    private let hosting: MovableHostingView<TabStripView>
    private weak var app: ApplicationController?
    private var isAligning = false
    private(set) var isUserMoving = false
    private let moveEndDebouncer = Debouncer(delay: 0.16)

    init(group: RuntimeWindowGroup, app: ApplicationController) {
        self.groupID = group.id
        self.app = app
        let root = TabStripView(group: group, app: app)
        let hosting = MovableHostingView(rootView: root)
        self.hosting = hosting

        let window = TabChromeWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 36),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.hasShadow = false
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = false
        window.isMovable = true
        window.isMovableByWindowBackground = true
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        window.contentView = hosting
        self.window = window
        super.init()
        align(to: group.synchronizedFrame, tabHeight: app.settingsStore.settings.tabHeight)
        refreshContent()
        window.orderFrontRegardless()
        window.delegate = self
        if CSLog.debugEnabled {
            CSLog.ui.info(
                "Created tab chrome group=\(group.id.uuidString, privacy: .public) frame=\(String(describing: window.frame), privacy: .public) level=\(window.level.rawValue)"
            )
        }
    }

    func align(to windowFrame: CGRect, tabHeight: CGFloat) {
        guard !isUserMoving else { return }
        let screen = NSScreen.screens.max {
            $0.frame.intersection(windowFrame).area < $1.frame.intersection(windowFrame).area
        } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? windowFrame
        var frame = ScreenCoordinateConverter.tabPanelFrame(
            windowFrame: windowFrame,
            height: tabHeight,
            visibleFrame: visible
        )
        frame.size.height = max(24, tabHeight)
        window.contentMinSize = NSSize(width: 120, height: frame.height)
        window.contentMaxSize = NSSize(width: 20_000, height: frame.height)
        guard !ScreenCoordinateConverter.framesApproximatelyEqual(window.frame, frame, tolerance: 1) else {
            return
        }
        if CSLog.debugEnabled {
            CSLog.ui.info(
                "Align tab chrome source=\(String(describing: windowFrame), privacy: .public) target=\(String(describing: frame), privacy: .public)"
            )
        }
        isAligning = true
        window.setFrame(frame, display: true, animate: false)
        isAligning = false
    }

    func refreshContent() {
        guard let app,
              let group = app.groupManager.groups.first(where: { $0.id == groupID }) else { return }
        hosting.rootView = TabStripView(group: group, app: app)
    }

    func setHidden(_ hidden: Bool) {
        if hidden {
            window.orderOut(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    func followFrontmostApp(raise: Bool) {
        if raise {
            window.level = .floating
            window.orderFrontRegardless()
        } else {
            window.level = .normal
        }
    }

    func close() {
        moveEndDebouncer.cancel()
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }

    func windowDidMove(_ notification: Notification) {
        handleUserChromeChange()
    }

    func windowDidResize(_ notification: Notification) {
        handleUserChromeChange()
    }

    private func handleUserChromeChange() {
        guard !isAligning else { return }
        guard NSEvent.pressedMouseButtons != 0 else { return }
        isUserMoving = true
        app?.chromeDidMove(groupID: groupID, panelFrame: window.frame)
        moveEndDebouncer.run { [weak self] in
            guard let self else { return }
            self.isUserMoving = false
            self.app?.chromeMoveEnded()
        }
    }
}

private extension CGRect {
    var area: CGFloat { width * height }
}
