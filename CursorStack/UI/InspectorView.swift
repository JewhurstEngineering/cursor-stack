import AppKit
import SwiftUI

struct InspectorView: View {
    @ObservedObject var app: ApplicationController
    @State private var selectedID: UUID?
    @State private var dump = "Select a Cursor window."

    var windows: [ManagedCursorWindow] {
        app.groupManager.allManagedWindows
    }

    var body: some View {
        HSplitView {
            List(windows, id: \.id, selection: $selectedID) { window in
                VStack(alignment: .leading) {
                    Text(window.displayName)
                    Text(window.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .tag(window.id)
            }
            .frame(minWidth: 180)

            VStack(alignment: .leading) {
                HStack {
                    Button("Dump AX Tree") { refresh() }
                    Button("Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(dump, forType: .string)
                    }
                    if let selectedID, let window = windows.first(where: { $0.id == selectedID }) {
                        Text(window.attentionState.rawValue)
                            .font(.caption.monospaced())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.2), in: Capsule())
                    }
                    Spacer()
                }
                ScrollView {
                    Text(dump)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding()
        }
        .onChange(of: selectedID) { _, _ in refresh() }
    }

    private func refresh() {
        guard let selectedID, let window = windows.first(where: { $0.id == selectedID }) else { return }
        dump = app.dumpAXTree(for: window)
        let hints = AXTreeInspector.attentionHints(in: dump)
        if !hints.isEmpty {
            dump += "\n\n--- attention hints ---\n" + hints.joined(separator: "\n")
        }
    }
}
