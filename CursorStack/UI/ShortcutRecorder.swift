import AppKit
import SwiftUI

struct ShortcutRecorder: View {
    let title: String
    let shortcut: String
    let warning: String?
    let isRecording: Bool
    let onBeginRecording: () -> Void
    let onEndRecording: () -> Void
    let onCapture: (HotKeySpec) -> Void

    @State private var validationMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    if isRecording {
                        onEndRecording()
                    } else {
                        validationMessage = nil
                        onBeginRecording()
                    }
                } label: {
                    Text(isRecording ? "Type shortcut…" : shortcut)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .frame(minWidth: isRecording ? 112 : 54)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(
                    isRecording ? Color.accentColor.opacity(0.12) : Color(nsColor: .windowBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isRecording ? 1.5 : 1
                        )
                )
                .help(isRecording ? "Press Escape to cancel" : "Click to record a new shortcut")
            }

            if let message = validationMessage ?? warning {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background {
            if isRecording {
                ShortcutKeyCaptureView(
                    onCapture: { spec in
                        guard spec.hasCommandStyleModifier else {
                            validationMessage = "Use Control, Option, or Command with the key."
                            return
                        }
                        validationMessage = nil
                        onCapture(spec)
                        onEndRecording()
                    },
                    onCancel: onEndRecording
                )
                .frame(width: 1, height: 1)
            }
        }
        .onChange(of: isRecording) { _, recording in
            if !recording {
                validationMessage = nil
            }
        }
    }
}

private struct ShortcutKeyCaptureView: NSViewRepresentable {
    let onCapture: (HotKeySpec) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onCapture = onCapture
        nsView.onCancel = onCancel
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView, let window = nsView.window else { return }
            window.makeFirstResponder(nsView)
        }
    }
}

private final class KeyCaptureNSView: NSView {
    var onCapture: ((HotKeySpec) -> Void)?
    var onCancel: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            window.makeFirstResponder(self)
        }
    }

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        onCapture?(
            HotKeySpec(
                keyCode: event.keyCode,
                control: flags.contains(.control),
                option: flags.contains(.option),
                shift: flags.contains(.shift),
                command: flags.contains(.command)
            )
        )
    }
}
