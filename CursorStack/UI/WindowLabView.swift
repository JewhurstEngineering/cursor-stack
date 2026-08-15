import AppKit
import SwiftUI

struct WindowLabView: View {
    @ObservedObject var app: ApplicationController

    var windows: [ManagedCursorWindow] {
        app.groupManager.allManagedWindows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Detected Cursor Windows")
                .font(.title3.weight(.semibold))
            if !app.permissionGranted {
                Text("Grant Accessibility permission first.")
                    .foregroundStyle(.red)
            }
            List(Array(windows.enumerated()), id: \.element.id) { index, window in
                HStack {
                    Text("\(index + 1). \(window.displayName)")
                    Spacer()
                    Text(NSStringFromRect(window.frame))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Stack All") {
                    let ids = windows.map(\.id)
                    if let existing = app.groupManager.groups.first {
                        app.groupManager.add(windows: windows.filter { window in
                            existing.windows.contains { $0.id == window.id } == false
                        }, to: existing.id)
                        app.groupManager.synchronizeFrame(windows.first?.frame ?? .zero, in: existing.id)
                    } else {
                        app.createGroup(name: "Lab", windowIDs: ids)
                    }
                }
                ForEach(Array(windows.prefix(3).enumerated()), id: \.element.id) { index, window in
                    Button("Focus \(index + 1)") {
                        if let group = app.groupManager.group(containing: window.id) {
                            app.activate(windowID: window.id, in: group.id)
                        } else {
                            FocusCoordinator.activate(
                                window: window,
                                discovery: app.discovery,
                                accessibility: app.accessibility
                            )
                        }
                    }
                }
                Spacer()
                Button("Re-scan") { app.groupManager.refreshFromAccessibility() }
            }
        }
        .padding(20)
    }
}
