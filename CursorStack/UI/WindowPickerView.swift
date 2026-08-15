import SwiftUI

struct WindowPickerView: View {
    @ObservedObject var app: ApplicationController
    @State private var selected = Set<UUID>()
    @State private var groupName = "CursorStack Group"

    var windows: [ManagedCursorWindow] {
        app.groupManager.ungroupedWindows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(app.pickerTargetGroupID == nil ? "Create a group" : "Add windows")
                .font(.title3.weight(.semibold))

            if windows.isEmpty {
                Text("No ungrouped Cursor windows found.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Found \(windows.count) Cursor window\(windows.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
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
            }

            if app.pickerTargetGroupID == nil {
                TextField("Group name", text: $groupName)
                    .textFieldStyle(.roundedBorder)
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
        .padding(20)
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
