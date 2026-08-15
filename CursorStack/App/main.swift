import AppKit

/// Explicit AppKit bootstrap.
/// `@main` on `NSApplicationDelegate` only calls `NSApplicationMain`, which never
/// instantiates the delegate unless a Main storyboard/nib exists. This app has none,
/// so launching that way produced a running process with no windows and no menu bar.
enum CursorStackBootstrap {
    static var delegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        Self.delegate = delegate
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        NSLog("CursorStack: NSApplication starting")
        app.run()
    }
}

CursorStackBootstrap.main()
