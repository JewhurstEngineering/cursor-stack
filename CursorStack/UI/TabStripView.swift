import AppKit
import SwiftUI

struct TabStripView: View {
    @ObservedObject var group: RuntimeWindowGroup
    @ObservedObject var app: ApplicationController

    var body: some View {
        HStack(spacing: 10) {
                TrafficLights(
                    onClose: { NSApp.terminate(nil) },
                    onMiniaturize: { app.groupManager.minimizeGroup(group.id) },
                    onZoom: { app.groupManager.toggleMaximize(group.id) }
                )
                .padding(.leading, 8)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, window in
                            TabItemView(
                                window: window,
                                selected: window.id == group.activeWindowID,
                                showDot: app.settingsStore.settings.showTabIndicator && window.attentionState.showsTabDot,
                                showWorking: app.settingsStore.settings.showTabIndicator && window.attentionState.showsWorkingIndicator,
                                showFullTitle: app.settingsStore.settings.showFullTitle,
                                showProjectName: app.settingsStore.settings.showProjectName
                            )
                            .onTapGesture {
                                app.activate(windowID: window.id, in: group.id)
                            }
                            .contextMenu {
                                Button("Switch To") { app.activate(windowID: window.id, in: group.id) }
                                Button("Move Left") { app.groupManager.reorder(in: group.id, moving: window.id, to: max(0, index - 1)) }
                                Button("Move Right") { app.groupManager.reorder(in: group.id, moving: window.id, to: index + 1) }
                                Divider()
                                Button("Rename Tab…") { app.promptRenameTab(window) }
                                Divider()
                                Button("Detach From Group") { app.groupManager.detach(windowID: window.id, from: group.id) }
                                Button("Close Cursor Window") { app.groupManager.closeCursorWindow(window.id) }
                            }
                            .onDrop(of: [.text], isTargeted: nil) { providers in
                                app.handleTabDrop(providers: providers, onto: window.id, in: group.id)
                            }
                            .onDrag {
                                NSItemProvider(object: window.id.uuidString as NSString)
                            }
                        }
                        ForEach(group.unresolved) { unresolved in
                            Button {
                                app.reconnectUnresolved(unresolved, in: group.id)
                            } label: {
                                Text(unresolved.alias ?? unresolved.projectDisplayName)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Color(nsColor: .labelColor).opacity(0.45))
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .strokeBorder(Color(nsColor: .labelColor).opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
                                    )
                            }
                            .buttonStyle(.plain)
                            .help("Reconnect \(unresolved.projectDisplayName)")
                        }
                    }
                }

                Menu {
                    Button("Add Existing Cursor Window…") {
                        app.showWindowPicker(addingTo: group.id)
                    }
                    Button("Open New Cursor Window…") {
                        app.openNewCursorWindow()
                    }
                    Divider()
                    Button("Maximize Group") { app.groupManager.maximize(group.id) }
                    Button(group.isPaused ? "Resume Synchronization" : "Pause Synchronization") {
                        app.groupManager.pause(group.id, paused: !group.isPaused)
                    }
                    Button("Rename Group…") { app.promptRenameGroup(group) }
                    Divider()
                    Button("Show All Windows") { app.groupManager.showAllWindows(group.id) }
                    Button("Ungroup All", role: .destructive) { app.groupManager.ungroupAll(group.id) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .labelColor))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
                .padding(.trailing, 8)
                .help("Add window or group actions")
            }
            .onDrop(of: [.text], isTargeted: nil) { providers in
                app.handleTabDrop(providers: providers, onto: group.windows.last?.id, in: group.id)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(TitlebarBackground())
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color(nsColor: .separatorColor))
                    .frame(height: 1)
            }
            .onTapGesture(count: 2) {
                app.groupManager.toggleMaximize(group.id)
            }
            .contextMenu {
                Text(group.name).font(.headline)
                Button("Add Cursor Window…") { app.showWindowPicker(addingTo: group.id) }
                Button("Rename Group…") { app.promptRenameGroup(group) }
                Button("Maximize Group") { app.groupManager.maximize(group.id) }
                Button(group.isPaused ? "Resume Synchronization" : "Pause Synchronization") {
                    app.groupManager.pause(group.id, paused: !group.isPaused)
                }
                Divider()
                Button("Show All Windows") { app.groupManager.showAllWindows(group.id) }
                Button("Ungroup All", role: .destructive) { app.groupManager.ungroupAll(group.id) }
            }
    }
}

struct TabItemView: View {
    @ObservedObject var window: ManagedCursorWindow
    var selected: Bool
    var showDot: Bool
    var showWorking: Bool
    var showFullTitle: Bool
    var showProjectName: Bool

    private var label: String {
        if showFullTitle { return window.title }
        if let alias = window.alias, !alias.isEmpty { return alias }
        if showProjectName { return window.projectDisplayName }
        return window.displayName
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))
                .foregroundStyle(Color(nsColor: .labelColor).opacity(selected ? 1 : 0.78))
                .lineLimit(1)
            if showDot {
                Circle()
                    .fill(window.attentionState == .error ? Color.red : Color.accentColor)
                    .frame(width: 7, height: 7)
            } else if showWorking {
                Circle()
                    .strokeBorder(Color(nsColor: .labelColor).opacity(0.7), lineWidth: 1.2)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color(nsColor: .controlAccentColor).opacity(0.38) : Color.clear)
        )
        .help(window.title)
        .opacity(window.isUnavailable ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.12), value: selected)
    }
}

struct TrafficLights: View {
    var onClose: () -> Void
    var onMiniaturize: () -> Void
    var onZoom: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            TrafficLightButton(color: Color(red: 1, green: 0.38, blue: 0.37), symbol: "xmark", hovering: hovering, action: onClose)
                .help("Quit CursorStack")
            TrafficLightButton(color: Color(red: 1, green: 0.74, blue: 0.18), symbol: "minus", hovering: hovering, action: onMiniaturize)
                .help("Minimize")
            TrafficLightButton(color: Color(red: 0.19, green: 0.82, blue: 0.35), symbol: "arrow.up.left.and.arrow.down.right", hovering: hovering, action: onZoom)
                .help("Fill screen")
        }
        .onHover { hovering = $0 }
    }
}

struct TrafficLightButton: View {
    var color: Color
    var symbol: String
    var hovering: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
                    )
                if hovering {
                    Image(systemName: symbol)
                        .font(.system(size: 6, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.62))
                }
            }
            .frame(width: 14, height: 14)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

struct TitlebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .titlebar
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
        nsView.isEmphasized = true
    }
}
