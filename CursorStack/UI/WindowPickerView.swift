import SwiftUI

struct WindowPickerView: View {
    @ObservedObject var app: ApplicationController
    @State private var selected = Set<UUID>()
    @State private var groupName = "CursorStack Group"

    var windows: [ManagedCursorWindow] {
        app.groupManager.ungroupedWindows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 5) {
                BrandNameLogo(width: 210, style: .adaptive)
                Text("Turn Cursor windows into one tabbed stack")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(app.pickerTargetGroupID == nil ? "Create a stack" : "Add windows")
                    .font(.system(size: 20, weight: .bold))
                Text(
                    app.pickerTargetGroupID == nil
                        ? "Choose the Cursor projects you want to switch between as tabs."
                        : "Choose more Cursor projects for this stack."
                )
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }

            if windows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow.badge.plus")
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("No available Cursor windows")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Open another project in a new Cursor window, then come back and re-scan.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                    Button("Re-scan") {
                        app.groupManager.refreshFromAccessibility()
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
            } else {
                List(windows, id: \.id) { window in
                    Toggle(isOn: binding(for: window.id)) {
                        VStack(alignment: .leading) {
                            Text(window.displayName)
                            Text(window.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if app.pickerTargetGroupID == nil {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stack name")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("For example: Client work", text: $groupName)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    NSApp.keyWindow?.close()
                }
                Button(app.pickerTargetGroupID == nil ? "Create Group" : "Add") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selected.isEmpty)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            selected = Set(windows.map(\.id))
            if let first = windows.first {
                groupName = first.displayName
            }
        }
    }

    private func binding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { selected.contains(id) },
            set: { on in
                if on { selected.insert(id) } else { selected.remove(id) }
            }
        )
    }

    private func submit() {
        let ids = Array(selected)
        if let groupID = app.pickerTargetGroupID {
            app.addSelectedWindows(ids, to: groupID)
        } else {
            app.createGroup(name: groupName.isEmpty ? "CursorStack Group" : groupName, windowIDs: ids)
        }
    }
}
