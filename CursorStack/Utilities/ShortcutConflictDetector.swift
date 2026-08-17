import Foundation

enum ShortcutKind {
    case nextTab
    case previousTab
    case numberedTabs
}

enum ShortcutConflictDetector {
    static func warning(
        for candidate: HotKeySpec,
        kind: ShortcutKind,
        settings: AppSettings
    ) -> String? {
        if let internalConflict = internalConflict(
            for: candidate,
            kind: kind,
            settings: settings
        ) {
            return internalConflict
        }
        return commonSystemConflict(for: candidate, kind: kind)
    }

    private static func internalConflict(
        for candidate: HotKeySpec,
        kind: ShortcutKind,
        settings: AppSettings
    ) -> String? {
        switch kind {
        case .nextTab:
            if candidate == settings.previousTabHotKey {
                return "Also assigned to Previous tab."
            }
            if numberedSpecs(using: settings.effectiveNumberedTabHotKey).contains(candidate) {
                return "Also assigned to one of the Jump to tab shortcuts."
            }
        case .previousTab:
            if candidate == settings.nextTabHotKey {
                return "Also assigned to Next tab."
            }
            if numberedSpecs(using: settings.effectiveNumberedTabHotKey).contains(candidate) {
                return "Also assigned to one of the Jump to tab shortcuts."
            }
        case .numberedTabs:
            let numbered = numberedSpecs(using: candidate)
            if numbered.contains(settings.nextTabHotKey) {
                return "One of these is also assigned to Next tab."
            }
            if numbered.contains(settings.previousTabHotKey) {
                return "One of these is also assigned to Previous tab."
            }
        }
        return nil
    }

    private static func commonSystemConflict(
        for candidate: HotKeySpec,
        kind: ShortcutKind
    ) -> String? {
        let candidates = kind == .numberedTabs
            ? numberedSpecs(using: candidate)
            : [candidate]

        if candidates.contains(where: isApplicationSwitcher) {
            return "This conflicts with the macOS application switcher."
        }
        if candidates.contains(where: isSpotlight) {
            return "This commonly conflicts with Spotlight or input-source switching."
        }
        if candidates.contains(where: isMissionControl) {
            return "This commonly conflicts with Mission Control or Spaces."
        }
        if candidates.contains(where: isStandardApplicationShortcut) {
            return "This is a standard macOS application shortcut and may conflict."
        }
        return nil
    }

    private static func numberedSpecs(using modifiers: HotKeySpec) -> [HotKeySpec] {
        (1...9).map { HotKeySpec.numberedTab($0, modifiers: modifiers) }
    }

    private static func isApplicationSwitcher(_ spec: HotKeySpec) -> Bool {
        spec.keyCode == 48
            && spec.command
            && !spec.control
            && !spec.option
    }

    private static func isSpotlight(_ spec: HotKeySpec) -> Bool {
        spec.keyCode == 49
            && ((spec.command && !spec.control && !spec.option)
                || (spec.control && !spec.command && !spec.option))
    }

    private static func isMissionControl(_ spec: HotKeySpec) -> Bool {
        [123, 124, 125, 126].contains(spec.keyCode)
            && spec.control
            && !spec.command
            && !spec.option
    }

    private static func isStandardApplicationShortcut(_ spec: HotKeySpec) -> Bool {
        guard spec.command, !spec.control, !spec.option else { return false }
        let commonCommandKeys: Set<UInt16> = [
            0, 1, 6, 7, 8, 9, 12, 13, 15, 31, 35, 43, 45, 46,
        ]
        return commonCommandKeys.contains(spec.keyCode)
    }
}
