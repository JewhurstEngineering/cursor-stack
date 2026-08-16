import SwiftUI

struct OnboardingView: View {
    @ObservedObject var app: ApplicationController

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            BrandHero(maxWidth: 320)
            Text("Welcome to CursorStack")
                .font(.title2.weight(.semibold))
            Text("CursorStack needs Accessibility permission to organize and switch your Cursor windows.")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Label("can move Cursor windows", systemImage: "checkmark")
                Label("can resize Cursor windows", systemImage: "checkmark")
                Label("can focus Cursor windows", systemImage: "checkmark")
            }
            .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 6) {
                Label("does not read your source code", systemImage: "xmark")
                Label("does not modify Cursor", systemImage: "xmark")
                Label("does not upload window contents", systemImage: "xmark")
            }
            .foregroundStyle(.secondary)

            if app.permissionGranted {
                Label("Accessibility is granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Text("CursorStack needs Accessibility permission")
                    .font(.headline)
            }

            Spacer()

            Button("Open Accessibility Settings") {
                app.requestAccessibility()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
