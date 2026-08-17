import SwiftUI

struct GroupOrganizerView: View {
    @ObservedObject var app: ApplicationController
    @State private var selectedGroupID: UUID?
    @State private var draggedWindowID: UUID?
    @State private var targetedWindowID: UUID?

    init(app: ApplicationController, selectedGroupID: UUID?) {
        self.app = app
        self._selectedGroupID = State(
            initialValue: selectedGroupID ?? app.groupManager.preferredGroup()?.id
        )
    }

    private var selectedGroup: RuntimeWindowGroup? {
        app.groupManager.groups.first { $0.id == selectedGroupID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                BrandNameLogo(width: 190, style: .adaptive)
                Text("Arrange projects in each stack")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Tab order")
                        .font(.system(size: 20, weight: .bold))
                    Text("Drag rows or use the arrow buttons. Changes save automatically.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Picker("Stack", selection: $selectedGroupID) {
                    ForEach(app.groupManager.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .frame(width: 190)
            }

            if let group = selectedGroup {
                GroupOrderList(
                    group: group,
                    app: app,
                    draggedWindowID: $draggedWindowID,
                    targetedWindowID: $targetedWindowID
                )
            } else {
                ContentUnavailableView(
                    "No Stack Selected",
                    systemImage: "rectangle.stack",
                    description: Text("Create a stack before arranging its tabs.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 420)
    }
}

private struct GroupOrderList: View {
    @ObservedObject var group: RuntimeWindowGroup
    @ObservedObject var app: ApplicationController
    @Binding var draggedWindowID: UUID?
    @Binding var targetedWindowID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(group.windows.enumerated()), id: \.element.id) { index, window in
                    HStack(spacing: 12) {
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.tertiary)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(window.displayName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                                if window.id == group.activeWindowID {
                                    Text("ACTIVE")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            Text(window.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if app.groupManager.groups.count > 1 {
                            Menu {
                                ForEach(app.groupManager.groups.filter { $0.id != group.id }) { destination in
                                    Button(destination.name) {
                                        app.groupManager.moveWindow(
                                            window.id,
                                            from: group.id,
                                            to: destination.id,
                                            at: destination.windows.count
                                        )
                                    }
                                }
                            } label: {
                                Image(systemName: "rectangle.stack.badge.plus")
                            }
                            .menuStyle(.borderlessButton)
                            .help("Move to another stack")
                        }

                        Button {
                            app.groupManager.reorder(
                                in: group.id,
                                moving: window.id,
                                to: max(0, index - 1)
                            )
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .help("Move left")

                        Button {
                            app.groupManager.reorder(
                                in: group.id,
                                moving: window.id,
                                to: index + 1
                            )
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == group.windows.count - 1)
                        .help("Move right")
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 56)
                    .contentShape(Rectangle())
                    .background(
                        targetedWindowID == window.id
                            ? Color.accentColor.opacity(0.09)
                            : Color.clear
                    )
                    .onDrag {
                        draggedWindowID = window.id
                        return NSItemProvider(object: window.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: WindowOrderDropDelegate(
                            targetWindowID: window.id,
                            groupID: group.id,
                            app: app,
                            draggedWindowID: $draggedWindowID,
                            targetedWindowID: $targetedWindowID
                        )
                    )

                    if index < group.windows.count - 1 {
                        Divider()
                            .padding(.leading, 40)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
