import AppKit
import ApplicationServices

enum AXHelpers {
    static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard error == .success else { return nil }
        return value
    }

    static func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    static func boolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
        (copyAttribute(element, attribute) as? NSNumber)?.boolValue
    }

    static func cgPointAttribute(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        var point = CGPoint.zero
        if AXValueGetValue(value as! AXValue, .cgPoint, &point) {
            return point
        }
        return nil
    }

    static func cgSizeAttribute(_ element: AXUIElement, _ attribute: String) -> CGSize? {
        guard let value = copyAttribute(element, attribute) else { return nil }
        var size = CGSize.zero
        if AXValueGetValue(value as! AXValue, .cgSize, &size) {
            return size
        }
        return nil
    }

    static func setPoint(_ element: AXUIElement, _ attribute: String, _ point: CGPoint) -> Bool {
        var mutable = point
        guard let value = AXValueCreate(.cgPoint, &mutable) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    static func setSize(_ element: AXUIElement, _ attribute: String, _ size: CGSize) -> Bool {
        var mutable = size
        guard let value = AXValueCreate(.cgSize, &mutable) else { return false }
        return AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    static func setBool(_ element: AXUIElement, _ attribute: String, _ flag: Bool) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, flag as CFBoolean) == .success
    }

    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = cgPointAttribute(element, kAXPositionAttribute as String),
              let size = cgSizeAttribute(element, kAXSizeAttribute as String) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    static func setFrame(_ frame: CGRect, of element: AXUIElement) -> Bool {
        let positionOK = setPoint(element, kAXPositionAttribute as String, frame.origin)
        let sizeOK = setSize(element, kAXSizeAttribute as String, frame.size)
        return positionOK && sizeOK
    }

    static func isAlive(_ element: AXUIElement) -> Bool {
        copyAttribute(element, kAXRoleAttribute as String) != nil
    }

    static func equal(_ a: AXUIElement, _ b: AXUIElement) -> Bool {
        CFEqual(a, b)
    }
}
