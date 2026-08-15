import SwiftUI

struct TabStripView: View {
    let groupID: UUID
    @ObservedObject var app: ApplicationController

    var group: RuntimeWindowGroup? {
        app.groupManager.groups.first { $0.id == groupID }
    }

    var body: some View {
        if let group {
            HStack(spacing: 0) {
                ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, window in
                    TabItemView(
                        window: window,
                        selected: window.id == group.activeWindowID,
                        showDot: app.settingsStore.settings.showTabIndicator && window.attentionState.showsTabDot,
                        showWorking: app.settingsStore.settings.showTabIndicator && window.attentionState.showsWorkingIndicator,
                        showFullTitle: app.settingsStore.settings.showFullTitle
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

                Spacer(minLength: 8)

                Menu {
                    Button("Add Existing Cursor Window…") {
                        app.showWindowPicker(addingTo: group.id)
                    }
                    Button("Open New Cursor Window…") {
                        app.openNewCursorWindow()
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    )
            )
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
        } else {
            EmptyView()
        }
    }
}

struct TabItemView: View {
    @ObservedObject var window: ManagedCursorWindow
    var selected: Bool
    var showDot: Bool
    var showWorking: Bool
    var showFullTitle: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(showFullTitle ? window.title : window.displayName)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
            if showDot {
                Circle()
                    .fill(window.attentionState == .error ? Color.red : Color.accentColor)
                    .frame(width: 6, height: 6)
            } else if showWorking {
                Circle()
                    .strokeBorder(Color.secondary, lineWidth: 1)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.22) : Color.clear)
        )
        .foregroundStyle(selected ? Color.primary : Color.secondary)
        .help(window.title)
        .opacity(window.isUnavailable ? 0.45 : 1)
    }
}
