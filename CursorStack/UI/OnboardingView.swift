import SwiftUI

struct OnboardingView: View {
    @ObservedObject var app: ApplicationController

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                BrandNameLogo(width: 250, style: .adaptive)
                Text("Your Cursor projects, one tab away")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Connect Accessibility")
                    .font(.system(size: 24, weight: .bold))
                Text("CursorStack uses macOS Accessibility to line up real Cursor windows and switch between them.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 12) {
                PermissionCard(
                    title: "What it can do",
                    symbol: "checkmark.shield",
                    items: ["Move and resize windows", "Bring a project to front", "Keep stack members aligned"]
                )
                PermissionCard(
                    title: "What it never does",
                    symbol: "hand.raised",
                    items: ["Read your source code", "Modify Cursor", "Upload window contents"]
                )
            }

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
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct PermissionCard: View {
    let title: String
    let symbol: String
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .bold))
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
