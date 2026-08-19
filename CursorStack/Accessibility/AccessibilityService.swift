import ApplicationServices
import Foundation

protocol ExternalWindowControlling: AnyObject {
    func windows(for pid: pid_t) throws -> [AXWindowSnapshot]
    func frame(of snapshot: AXWindowSnapshot) throws -> CGRect
    func setFrame(_ frame: CGRect, of snapshot: AXWindowSnapshot) throws
    func raise(_ snapshot: AXWindowSnapshot) throws
    func focus(_ snapshot: AXWindowSnapshot) throws
    func minimize(_ snapshot: AXWindowSnapshot) throws
    func deminimize(_ snapshot: AXWindowSnapshot) throws
    func close(_ snapshot: AXWindowSnapshot) throws
}

struct AXWindowSnapshot {
    var pid: pid_t
    var element: AXUIElement
    var title: String
    var role: String
    var subrole: String?
    var frame: CGRect
    var isMinimized: Bool
    var isMain: Bool
    var isFocused: Bool

    var projectDisplayName: String {
        WindowTitleParser.projectDisplayName(from: title)
    }
}

enum AccessibilityServiceError: Error {
    case copyFailed
    case invalidWindow
    case setFrameFailed
    case raiseFailed
}

final class AccessibilityService: ExternalWindowControlling {
    func applicationElement(pid: pid_t) -> AXUIElement {
        AXUIElementCreateApplication(pid)
    }

    func windows(for pid: pid_t) throws -> [AXWindowSnapshot] {
        let app = applicationElement(pid: pid)
        let elements: [AXUIElement]
        switch AXHelpers.copyAttributeResult(app, kAXWindowsAttribute as String) {
        case .value(let raw):
            elements = (raw as? [AXUIElement]) ?? []
        case .noValue:
            elements = []
        case .failed(let error):
            CSLog.ax.error("AX window list unavailable for pid \(pid) (\(error.rawValue))")
            throw AccessibilityServiceError.copyFailed
        }

        return elements.compactMap { element in
            snapshot(pid: pid, element: element)
        }
        .filter { Self.isLikelyEditorWindow($0) }
    }

    func snapshot(pid: pid_t, element: AXUIElement) -> AXWindowSnapshot? {
        let role = AXHelpers.stringAttribute(element, kAXRoleAttribute as String) ?? ""
        let subrole = AXHelpers.stringAttribute(element, kAXSubroleAttribute as String)
        let title = AXHelpers.stringAttribute(element, kAXTitleAttribute as String) ?? ""
        guard let frame = AXHelpers.frame(of: element) else { return nil }
        let isMinimized = AXHelpers.boolAttribute(element, kAXMinimizedAttribute as String) ?? false
        let isMain = AXHelpers.boolAttribute(element, kAXMainAttribute as String) ?? false
        let isFocused = AXHelpers.boolAttribute(element, kAXFocusedAttribute as String) ?? false
        return AXWindowSnapshot(
            pid: pid,
            element: element,
            title: title,
            role: role,
            subrole: subrole,
            frame: ScreenCoordinateConverter.cocoaRect(fromAX: frame),
            isMinimized: isMinimized,
            isMain: isMain,
            isFocused: isFocused
        )
    }

    func frame(of snapshot: AXWindowSnapshot) throws -> CGRect {
        guard let frame = AXHelpers.frame(of: snapshot.element) else {
            throw AccessibilityServiceError.invalidWindow
        }
        return ScreenCoordinateConverter.cocoaRect(fromAX: frame)
    }

    func setFrame(_ frame: CGRect, of snapshot: AXWindowSnapshot) throws {
        let axFrame = ScreenCoordinateConverter.axRect(fromCocoa: frame)
        guard AXHelpers.setFrame(axFrame, of: snapshot.element) else {
            throw AccessibilityServiceError.setFrameFailed
        }
    }

    func raise(_ snapshot: AXWindowSnapshot) throws {
        _ = AXHelpers.perform(snapshot.element, kAXRaiseAction as String)
        _ = AXHelpers.setBool(snapshot.element, kAXMainAttribute as String, true)
        _ = AXHelpers.setBool(snapshot.element, kAXFocusedAttribute as String, true)
        let app = applicationElement(pid: snapshot.pid)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, snapshot.element)
    }

    func focus(_ snapshot: AXWindowSnapshot) throws {
        try raise(snapshot)
    }

    func minimize(_ snapshot: AXWindowSnapshot) throws {
        _ = AXHelpers.setBool(snapshot.element, kAXMinimizedAttribute as String, true)
    }

    func deminimize(_ snapshot: AXWindowSnapshot) throws {
        _ = AXHelpers.setBool(snapshot.element, kAXMinimizedAttribute as String, false)
    }

    func close(_ snapshot: AXWindowSnapshot) throws {
        if let closeButton = AXHelpers.copyAttribute(snapshot.element, kAXCloseButtonAttribute as String) {
            _ = AXHelpers.perform(closeButton as! AXUIElement, kAXPressAction as String)
            return
        }
        throw AccessibilityServiceError.invalidWindow
    }

    static func isLikelyEditorWindow(_ snapshot: AXWindowSnapshot) -> Bool {
        if snapshot.role != (kAXWindowRole as String) {
            return false
        }
        let dialogRoles: Set<String> = [
            kAXDialogSubrole as String,
            kAXSystemDialogSubrole as String,
            kAXFloatingWindowSubrole as String,
            kAXSystemFloatingWindowSubrole as String
        ]
        if let subrole = snapshot.subrole, dialogRoles.contains(subrole) {
            return false
        }
        if snapshot.frame.width < 280 || snapshot.frame.height < 200 {
            return false
        }
        return true
    }
}
