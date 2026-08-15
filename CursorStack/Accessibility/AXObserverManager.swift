import ApplicationServices
import Foundation

final class ObserverContext {
    let pid: pid_t
    weak var manager: AXObserverManager?

    init(pid: pid_t, manager: AXObserverManager) {
        self.pid = pid
        self.manager = manager
    }
}

final class AXObserverManager {
    var onEvent: ((pid_t, AXUIElement, String) -> Void)?

    private var observers: [pid_t: AXObserver] = [:]
    private var contexts: [pid_t: ObserverContext] = [:]

    func observe(pid: pid_t, appElement: AXUIElement) {
        stop(pid: pid)

        let context = ObserverContext(pid: pid, manager: self)
        contexts[pid] = context

        var observer: AXObserver?
        let result = AXObserverCreate(pid, { _, element, notification, refcon in
            guard let refcon else { return }
            let ctx = Unmanaged<ObserverContext>.fromOpaque(refcon).takeUnretainedValue()
            let name = notification as String
            let pid = ctx.pid
            DispatchQueue.main.async {
                ctx.manager?.onEvent?(pid, element, name)
            }
        }, &observer)

        guard result == .success, let observer else {
            CSLog.ax.error("Failed to create AX observer for pid \(pid)")
            return
        }

        observers[pid] = observer
        let refcon = Unmanaged.passUnretained(context).toOpaque()

        let notifications = [
            kAXWindowCreatedNotification,
            kAXUIElementDestroyedNotification,
            kAXFocusedWindowChangedNotification,
            kAXApplicationActivatedNotification,
            kAXMovedNotification,
            kAXResizedNotification,
            kAXTitleChangedNotification,
            kAXWindowMiniaturizedNotification,
            kAXWindowDeminiaturizedNotification,
            kAXMainWindowChangedNotification
        ]

        for notification in notifications {
            let addResult = AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
            if addResult != .success && addResult != .notificationUnsupported {
                CSLog.ax.debug("Could not subscribe to \(notification as String, privacy: .public) (\(addResult.rawValue))")
            }
        }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    func stop(pid: pid_t) {
        if let observer = observers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        contexts.removeValue(forKey: pid)
    }

    func stopAll() {
        for pid in Array(observers.keys) {
            stop(pid: pid)
        }
    }
}
