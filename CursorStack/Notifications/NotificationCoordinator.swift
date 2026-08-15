import Foundation
import UserNotifications

@MainActor
final class NotificationCoordinator: NSObject, @preconcurrency UNUserNotificationCenterDelegate {
    static let categoryID = "cursorstack.attention"
    static let groupIDKey = "groupID"
    static let windowIDKey = "windowID"

    var onActivate: ((UUID, UUID) -> Void)?
    private var authorized = false

    func start() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
        center.requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, error in
            if let error {
                CSLog.general.error("Notification auth failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in
                self?.authorized = granted
            }
        }
    }

    func notify(window: ManagedCursorWindow, groupID: UUID, sound: Bool) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "CursorStack"
        content.body = "\(window.displayName) needs attention"
        content.subtitle = "Cursor is waiting in the \(window.displayName) project."
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [
            Self.groupIDKey: groupID.uuidString,
            Self.windowIDKey: window.id.uuidString
        ]
        content.sound = sound ? .default : nil

        let request = UNNotificationRequest(
            identifier: "cursorstack.\(window.id.uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if let groupRaw = info[Self.groupIDKey] as? String,
           let windowRaw = info[Self.windowIDKey] as? String,
           let groupID = UUID(uuidString: groupRaw),
           let windowID = UUID(uuidString: windowRaw) {
            onActivate?(groupID, windowID)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list])
    }
}
