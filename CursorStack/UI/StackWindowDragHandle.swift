import AppKit
import SwiftUI

struct StackWindowDragHandle: View {
    var body: some View {
        ZStack {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
            WindowDragCaptureView()
        }
        .contentShape(Rectangle())
        .help("Drag to move the whole stack")
    }
}

private struct WindowDragCaptureView: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragNSView {
        WindowDragNSView()
    }

    func updateNSView(_ nsView: WindowDragNSView, context: Context) {}
}

private final class WindowDragNSView: NSView {
    override func mouseDown(with event: NSEvent) {
        NSApp.activate()
        window?.performDrag(with: event)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
