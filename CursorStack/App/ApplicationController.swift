import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ApplicationController: NSObject, ObservableObject {
    let permissionManager = AccessibilityPermissionManager()
    let discovery = CursorDiscoveryService()
    let accessibility = AccessibilityService()
    let settingsStore = AppSettingsStore()
    let groupStore = GroupStore()
    let launchAtLogin = LaunchAtLoginManager()
    let notifications = NotificationCoordinator()
    let attention = AttentionCoordinator()
    let observer = AXObserverManager()

    override init() {
        super.init()
    }

    lazy var groupManager: GroupManager = {
        GroupManager(accessibility: accessibility, discovery: discovery)
    }()

    private var hotKeys: HotKeyManager?
    private var tabPanels: [UUID: GroupTabPanelController] = [:]
    private var reconcileTimer: Timer?
    private var attentionTimer: Timer?
    private var permissionTimer: Timer?
    private var settingsWindow: NSWindow?
    private var pickerWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var inspectorWindow: NSWindow?
    private var labWindow: NSWindow?
    private var menuBar: MenuBarController?
    private var newWindowPrompted = Set<UUID>()

    @Published var permissionGranted = false
    @Published var pickerTargetGroupID: UUID?

    var tabHeight: CGFloat { settingsStore.settings.tabHeight }

    func start() {
        applyActivationPolicy()
        groupManager.delegate = self
        attention.configure()
        attention.settings = settingsStore.settings
        attention.isWindowSelected = { [weak self] windowID in
            self?.groupManager.groups.contains { $0.activeWindowID == windowID } ?? false
        }
        attention.onNotify = { [weak self] window, _ in
            self?.notifyIfNeeded(window: window)
        }
        notifications.onActivate = { [weak self] groupID, windowID in
            self?.activate(windowID: windowID, in: groupID)
        }
        notifications.start()

        observer.onEvent = { [weak self] pid, element, notification in
            self?.handleAXEvent(pid: pid, element: element, notification: notification)
        }

        let hotKeys = HotKeyManager(settings: settingsStore.settings)
        hotKeys.onNextTab = { [weak self] in
            guard let self, let group = self.groupManager.preferredGroup() else { return }
            self.groupManager.cycle(in: group, delta: 1)
        }
        hotKeys.onPreviousTab = { [weak self] in
            guard let self, let group = self.groupManager.preferredGroup() else { return }
            self.groupManager.cycle(in: group, delta: -1)
        }
        hotKeys.onNumberedTab = { [weak self] number in
            self?.groupManager.activateNumberedTab(number)
        }
        hotKeys.start()
        self.hotKeys = hotKeys

        menuBar = MenuBarController(app: self)
        menuBar?.reload()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        permissionGranted = permissionManager.isTrusted
        if permissionGranted {
            beginWindowManagement()
        } else {
            showOnboarding()
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.checkPermission()
                }
            }
        }

        NSApp.activate()
        NSLog("CursorStack: started (accessibility=%@)", permissionGranted ? "yes" : "no")

        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        attentionTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.attention.poll() }
        }
    }

    func handleReopen() {
        if !permissionGranted {
            showOnboarding()
        } else if groupManager.groups.isEmpty {
            showWindowPicker(addingTo: nil)
        } else {
            showSettings()
        }
    }

    func requestAccessibility() {
        permissionManager.promptIfNeeded()
        permissionManager.openSystemSettings()
    }

    func activate(windowID: UUID, in groupID: UUID) {
        groupManager.activate(windowID: windowID, in: groupID)
        if let window = groupManager.group(containing: windowID)?.windows.first(where: { $0.id == windowID }) {
            attention.markViewedIfAppropriate(window)
        }
        realignPanels()
    }

    func showWindowPicker(addingTo groupID: UUID?) {
        pickerTargetGroupID = groupID
        groupManager.refreshFromAccessibility()
        let view = WindowPickerView(app: self)
        present(window: &pickerWindow, title: "CursorStack", size: NSSize(width: 420, height: 460), view: AnyView(view))
    }

    func showSettings() {
        let view = SettingsView(app: self)
        present(window: &settingsWindow, title: "CursorStack Settings", size: NSSize(width: 560, height: 520), view: AnyView(view))
    }

    func showInspector() {
        let view = InspectorView(app: self)
        present(window: &inspectorWindow, title: "Cursor Accessibility Inspector", size: NSSize(width: 720, height: 560), view: AnyView(view))
    }

    func showWindowLab() {
        groupManager.refreshFromAccessibility()
        let view = WindowLabView(app: self)
        present(window: &labWindow, title: "CursorStack Window Lab", size: NSSize(width: 480, height: 420), view: AnyView(view))
    }

    func createGroup(name: String, windowIDs: [UUID]) {
        let windows = (groupManager.ungroupedWindows + groupManager.groups.flatMap(\.windows))
            .filter { windowIDs.contains($0.id) }
        guard !windows.isEmpty else { return }
        groupManager.createGroup(name: name, windows: windows)
        pickerWindow?.close()
    }

    func addSelectedWindows(_ windowIDs: [UUID], to groupID: UUID) {
        let windows = groupManager.ungroupedWindows.filter { windowIDs.contains($0.id) }
        groupManager.add(windows: windows, to: groupID)
        pickerWindow?.close()
    }

    func promptRenameGroup(_ group: RuntimeWindowGroup) {
        let alert = NSAlert()
        alert.messageText = "Rename Group"
        alert.informativeText = group.name
        let field = NSTextField(string: group.name)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            groupManager.renameGroup(group.id, to: field.stringValue)
        }
    }

    func promptRenameTab(_ window: ManagedCursorWindow) {
        let alert = NSAlert()
        alert.messageText = "Rename Tab"
        alert.informativeText = window.title
        let field = NSTextField(string: window.alias ?? window.displayName)
        field.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            groupManager.renameTab(window.id, alias: field.stringValue)
        }
    }

    func handleTabDrop(providers: [NSItemProvider], onto targetID: UUID, in groupID: UUID) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
            let raw: String?
            if let data = item as? Data {
                raw = String(data: data, encoding: .utf8)
            } else {
                raw = item as? String
            }
            guard let raw, let moved = UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
            Task { @MainActor in
                guard let group = self.groupManager.groups.first(where: { $0.id == groupID }),
                      let dest = group.windows.firstIndex(where: { $0.id == targetID }) else { return }
                self.groupManager.reorder(in: groupID, moving: moved, to: dest)
            }
        }
        return true
    }

    func openNewCursorWindow() {
        discovery.activateCursor(pid: discovery.cursorApplications().first?.pid ?? 0)
        let source = CGEventSource(stateID: .hidSystemState)
        func post(key: CGKeyCode, down: Bool) {
            let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down)
            event?.flags = [.maskCommand, .maskShift]
            event?.post(tap: .cghidEventTap)
        }
        post(key: 45, down: true) // N
        post(key: 45, down: false)
    }

    func resetSavedGroups() {
        groupStore.reset()
        for group in groupManager.groups {
            groupManager.ungroupAll(group.id)
        }
    }

    func applySettingsSideEffects() {
        attention.settings = settingsStore.settings
        hotKeys?.update(settings: settingsStore.settings)
        applyActivationPolicy()
        launchAtLogin.apply(enabled: settingsStore.settings.launchAtLogin)
        menuBar?.reload()
        realignPanels()
        objectWillChange.send()
    }

    func dumpAXTree(for window: ManagedCursorWindow) -> String {
        AXTreeInspector.dump(element: window.element)
    }

    private func beginWindowManagement() {
        permissionGranted = true
        onboardingWindow?.close()
        attachObservers()
        groupManager.refreshFromAccessibility()
        let persisted = groupStore.load()
        if !persisted.isEmpty {
            groupManager.restore(persisted: persisted, live: groupManager.ungroupedWindows)
        }
        if groupManager.groups.isEmpty {
            showWindowPicker(addingTo: nil)
        }
        startAttentionForAll()
        realignPanels()
        menuBar?.reload()
    }

    private func checkPermission() {
        let trusted = permissionManager.isTrusted
        if trusted && !permissionGranted {
            permissionTimer?.invalidate()
            beginWindowManagement()
        }
        permissionGranted = trusted
    }

    private func attachObservers() {
        observer.stopAll()
        for app in discovery.cursorApplications() {
            observer.observe(pid: app.pid, appElement: accessibility.applicationElement(pid: app.pid))
        }
    }

    private func reconcile() {
        guard permissionGranted else { return }
        attachObservers()
        groupManager.refreshFromAccessibility()
        startAttentionForAll()
        realignPanels()
        menuBar?.reload()
    }

    private func startAttentionForAll() {
        attention.stopAll()
        for window in groupManager.groups.flatMap(\.windows) {
            attention.start(window: window)
        }
    }

    private func realignPanels() {
        let tabHeight = settingsStore.settings.tabHeight
        for group in groupManager.groups {
            if tabPanels[group.id] == nil {
                tabPanels[group.id] = GroupTabPanelController(group: group, app: self)
            }
            let frame = group.activeWindow?.frame ?? group.synchronizedFrame
            tabPanels[group.id]?.align(to: frame, tabHeight: tabHeight)
        }
        for id in tabPanels.keys where !groupManager.groups.contains(where: { $0.id == id }) {
            tabPanels[id]?.close()
            tabPanels[id] = nil
        }
    }

    private func handleAXEvent(pid: pid_t, element: AXUIElement, notification: String) {
        switch notification {
        case kAXMovedNotification as String, kAXResizedNotification as String:
            groupManager.handleFrameChange(pid: pid, element: element)
            realignPanels()
        case kAXWindowCreatedNotification as String:
            groupManager.refreshFromAccessibility()
        case kAXUIElementDestroyedNotification as String:
            groupManager.handleWindowClosed(element: element)
        case kAXFocusedWindowChangedNotification as String, kAXMainWindowChangedNotification as String:
            groupManager.handleFocusChange(pid: pid, element: element)
        case kAXTitleChangedNotification as String:
            groupManager.refreshFromAccessibility()
        case kAXWindowMiniaturizedNotification as String:
            groupManager.handleMiniaturize(element: element, minimized: true)
        case kAXWindowDeminiaturizedNotification as String:
            groupManager.handleMiniaturize(element: element, minimized: false)
        default:
            break
        }
        realignPanels()
        menuBar?.reload()
    }

    private func notifyIfNeeded(window: ManagedCursorWindow) {
        guard settingsStore.settings.sendNotifications else { return }
        if !settingsStore.settings.notifyWhenFrontmost, NSApp.isActive { return }
        guard let group = groupManager.group(containing: window.id) else { return }
        if group.activeWindowID == window.id, !settingsStore.settings.notifyForSelectedTab { return }
        notifications.notify(window: window, groupID: group.id, sound: settingsStore.settings.notificationSound)
    }

    private func promptForNewWindow(_ window: ManagedCursorWindow) {
        guard !newWindowPrompted.contains(window.id) else { return }
        newWindowPrompted.insert(window.id)
        if settingsStore.settings.autoAddNewWindows, let group = groupManager.preferredGroup() {
            groupManager.add(windows: [window], to: group.id)
            return
        }

        let alert = NSAlert()
        alert.messageText = "New Cursor window detected"
        alert.informativeText = window.displayName
        if let group = groupManager.preferredGroup() {
            alert.addButton(withTitle: "Add to \(group.name)")
        }
        alert.addButton(withTitle: "New Group")
        alert.addButton(withTitle: "Ignore")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, let group = groupManager.preferredGroup() {
            groupManager.add(windows: [window], to: group.id)
        } else if (groupManager.preferredGroup() == nil && response == .alertFirstButtonReturn) ||
                    (groupManager.preferredGroup() != nil && response == .alertSecondButtonReturn) {
            groupManager.createGroup(name: window.displayName, windows: [window])
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(settingsStore.settings.showDockIcon ? .regular : .accessory)
        menuBar?.reload()
    }

    private func showOnboarding() {
        let view = OnboardingView(app: self)
        present(window: &onboardingWindow, title: "Welcome to CursorStack", size: NSSize(width: 460, height: 420), view: AnyView(view))
    }

    private func present(window: inout NSWindow?, title: String, size: NSSize, view: AnyView) {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }
        let hosted = NSHostingController(rootView: view)
        let newWindow = NSWindow(contentViewController: hosted)
        newWindow.title = title
        newWindow.setContentSize(size)
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.isReleasedWhenClosed = false
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window = newWindow
    }

    @objc private func workspaceDidWake() {
        reconcile()
    }

    @objc private func appLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              discovery.isCursor(app) else { return }
        reconcile()
    }

    @objc private func appTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              discovery.isCursor(app) else { return }
        reconcile()
    }
}

extension ApplicationController: GroupManagerDelegate {
    func groupManager(_ manager: GroupManager, didCreate group: RuntimeWindowGroup) {
        realignPanels()
        startAttentionForAll()
        menuBar?.reload()
    }

    func groupManager(_ manager: GroupManager, didRemove groupID: UUID) {
        tabPanels[groupID]?.close()
        tabPanels[groupID] = nil
        menuBar?.reload()
    }

    func groupManagerNeedsPersistence(_ manager: GroupManager) {
        groupStore.save(manager.persistableGroups())
        realignPanels()
        menuBar?.reload()
        objectWillChange.send()
    }

    func groupManager(_ manager: GroupManager, didDetectNewWindow window: ManagedCursorWindow) {
        if manager.group(containing: window.id) == nil, !manager.groups.isEmpty {
            promptForNewWindow(window)
        }
        menuBar?.reload()
    }
}
