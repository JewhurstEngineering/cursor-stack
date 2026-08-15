import Foundation
import CoreGraphics

enum AttentionState: String, Codable, Equatable, CaseIterable {
    case unknown
    case idle
    case working
    case attention
    case completed
    case error

    var showsTabDot: Bool {
        self == .attention || self == .error
    }

    var showsWorkingIndicator: Bool {
        self == .working
    }
}

enum AttentionSource: String, Codable {
    case accessibility
    case metadata
    case visual
    case user
}

struct AttentionObservation: Equatable {
    var state: AttentionState
    var confidence: Double
    var source: AttentionSource
}

struct AttentionTrackingState: Equatable {
    var currentState: AttentionState = .unknown
    var lastNotifiedState: AttentionState?
    var lastNotificationDate: Date?

    mutating func shouldNotify(
        newState: AttentionState,
        notifySelected: Bool,
        isSelected: Bool,
        cooldown: TimeInterval = 30
    ) -> Bool {
        let previous = currentState
        currentState = newState

        guard newState == .attention || newState == .error else {
            if newState == .idle || newState == .unknown {
                lastNotifiedState = nil
            }
            return false
        }

        if isSelected && !notifySelected {
            return false
        }

        if lastNotifiedState == newState {
            if let last = lastNotificationDate, Date().timeIntervalSince(last) < cooldown {
                return false
            }
            if previous == newState {
                return false
            }
        }

        lastNotifiedState = newState
        lastNotificationDate = Date()
        return true
    }
}

struct CodableRect: Codable, Equatable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

struct GroupSettings: Codable, Equatable {
    var isPaused: Bool = false
}

struct PersistedWindowReference: Codable, Identifiable, Equatable {
    var id: UUID
    var lastTitle: String
    var projectDisplayName: String
    var alias: String?
    var lastSeen: Date
}

struct CursorWindowGroup: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var members: [PersistedWindowReference]
    var activeMemberID: UUID?
    var frame: CodableRect
    var settings: GroupSettings
}

struct HotKeySpec: Codable, Equatable {
    var keyCode: UInt16
    var control: Bool
    var option: Bool
    var shift: Bool
    var command: Bool

    static let nextTab = HotKeySpec(keyCode: 30, control: true, option: true, shift: false, command: false)
    static let previousTab = HotKeySpec(keyCode: 33, control: true, option: true, shift: false, command: false)

    static func numberedTab(_ n: Int) -> HotKeySpec {
        let codes: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let code = codes[max(0, min(n - 1, codes.count - 1))]
        return HotKeySpec(keyCode: code, control: true, option: true, shift: false, command: false)
    }

    var displayString: String {
        var parts: [String] = []
        if control { parts.append("⌃") }
        if option { parts.append("⌥") }
        if shift { parts.append("⇧") }
        if command { parts.append("⌘") }
        parts.append(Self.label(for: keyCode))
        return parts.joined()
    }

    private static func label(for keyCode: UInt16) -> String {
        switch keyCode {
        case 30: return "]"
        case 33: return "["
        case 18: return "1"
        case 19: return "2"
        case 20: return "3"
        case 21: return "4"
        case 23: return "5"
        case 22: return "6"
        case 26: return "7"
        case 28: return "8"
        case 25: return "9"
        default: return "#\(keyCode)"
        }
    }
}

struct AppSettings: Codable, Equatable {
    var launchAtLogin: Bool = false
    var showMenuBarIcon: Bool = true
    var showDockIcon: Bool = true

    var tabHeight: CGFloat = 36
    var showProjectName: Bool = true
    var showFullTitle: Bool = false

    var detectAttention: Bool = true
    var showTabIndicator: Bool = true
    var sendNotifications: Bool = true
    var notificationSound: Bool = false
    var notifyWhenFrontmost: Bool = false
    var notifyForSelectedTab: Bool = false
    var enableVisualDetection: Bool = false
    var autoAddNewWindows: Bool = false

    var debugLogging: Bool = false

    var nextTabHotKey: HotKeySpec = .nextTab
    var previousTabHotKey: HotKeySpec = .previousTab
}

enum GroupLogic {
    static func nextActiveID(afterClosing closedID: UUID, orderedIDs: [UUID], current: UUID?) -> UUID? {
        guard !orderedIDs.isEmpty else { return nil }
        let remaining = orderedIDs.filter { $0 != closedID }
        guard !remaining.isEmpty else { return nil }
        if current != closedID, let current, remaining.contains(current) {
            return current
        }
        if let index = orderedIDs.firstIndex(of: closedID) {
            if index < remaining.count {
                return remaining[index]
            }
            return remaining.last
        }
        return remaining.first
    }

    static func reorder(ids: [UUID], moving movedID: UUID, to destinationIndex: Int) -> [UUID] {
        guard let from = ids.firstIndex(of: movedID) else { return ids }
        var result = ids
        result.remove(at: from)
        let clamped = max(0, min(destinationIndex, result.count))
        result.insert(movedID, at: clamped)
        return result
    }
}

enum AttentionDeduplicator {
    static func shouldNotify(
        tracking: inout AttentionTrackingState,
        newState: AttentionState,
        notifySelected: Bool,
        isSelected: Bool
    ) -> Bool {
        tracking.shouldNotify(newState: newState, notifySelected: notifySelected, isSelected: isSelected)
    }
}
