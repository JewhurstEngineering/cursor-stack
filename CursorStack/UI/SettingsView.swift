import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: ApplicationController
    @ObservedObject private var settingsStore: AppSettingsStore
    @State private var selection: SettingsSection = .general
    @State private var installMessage: String?
    @State private var installSucceeded = false
    @State private var recordingShortcut: ShortcutTarget?

    init(app: ApplicationController) {
        self.app = app
        self._settingsStore = ObservedObject(wrappedValue: app.settingsStore)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 196)

            Divider()

            ScrollView {
                detail
                    .padding(.horizontal, 30)
                    .padding(.vertical, 26)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                BrandNameLogo(width: 146, style: .adaptive)
                Text("Window groups for Cursor")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)

            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 18)
                            Text(section.title)
                                .font(.system(size: 13, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(selection == section ? Color.accentColor : Color.primary)
                        .padding(.horizontal, 11)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == section ? Color.accentColor.opacity(0.13) : .clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(app.permissionGranted ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                Text(app.permissionGranted ? "Accessibility connected" : "Permission needed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsPageHeader(
                title: selection.title,
                detail: selection.detail,
                symbol: selection.symbol
            )

            switch selection {
            case .general:
                general
            case .tabs:
                tabs
            case .shortcuts:
                shortcuts
            case .attention:
                attention
            case .advanced:
                advanced
            }
        }
    }

    private var settings: Binding<AppSettings> {
        Binding(
            get: { settingsStore.settings },
            set: {
                settingsStore.settings = $0
                app.applySettingsSideEffects()
            }
        )
    }

    private var tabLabelStyle: Binding<TabLabelStyle> {
        Binding(
            get: {
                settingsStore.settings.showFullTitle ? .fullTitle : .projectName
            },
            set: { style in
                var updated = settingsStore.settings
                updated.showProjectName = true
                updated.showFullTitle = style == .fullTitle
                settingsStore.settings = updated
                app.applySettingsSideEffects()
            }
        )
    }

    private var appAppearance: Binding<AppAppearance> {
        Binding(
            get: { settingsStore.settings.effectiveAppAppearance },
            set: { appearance in
                var updated = settingsStore.settings
                updated.appAppearance = appearance == .system ? nil : appearance
                updated.tabBarAppearance = nil
                settingsStore.settings = updated
                app.applySettingsSideEffects()
            }
        )
    }

    private var general: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Installation", symbol: "square.and.arrow.down") {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(installationTitle)
                            .font(.system(size: 13, weight: .semibold))
                        Text(installationDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if AppInstall.isRunningFromApplications {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    } else if installSucceeded {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.green)
                    } else {
                        Button(AppInstall.isInstalled ? "Update in Applications" : "Install to Applications") {
                            installToApplications()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if !AppInstall.isRunningFromApplications,
                   installSucceeded || AppInstall.isInstalled {
                    Divider()
                    HStack(spacing: 10) {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([AppInstall.installedAppURL])
                        }
                        Button("Quit and Reopen from Applications") {
                            AppInstall.launchInstalledAndTerminate()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if let installMessage {
                    Text(installMessage)
                        .font(.caption)
                        .foregroundStyle(installSucceeded ? Color.secondary : Color.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsCard(title: "Startup", symbol: "power") {
                SettingsToggleRow(
                    title: "Open at login",
                    detail: "Starts CursorStack quietly when you sign in.",
                    isOn: settings.launchAtLogin
                )
            }

            SettingsCard(title: "Where CursorStack appears", symbol: "macwindow") {
                SettingsToggleRow(
                    title: "Menu bar",
                    detail: "Quick access to groups, windows, and settings.",
                    isOn: settings.showMenuBarIcon
                )
                Divider()
                SettingsToggleRow(
                    title: "Dock and app switcher",
                    detail: "Shows CursorStack alongside your other apps.",
                    isOn: settings.showDockIcon
                )
            }

            SettingsCard(title: "New Cursor windows", symbol: "plus.rectangle.on.rectangle") {
                SettingsToggleRow(
                    title: "Add to the current stack automatically",
                    detail: "New Cursor windows join the stack you are currently using.",
                    isOn: settings.autoAddNewWindows
                )
            }
        }
    }

    private var tabs: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Appearance", symbol: "rectangle.topthird.inset.filled") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("CursorStack appearance")
                        .font(.system(size: 13, weight: .semibold))
                    Picker("CursorStack appearance", selection: appAppearance) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    Text("Applies to the stack bar, Settings, menus, pickers, and popups. System follows macOS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Tab bar height")
                        .font(.system(size: 13, weight: .semibold))
                    Picker("Tab bar height", selection: settings.tabHeight) {
                        Text("Compact").tag(CGFloat(35))
                        Text("Regular").tag(CGFloat(36))
                        Text("Roomy").tag(CGFloat(40))
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    Text("The bar sits above Cursor in its own row. Compact leaves the most room.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Tab names", symbol: "textformat") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Show each tab as")
                        .font(.system(size: 13, weight: .semibold))
                    Picker("Tab names", selection: tabLabelStyle) {
                        ForEach(TabLabelStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    Text(tabLabelStyle.wrappedValue.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SettingsCard(title: "Group and tab order", symbol: "list.bullet") {
                SettingsActionRow(
                    title: "Arrange tabs across your stacks",
                    detail: "Drag tabs into order, use precise move controls, or move a tab to another stack.",
                    buttonTitle: "Manage Groups…"
                ) {
                    app.showGroupOrganizer()
                }
            }
        }
    }

    private var shortcuts: some View {
        SettingsCard(title: "Switch tabs from anywhere", symbol: "keyboard") {
            ShortcutRecorder(
                title: "Next tab",
                shortcut: settingsStore.settings.nextTabHotKey.displayString,
                warning: ShortcutConflictDetector.warning(
                    for: settingsStore.settings.nextTabHotKey,
                    kind: .nextTab,
                    settings: settingsStore.settings
                ),
                isRecording: recordingShortcut == .nextTab,
                onBeginRecording: { beginRecording(.nextTab) },
                onEndRecording: endRecording,
                onCapture: { setShortcut($0, for: .nextTab) }
            )
            Divider()
            ShortcutRecorder(
                title: "Previous tab",
                shortcut: settingsStore.settings.previousTabHotKey.displayString,
                warning: ShortcutConflictDetector.warning(
                    for: settingsStore.settings.previousTabHotKey,
                    kind: .previousTab,
                    settings: settingsStore.settings
                ),
                isRecording: recordingShortcut == .previousTab,
                onBeginRecording: { beginRecording(.previousTab) },
                onEndRecording: endRecording,
                onCapture: { setShortcut($0, for: .previousTab) }
            )
            Divider()
            ShortcutRecorder(
                title: "Jump to tab 1–9",
                shortcut: numberedTabShortcutDisplay,
                warning: ShortcutConflictDetector.warning(
                    for: settingsStore.settings.effectiveNumberedTabHotKey,
                    kind: .numberedTabs,
                    settings: settingsStore.settings
                ),
                isRecording: recordingShortcut == .numberedTabs,
                onBeginRecording: { beginRecording(.numberedTabs) },
                onEndRecording: endRecording,
                onCapture: { setShortcut($0, for: .numberedTabs) }
            )

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Click a shortcut to record it. CursorStack checks its own shortcuts and common macOS shortcuts, but other apps do not expose all of theirs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Restore Defaults") {
                    restoreDefaultShortcuts()
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
        }
        .onDisappear(perform: endRecording)
    }

    private var numberedTabShortcutDisplay: String {
        settingsStore.settings.effectiveNumberedTabHotKey.modifierDisplayString + "1 … 9"
    }

    private func beginRecording(_ target: ShortcutTarget) {
        recordingShortcut = target
        app.setShortcutRecording(true)
    }

    private func endRecording() {
        recordingShortcut = nil
        app.setShortcutRecording(false)
    }

    private func setShortcut(_ shortcut: HotKeySpec, for target: ShortcutTarget) {
        var updated = settingsStore.settings
        switch target {
        case .nextTab:
            updated.nextTabHotKey = shortcut
        case .previousTab:
            updated.previousTabHotKey = shortcut
        case .numberedTabs:
            updated.numberedTabHotKey = HotKeySpec(
                keyCode: 18,
                control: shortcut.control,
                option: shortcut.option,
                shift: shortcut.shift,
                command: shortcut.command
            )
        }
        settingsStore.settings = updated
        app.applySettingsSideEffects()
    }

    private func restoreDefaultShortcuts() {
        var updated = settingsStore.settings
        updated.nextTabHotKey = .nextTab
        updated.previousTabHotKey = .previousTab
        updated.numberedTabHotKey = nil
        settingsStore.settings = updated
        app.applySettingsSideEffects()
        endRecording()
    }

    private var installationTitle: String {
        if AppInstall.isRunningFromApplications {
            return "CursorStack is running from Applications"
        }
        if installSucceeded {
            return "CursorStack is ready in Applications"
        }
        return AppInstall.isInstalled
            ? "An Applications copy is available"
            : "Move CursorStack out of its build folder"
    }

    private var installationDetail: String {
        if AppInstall.isRunningFromApplications {
            return "This is the installed copy. Updates can replace it later."
        }
        if installSucceeded {
            return "Quit this build and reopen the installed copy to finish switching over."
        }
        return "Install a standalone copy so CursorStack is available outside Xcode."
    }

    private func installToApplications() {
        do {
            let destination = try AppInstall.copyRunningAppToApplications()
            installSucceeded = true
            installMessage = "Copied to \(destination.path). Use Quit and Reopen to switch to it."
        } catch {
            installSucceeded = false
            installMessage = "Couldn’t install CursorStack: \(error.localizedDescription)"
        }
    }

    private var attention: some View {
        VStack(spacing: 16) {
            SettingsCard(title: "Detection", symbol: "sparkle.magnifyingglass") {
                SettingsToggleRow(
                    title: "Detect when Cursor needs you",
                    detail: "Looks for waiting, completed, and error states in each Cursor window.",
                    isOn: settings.detectAttention
                )
                Divider()
                SettingsToggleRow(
                    title: "Show a dot on the tab",
                    detail: "Marks the project that needs attention.",
                    isOn: settings.showTabIndicator
                )
                .disabled(!settingsStore.settings.detectAttention)
                .opacity(settingsStore.settings.detectAttention ? 1 : 0.45)
            }

            SettingsCard(title: "Notifications", symbol: "bell.badge") {
                SettingsToggleRow(
                    title: "Send a macOS notification",
                    detail: "Notifies you when a background Cursor project needs attention.",
                    isOn: settings.sendNotifications
                )
                Divider()
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Play a sound",
                        detail: "Uses the default macOS notification sound.",
                        isOn: settings.notificationSound
                    )
                    Divider()
                    SettingsToggleRow(
                        title: "Notify while CursorStack is active",
                        detail: "Useful when you are working in a different stack.",
                        isOn: settings.notifyWhenFrontmost
                    )
                    Divider()
                    SettingsToggleRow(
                        title: "Notify for the selected tab",
                        detail: "Also alerts for the project already in front.",
                        isOn: settings.notifyForSelectedTab
                    )
                }
                .disabled(!settingsStore.settings.sendNotifications)
                .opacity(settingsStore.settings.sendNotifications ? 1 : 0.45)
            }

            SettingsCard(title: "Experimental fallback", symbol: "viewfinder") {
                SettingsToggleRow(
                    title: "Use visual detection",
                    detail: "Checks a small local screenshot only when Accessibility cannot see Cursor’s status. Requires Screen Recording permission.",
                    isOn: settings.enableVisualDetection
                )
                .disabled(!settingsStore.settings.detectAttention)
                .opacity(settingsStore.settings.detectAttention ? 1 : 0.45)
            }
        }
    }

    private var advanced: some View {
        VStack(spacing: 16) {
            if !app.permissionGranted {
                SettingsCard(title: "Accessibility permission", symbol: "exclamationmark.triangle") {
                    SettingsActionRow(
                        title: "CursorStack cannot manage windows",
                        detail: "Reconnect Accessibility permission to restore grouping and switching.",
                        buttonTitle: "Open Privacy Settings",
                        action: app.requestAccessibility
                    )
                }
            }

            SettingsCard(title: "Diagnostics", symbol: "stethoscope") {
                SettingsActionRow(
                    title: "Re-scan Cursor windows",
                    detail: "Refreshes the list when an open project is missing.",
                    buttonTitle: "Re-scan"
                ) {
                    app.groupManager.refreshFromAccessibility()
                }
                Divider()
                SettingsActionRow(
                    title: "Window Lab",
                    detail: "Tests focus, movement, and sizing against live Cursor windows.",
                    buttonTitle: "Open"
                ) {
                    app.showWindowLab()
                }
                Divider()
                SettingsActionRow(
                    title: "Accessibility inspector",
                    detail: "Shows the window information Cursor exposes to macOS.",
                    buttonTitle: "Open"
                ) {
                    app.showInspector()
                }
                Divider()
                SettingsToggleRow(
                    title: "Debug logging",
                    detail: "Writes detailed window-management events to the macOS log.",
                    isOn: settings.debugLogging
                )
            }

            SettingsCard(title: "Saved data", symbol: "externaldrive") {
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reset saved groups")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Forgets every stack. Your Cursor windows and projects stay open.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Reset…", role: .destructive) {
                        app.resetSavedGroups()
                    }
                }
            }

        }
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case tabs
    case shortcuts
    case attention
    case advanced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .tabs: "Tabs"
        case .shortcuts: "Shortcuts"
        case .attention: "Attention"
        case .advanced: "Advanced"
        }
    }

    var detail: String {
        switch self {
        case .general: "Choose when CursorStack runs and where it appears."
        case .tabs: "Control how your Cursor projects look in the stack bar."
        case .shortcuts: "Move between projects without reaching for the mouse."
        case .attention: "Decide how CursorStack tells you a project is waiting."
        case .advanced: "Troubleshoot window detection and manage saved data."
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tabs: "rectangle.split.3x1"
        case .shortcuts: "keyboard"
        case .attention: "bell"
        case .advanced: "wrench.and.screwdriver"
        }
    }
}

private enum ShortcutTarget {
    case nextTab
    case previousTab
    case numberedTabs
}

private enum TabLabelStyle: String, CaseIterable, Identifiable {
    case projectName
    case fullTitle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .projectName: "Project name"
        case .fullTitle: "Full window title"
        }
    }

    var detail: String {
        switch self {
        case .projectName: "Short labels such as “cursor-stack” or “budmath”."
        case .fullTitle: "Includes Cursor’s active file name and project name."
        }
    }
}

private struct SettingsPageHeader: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder let content: Content

    init(title: String, symbol: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.symbol = symbol
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 12) {
                content
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
        )
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .fixedSize()
        }
    }
}

private struct SettingsActionRow: View {
    let title: String
    let detail: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(buttonTitle, action: action)
        }
    }
}
