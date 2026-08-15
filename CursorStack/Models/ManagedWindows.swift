import ApplicationServices
import Foundation

@MainActor
final class ManagedCursorWindow: ObservableObject, Identifiable {
    let id: UUID
    var pid: pid_t
    var element: AXUIElement

    @Published var title: String
    @Published var projectDisplayName: String
    @Published var alias: String?
    @Published var frame: CGRect
    @Published var isMinimized: Bool
    @Published var isClosed: Bool
    @Published var isUnavailable: Bool
    @Published var attentionState: AttentionState
    @Published var isMain: Bool
    @Published var isFocused: Bool

    var displayName: String {
        if let alias, !alias.isEmpty { return alias }
        return projectDisplayName
    }

    init(id: UUID = UUID(), snapshot: AXWindowSnapshot, alias: String? = nil) {
        self.id = id
        self.pid = snapshot.pid
        self.element = snapshot.element
        self.title = snapshot.title
        self.projectDisplayName = snapshot.projectDisplayName
        self.alias = alias
        self.frame = snapshot.frame
        self.isMinimized = snapshot.isMinimized
        self.isClosed = false
        self.isUnavailable = false
        self.attentionState = .unknown
        self.isMain = snapshot.isMain
        self.isFocused = snapshot.isFocused
    }

    var snapshot: AXWindowSnapshot {
        AXWindowSnapshot(
            pid: pid,
            element: element,
            title: title,
            role: kAXWindowRole as String,
            subrole: nil,
            frame: frame,
            isMinimized: isMinimized,
            isMain: isMain,
            isFocused: isFocused
        )
    }

    func apply(_ snapshot: AXWindowSnapshot) {
        pid = snapshot.pid
        element = snapshot.element
        title = snapshot.title
        projectDisplayName = snapshot.projectDisplayName
        frame = snapshot.frame
        isMinimized = snapshot.isMinimized
        isMain = snapshot.isMain
        isFocused = snapshot.isFocused
        isClosed = false
        isUnavailable = false
    }

    func persistedReference() -> PersistedWindowReference {
        PersistedWindowReference(
            id: id,
            lastTitle: title,
            projectDisplayName: projectDisplayName,
            alias: alias,
            lastSeen: Date()
        )
    }
}

@MainActor
final class RuntimeWindowGroup: ObservableObject, Identifiable {
    let id: UUID
    @Published var name: String
    @Published var windows: [ManagedCursorWindow]
    @Published var activeWindowID: UUID?
    @Published var synchronizedFrame: CGRect
    @Published var isPaused: Bool
    @Published var isFullScreenPaused: Bool
    var isApplyingSynchronizedFrame = false
    var synchronizationGeneration: UInt64 = 0
    var frameBeforeMaximize: CGRect?

    var activeWindow: ManagedCursorWindow? {
        windows.first(where: { $0.id == activeWindowID }) ?? windows.first
    }

    var liveWindows: [ManagedCursorWindow] {
        windows.filter { !$0.isClosed && !$0.isUnavailable }
    }

    var isMinimized: Bool {
        activeWindow?.isMinimized == true
    }

    init(
        id: UUID = UUID(),
        name: String,
        windows: [ManagedCursorWindow],
        activeWindowID: UUID?,
        synchronizedFrame: CGRect,
        isPaused: Bool
    ) {
        self.id = id
        self.name = name
        self.windows = windows
        self.activeWindowID = activeWindowID ?? windows.first?.id
        self.synchronizedFrame = synchronizedFrame
        self.isPaused = isPaused
        self.isFullScreenPaused = false
    }

    var persisted: CursorWindowGroup {
        CursorWindowGroup(
            id: id,
            name: name,
            members: windows.map { $0.persistedReference() },
            activeMemberID: activeWindowID,
            frame: CodableRect(synchronizedFrame),
            settings: GroupSettings(isPaused: isPaused)
        )
    }
}
