import AppKit
import SwiftUI

struct TabStripView: View {
    @ObservedObject var group: RuntimeWindowGroup
    @ObservedObject var app: ApplicationController

    private var position: TabBarPosition {
        app.settingsStore.settings.effectiveTabBarPosition
    }

    var body: some View {
        Group {
            if position.isVertical {
                verticalStrip
            } else {
                horizontalStrip
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TitlebarBackground())
        .overlay(alignment: separatorAlignment) {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(
                    width: position.isVertical ? 1 : nil,
                    height: position.isVertical ? nil : 1
                )
        }
        .onTapGesture(count: 2) {
            app.groupManager.toggleMaximize(group.id)
        }
        .contextMenu {
            stripContextMenu
        }
    }

    private var separatorAlignment: Alignment {
        switch position {
        case .top: .bottom
        case .bottom: .top
        case .left: .trailing
        case .right: .leading
        }
    }

    private var horizontalStrip: some View {
        HStack(spacing: 10) {
            TrafficLights(
                onClose: { NSApp.terminate(nil) },
                onMiniaturize: { app.groupManager.minimizeGroup(group.id) },
                onZoom: { app.groupManager.toggleMaximize(group.id) }
            )
            .padding(.leading, 8)

            StackBarBrandMark()
                .frame(width: 98)
                .help("CursorStack")

            StackWindowDragHandle()
                .frame(width: 14, height: 24)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 1, height: 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    tabItems(fillsWidth: false)
                }
            }

            addMenu
            settingsButton
                .padding(.trailing, 8)
        }
    }

    private var verticalStrip: some View {
        VStack(spacing: 10) {
            TrafficLights(
                onClose: { NSApp.terminate(nil) },
                onMiniaturize: { app.groupManager.minimizeGroup(group.id) },
                onZoom: { app.groupManager.toggleMaximize(group.id) }
            )
            .padding(.top, 10)

            BrandMark(size: 28, style: .adaptive)
                .help("CursorStack")

            StackWindowDragHandle()
                .frame(width: 24, height: 14)

            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 18, height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 2) {
                    tabItems(fillsWidth: true)
                }
                .padding(.horizontal, 8)
            }

            addMenu
            settingsButton
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func tabItems(fillsWidth: Bool) -> some View {
        ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, window in
            TabItemView(
                window: window,
                selected: window.id == group.activeWindowID,
                showIndicator: app.settingsStore.settings.showTabIndicator,
                showFullTitle: app.settingsStore.settings.showFullTitle,
                showProjectName: app.settingsStore.settings.showProjectName,
                sparkStyle: app.settingsStore.settings.effectiveClaudeSparkStyle,
                fillsWidth: fillsWidth
            )
            .onTapGesture {
                app.activate(windowID: window.id, in: group.id)
            }
            .contextMenu {
                Button("Switch To") { app.activate(windowID: window.id, in: group.id) }
                Button(fillsWidth ? "Move Up" : "Move Left") {
                    app.groupManager.reorder(in: group.id, moving: window.id, to: max(0, index - 1))
                }
                Button(fillsWidth ? "Move Down" : "Move Right") {
                    app.groupManager.reorder(in: group.id, moving: window.id, to: index + 1)
                }
                Button("Manage Tab Order…") { app.showGroupOrganizer(groupID: group.id) }
                Divider()
                Button("Rename Tab…") { app.promptRenameTab(window) }
                Divider()
                Button("Detach From Group") { app.groupManager.detach(windowID: window.id, from: group.id) }
                Button("Close Cursor Window") { app.groupManager.closeCursorWindow(window.id) }
            }
            .onDrag {
                app.draggedTabWindowID = window.id
                return NSItemProvider(object: window.id.uuidString as NSString)
            }
            .onDrop(
                of: [.text],
                delegate: WindowOrderDropDelegate(
                    targetWindowID: window.id,
                    groupID: group.id,
                    app: app,
                    draggedWindowID: $app.draggedTabWindowID,
                    targetedWindowID: $app.targetedTabWindowID
                )
            )
            .overlay(alignment: fillsWidth ? .top : .leading) {
                if app.targetedTabWindowID == window.id {
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: fillsWidth ? nil : 3, height: fillsWidth ? 3 : nil)
                        .padding(fillsWidth ? .horizontal : .vertical, 3)
                        .offset(x: fillsWidth ? 0 : -2, y: fillsWidth ? -2 : 0)
                }
            }
        }
        ForEach(group.unresolved) { unresolved in
            UnresolvedTabItemView(
                unresolved: unresolved,
                canRemoveAll: group.unresolved.count > 1,
                fillsWidth: fillsWidth,
                onReconnect: { app.reconnectUnresolved(unresolved, in: group.id) },
                onRemove: { app.forgetUnresolved(unresolved, in: group.id) },
                onRemoveAll: { app.forgetAllUnresolved(in: group.id) }
            )
        }
    }

    private var addMenu: some View {
        Menu {
            Button("Add Existing Cursor Window…") {
                app.showWindowPicker(addingTo: group.id)
            }
            Button("Open New Cursor Window…") {
                app.openNewCursorWindow()
            }
            if !group.unresolved.isEmpty {
                Button("Remove Closed Tabs", role: .destructive) {
                    app.forgetAllUnresolved(in: group.id)
                }
            }
            Divider()
            Button("Maximize Group") { app.groupManager.maximize(group.id) }
            Button(group.isPaused ? "Resume Synchronization" : "Pause Synchronization") {
                app.groupManager.pause(group.id, paused: !group.isPaused)
            }
            Button("Rename Group…") { app.promptRenameGroup(group) }
            Button("Manage Tab Order…") { app.showGroupOrganizer(groupID: group.id) }
            Divider()
            Button("Show All Windows") { app.groupManager.showAllWindows(group.id) }
            Button("Ungroup All", role: .destructive) { app.groupManager.ungroupAll(group.id) }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                Text("Add")
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(nsColor: .labelColor))
            .frame(maxWidth: position.isVertical ? .infinity : nil)
            .frame(height: 24)
            .padding(.horizontal, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            )
            .fixedSize(horizontal: !position.isVertical, vertical: true)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: !position.isVertical, vertical: true)
        .help("Add Cursor windows or manage this stack")
    }

    private var settingsButton: some View {
        Button {
            app.showSettings()
        } label: {
            Label("Settings", systemImage: "gearshape")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
                .frame(maxWidth: position.isVertical ? .infinity : nil)
                .frame(height: 24)
                .padding(.horizontal, 7)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.75))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if app.updateAvailable {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                            .overlay(
                                Circle()
                                    .strokeBorder(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5)
                            )
                            .offset(x: 2, y: -2)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(app.updateAvailable ? "Update available — open Settings" : "Open CursorStack Settings")
        .accessibilityLabel(app.updateAvailable ? "Settings, update available" : "Settings")
    }

    @ViewBuilder
    private var stripContextMenu: some View {
        Text(group.name).font(.headline)
        Button("Add Cursor Window…") { app.showWindowPicker(addingTo: group.id) }
        Button("Rename Group…") { app.promptRenameGroup(group) }
        Button("Manage Tab Order…") { app.showGroupOrganizer(groupID: group.id) }
        Button("Maximize Group") { app.groupManager.maximize(group.id) }
        Button(group.isPaused ? "Resume Synchronization" : "Pause Synchronization") {
            app.groupManager.pause(group.id, paused: !group.isPaused)
        }
        if !group.unresolved.isEmpty {
            Divider()
            Button("Remove Closed Tabs", role: .destructive) {
                app.forgetAllUnresolved(in: group.id)
            }
        }
        Divider()
        Button("Show All Windows") { app.groupManager.showAllWindows(group.id) }
        Button("Ungroup All", role: .destructive) { app.groupManager.ungroupAll(group.id) }
    }
}

private struct UnresolvedTabItemView: View {
    let unresolved: PersistedWindowReference
    let canRemoveAll: Bool
    var fillsWidth: Bool = false
    let onReconnect: () -> Void
    let onRemove: () -> Void
    let onRemoveAll: () -> Void

    private var label: String {
        unresolved.alias ?? unresolved.projectDisplayName
    }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onReconnect) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: .labelColor).opacity(0.45))
                    .lineLimit(1)
                    .padding(.leading, 11)
                    .padding(.vertical, 5)
                    .padding(.trailing, 2)
            }
            .buttonStyle(.plain)
            .help("Reconnect \(unresolved.projectDisplayName)")

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color(nsColor: .labelColor).opacity(0.5))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove closed tab")
            .padding(.trailing, 6)
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color(nsColor: .labelColor).opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
        .contextMenu {
            Button("Reconnect…", action: onReconnect)
            Button("Remove Closed Tab", action: onRemove)
            if canRemoveAll {
                Button("Remove All Closed Tabs", role: .destructive, action: onRemoveAll)
            }
        }
    }
}

private struct ChatSignalMark: View {
    enum Kind {
        case running
        case waiting
        case error
    }

    var kind: Kind
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let amber = Color(red: 245.0 / 255, green: 158.0 / 255, blue: 11.0 / 255)

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? nil : 1.0 / 30.0, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            switch kind {
            case .running:
                let angle = reduceMotion ? -90.0 : time.truncatingRemainder(dividingBy: 1) * 360
                Circle()
                    .trim(from: 0.12, to: 1)
                    .stroke(Self.amber, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 8, height: 8)
                    .rotationEffect(.degrees(angle))
                    .help("Chat running")
            case .waiting, .error:
                let color = kind == .error ? Color.red : Self.amber
                let pulse = reduceMotion ? 0.0 : 0.5 + 0.5 * sin(time * .pi * 2 / 1.6)
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(color, lineWidth: 1.5)
                            .scaleEffect(1 + pulse * 0.9)
                            .opacity(1 - pulse)
                    }
                    .help(kind == .error ? "Needs attention" : "Waiting on you")
            }
        }
    }
}

private struct ClaudeSparkMark: View {
    var style: ClaudeSparkStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let clay = Color(red: 217.0 / 255, green: 119.0 / 255, blue: 87.0 / 255)

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? nil : 1.0 / 30.0, paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let angle = reduceMotion ? 0.0 : time.truncatingRemainder(dividingBy: 8) / 8 * 360
            let wave = reduceMotion ? 1.0 : 0.5 + 0.5 * sin(time * .pi * 2 / 1.6)
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    Capsule()
                        .fill(Self.clay)
                        .frame(width: 2, height: 9)
                        .rotationEffect(.degrees(Double(index) * 60))
                        .opacity(style.spokeOpacity(index: index, wave: wave))
                }
            }
            .frame(width: 11, height: 11)
            .rotationEffect(.degrees(angle))
            .help("Claude Code running")
        }
    }
}

struct TabItemView: View {
    @ObservedObject var window: ManagedCursorWindow
    var selected: Bool
    var showIndicator: Bool
    var showFullTitle: Bool
    var showProjectName: Bool
    var sparkStyle: ClaudeSparkStyle
    var fillsWidth: Bool = false

    private var helpText: String {
        let cursor: String
        switch window.attentionState {
        case .working:
            cursor = "\(window.title) — Cursor chat running"
        case .attention:
            cursor = "\(window.title) — waiting on you"
        case .completed:
            cursor = "\(window.title) — Cursor chat is done"
        case .error:
            cursor = "\(window.title) — needs attention"
        case .unknown, .idle:
            cursor = window.title
        }
        guard window.claudeBusy else { return cursor }
        if cursor == window.title {
            return "\(window.title) — Claude Code running"
        }
        return "\(cursor). Claude Code running"
    }

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
            if fillsWidth {
                Spacer(minLength: 0)
            }
            if showIndicator, window.attentionState.showsTabDot {
                ChatSignalMark(kind: window.attentionState == .error ? .error : .waiting)
            } else if showIndicator, window.attentionState.showsWorkingIndicator {
                ChatSignalMark(kind: .running)
            }
            if showIndicator, window.claudeBusy {
                ClaudeSparkMark(style: sparkStyle)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 4)
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(selected ? Color(nsColor: .controlAccentColor).opacity(0.38) : Color.clear)
        )
        .help(helpText)
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
