import XCTest
@testable import CursorStack

final class WindowTitleParserTests: XCTestCase {
    func testStripsCursorSuffixAndUsesProjectComponent() {
        XCTAssertEqual(
            WindowTitleParser.projectDisplayName(from: "package.json — jamesware-ai-meter — Cursor"),
            "jamesware-ai-meter"
        )
    }

    func testUntitledWhenEmpty() {
        XCTAssertEqual(WindowTitleParser.projectDisplayName(from: "   "), "Untitled")
    }

    func testDirtyIndicator() {
        XCTAssertEqual(
            WindowTitleParser.projectDisplayName(from: "● App.swift — cursor-stack — Cursor"),
            "cursor-stack"
        )
    }
}

final class WindowMatcherTests: XCTestCase {
    func testMatchesByProjectName() {
        let persisted = [
            PersistedWindowReference(
                id: UUID(),
                lastTitle: "old",
                projectDisplayName: "ai-meter",
                alias: nil,
                lastSeen: Date()
            )
        ]
        let live = [(title: "main.ts — ai-meter — Cursor", projectDisplayName: "ai-meter")]
        let result = WindowMatcher.match(persisted: persisted, live: live)
        XCTAssertEqual(result[persisted[0].id], 0)
    }

    func testDoesNotDoubleAssign() {
        let a = UUID()
        let b = UUID()
        let persisted = [
            PersistedWindowReference(id: a, lastTitle: "x", projectDisplayName: "same", alias: nil, lastSeen: Date()),
            PersistedWindowReference(id: b, lastTitle: "y", projectDisplayName: "same", alias: nil, lastSeen: Date())
        ]
        let live = [
            (title: "same", projectDisplayName: "same"),
            (title: "other", projectDisplayName: "other")
        ]
        let result = WindowMatcher.match(persisted: persisted, live: live)
        XCTAssertEqual(Set(result.values).count, result.count)
    }
}

final class ScreenCoordinateConverterTests: XCTestCase {
    func testConvertsAXTopLeftCoordinatesToCocoaBottomLeftCoordinates() {
        let axFrame = CGRect(x: 0, y: 33, width: 1512, height: 949)
        let cocoaFrame = ScreenCoordinateConverter.cocoaRect(
            fromAX: axFrame,
            primaryScreenMaxY: 982
        )

        XCTAssertEqual(cocoaFrame, CGRect(x: 0, y: 0, width: 1512, height: 949))
        XCTAssertEqual(
            ScreenCoordinateConverter.axRect(
                fromCocoa: cocoaFrame,
                primaryScreenMaxY: 982
            ),
            axFrame
        )
    }

    func testRecoversFrameFromDisconnectedDisplay() {
        let stale = CGRect(x: -1756, y: -144, width: 1720, height: 1410)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)

        XCTAssertEqual(
            ScreenCoordinateConverter.visibleFraction(of: stale, in: [visible]),
            0
        )
        let recovered = ScreenCoordinateConverter.recoveredFrame(
            stale,
            visibleFrames: [visible]
        )
        XCTAssertTrue(visible.contains(recovered))
        XCTAssertEqual(recovered.size, visible.size)
    }

    func testTabPanelSitsAboveCursorTitlebar() {
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = ScreenCoordinateConverter.tabPanelFrame(windowFrame: window, height: 36, visibleFrame: visible)
        XCTAssertEqual(panel.minX, 100)
        XCTAssertEqual(panel.width, 800)
        XCTAssertEqual(panel.minY, 800)
        XCTAssertEqual(panel.maxY, 836)
        XCTAssertEqual(panel.height, 36)
    }

    func testMaximizeLeavesRoomForTabBar() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.maximizedContentFrame(visibleFrame: visible, tabHeight: 36)
        XCTAssertEqual(content.height, 908)
        XCTAssertEqual(content.width, 1512)
        XCTAssertEqual(content.maxY, 908)
    }

    func testFullHeightWindowShrinksToLeaveTabRoom() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.contentFrameLeavingTabRoom(
            visible,
            tabHeight: 36,
            visibleFrame: visible
        )
        XCTAssertEqual(content, CGRect(x: 0, y: 0, width: 1512, height: 908))
    }

    func testFloatingWindowMovesDownToLeaveTabRoomWithoutShrinking() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let original = CGRect(x: 100, y: 400, width: 800, height: 500)
        let content = ScreenCoordinateConverter.contentFrameLeavingTabRoom(
            original,
            tabHeight: 36,
            visibleFrame: visible
        )
        XCTAssertEqual(content, CGRect(x: 100, y: 364, width: 800, height: 500))
    }

    func testWindowFollowsPanelBelowItsBottomEdge() {
        let panel = CGRect(x: 100, y: 800, width: 800, height: 36)
        let window = ScreenCoordinateConverter.windowFrame(matchingTabPanel: panel, windowHeight: 600)
        XCTAssertEqual(window.minX, 100)
        XCTAssertEqual(window.maxY, 800)
        XCTAssertEqual(window.height, 600)
    }

    func testApproximateEquality() {
        let a = CGRect(x: 10, y: 10, width: 100, height: 100)
        let b = CGRect(x: 11, y: 9.5, width: 100.5, height: 101)
        XCTAssertTrue(ScreenCoordinateConverter.framesApproximatelyEqual(a, b, tolerance: 2))
    }
}

final class ShortcutSettingsTests: XCTestCase {
    func testCustomNumberedModifiersApplyToEveryNumber() {
        let modifiers = HotKeySpec(
            keyCode: 18,
            control: false,
            option: true,
            shift: true,
            command: false
        )

        XCTAssertEqual(
            HotKeySpec.numberedTab(9, modifiers: modifiers),
            HotKeySpec(
                keyCode: 25,
                control: false,
                option: true,
                shift: true,
                command: false
            )
        )
    }

    func testWarnsWhenNextAndPreviousShortcutsMatch() {
        var settings = AppSettings()
        settings.previousTabHotKey = settings.nextTabHotKey

        XCTAssertEqual(
            ShortcutConflictDetector.warning(
                for: settings.nextTabHotKey,
                kind: .nextTab,
                settings: settings
            ),
            "Also assigned to Previous tab."
        )
    }

    func testWarnsWhenShortcutOverlapsNumberedTabs() {
        var settings = AppSettings()
        settings.nextTabHotKey = .numberedTab(3)

        XCTAssertEqual(
            ShortcutConflictDetector.warning(
                for: settings.nextTabHotKey,
                kind: .nextTab,
                settings: settings
            ),
            "Also assigned to one of the Jump to tab shortcuts."
        )
    }

    func testWarnsAboutCommonMacOSShortcut() {
        let commandQ = HotKeySpec(
            keyCode: 12,
            control: false,
            option: false,
            shift: false,
            command: true
        )

        XCTAssertNotNil(
            ShortcutConflictDetector.warning(
                for: commandQ,
                kind: .nextTab,
                settings: AppSettings()
            )
        )
    }

    func testOlderSettingsDecodeWithoutNumberedShortcut() throws {
        let data = try JSONEncoder().encode(AppSettings())
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.effectiveNumberedTabHotKey, .numberedTabModifiers)
        XCTAssertEqual(decoded.effectiveAppAppearance, .system)
    }

    func testAppAppearanceRoundTrips() throws {
        var settings = AppSettings()
        settings.appAppearance = .dark

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.effectiveAppAppearance, .dark)
    }

    func testLegacyTabBarAppearanceMigratesToAppAppearance() {
        var settings = AppSettings()
        settings.tabBarAppearance = .dark

        XCTAssertEqual(settings.effectiveAppAppearance, .dark)
    }
}

final class GroupLogicTests: XCTestCase {
    func testNextActiveSelectsNeighbor() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        XCTAssertEqual(GroupLogic.nextActiveID(afterClosing: b, orderedIDs: [a, b, c], current: b), c)
        XCTAssertEqual(GroupLogic.nextActiveID(afterClosing: c, orderedIDs: [a, b, c], current: c), b)
        XCTAssertNil(GroupLogic.nextActiveID(afterClosing: a, orderedIDs: [a], current: a))
    }

    func testReorder() {
        let a = UUID()
        let b = UUID()
        let c = UUID()
        XCTAssertEqual(GroupLogic.reorder(ids: [a, b, c], moving: c, to: 0), [c, a, b])
        XCTAssertEqual(GroupLogic.reorder(ids: [a, b, c], moving: a, to: 1), [b, a, c])
        XCTAssertEqual(GroupLogic.reorder(ids: [a, b, c], moving: b, to: 2), [a, c, b])
        XCTAssertEqual(GroupLogic.reorder(ids: [a, b, c], moving: a, to: 99), [b, c, a])
    }
}

final class AttentionDedupTests: XCTestCase {
    func testSendsOnceUntilReset() {
        var tracking = AttentionTrackingState()
        XCTAssertTrue(AttentionDeduplicator.shouldNotify(tracking: &tracking, newState: .attention, notifySelected: false, isSelected: false))
        XCTAssertFalse(AttentionDeduplicator.shouldNotify(tracking: &tracking, newState: .attention, notifySelected: false, isSelected: false))
        XCTAssertFalse(AttentionDeduplicator.shouldNotify(tracking: &tracking, newState: .idle, notifySelected: false, isSelected: false))
        XCTAssertTrue(AttentionDeduplicator.shouldNotify(tracking: &tracking, newState: .attention, notifySelected: false, isSelected: false))
    }

    func testSkipsSelectedUnlessEnabled() {
        var tracking = AttentionTrackingState()
        XCTAssertFalse(AttentionDeduplicator.shouldNotify(tracking: &tracking, newState: .attention, notifySelected: false, isSelected: true))
        XCTAssertTrue(AttentionDeduplicator.shouldNotify(tracking: &tracking, newState: .attention, notifySelected: true, isSelected: true))
    }
}

final class AccessibilityAttentionInterpretTests: XCTestCase {
    func testUnreadHint() {
        let observation = AccessibilityAttentionProvider.interpret(
            hints: ["AXButton desc=Chat, 1 unread"],
            title: "AI Meter — Cursor"
        )
        XCTAssertEqual(observation.state, .attention)
    }

    func testMetadataDot() {
        let observation = WindowMetadataAttentionProvider.interpret(title: "● backend — Cursor")
        XCTAssertEqual(observation.state, .attention)
    }
}
