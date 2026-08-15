import SwiftUI

struct SettingsView: View {
    @ObservedObject var app: ApplicationController
    @ObservedObject private var settingsStore: AppSettingsStore

    init(app: ApplicationController) {
        self.app = app
        self._settingsStore = ObservedObject(wrappedValue: app.settingsStore)
    }

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            tabs.tabItem { Label("Tabs", systemImage: "rectangle.split.3x1") }
            shortcuts.tabItem { Label("Shortcuts", systemImage: "keyboard") }
            attention.tabItem { Label("Attention", systemImage: "bell") }
            advanced.tabItem { Label("Advanced", systemImage: "wrench.and.screwdriver") }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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

    private var general: some View {
        Form {
            Toggle("Launch CursorStack at login", isOn: settings.launchAtLogin)
            Toggle("Show menu bar icon", isOn: settings.showMenuBarIcon)
            Toggle("Show Dock icon", isOn: settings.showDockIcon)
            Toggle("Automatically add new Cursor windows to the current group", isOn: settings.autoAddNewWindows)
        }
    }

    private var tabs: some View {
        Form {
            Picker("Tab height", selection: settings.tabHeight) {
                Text("Compact").tag(CGFloat(40))
                Text("Regular").tag(CGFloat(44))
                Text("Comfortable").tag(CGFloat(52))
            }
            Toggle("Project name", isOn: settings.showProjectName)
            Toggle("Full Cursor window title", isOn: settings.showFullTitle)
        }
    }

    private var shortcuts: some View {
        Form {
            labeled("Next tab", settings.wrappedValue.nextTabHotKey.displayString)
            labeled("Previous tab", settings.wrappedValue.previousTabHotKey.displayString)
            labeled("Tab 1–9", "⌃⌥ 1 … 9")
            Text("Shortcuts are global while Accessibility is granted.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var attention: some View {
        Form {
            Toggle("Detect Cursor attention state", isOn: settings.detectAttention)
            Toggle("Show tab indicator", isOn: settings.showTabIndicator)
            Toggle("Send macOS notification", isOn: settings.sendNotifications)
            Toggle("Play sound", isOn: settings.notificationSound)
            Toggle("Notify while CursorStack is frontmost", isOn: settings.notifyWhenFrontmost)
            Toggle("Notify for currently selected tab", isOn: settings.notifyForSelectedTab)
            Toggle("Enable experimental visual detection", isOn: settings.enableVisualDetection)
            Text("Experimental: Visual Cursor Alert Detection requires Screen Recording permission. Nothing is uploaded.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("Inspect Cursor Accessibility Tree") { app.showInspector() }
            Button("Re-scan Cursor Windows") { app.groupManager.refreshFromAccessibility() }
            Button("Window Lab") { app.showWindowLab() }
            Button("Reset Saved Groups", role: .destructive) { app.resetSavedGroups() }
            Toggle("Debug logging", isOn: settings.debugLogging)
            if !app.permissionGranted {
                Text("CursorStack no longer has Accessibility permission.")
                    .foregroundStyle(.red)
                Button("Open Privacy Settings") { app.requestAccessibility() }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospaced()
        }
    }
}
