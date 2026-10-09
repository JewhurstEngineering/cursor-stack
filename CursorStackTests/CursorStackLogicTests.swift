import XCTest
import ApplicationServices
@testable import CursorStack

final class WindowTitleParserTests: XCTestCase {
    func testStripsCursorSuffixAndUsesProjectComponent() {
        XCTAssertEqual(
            WindowTitleParser.projectDisplayName(from: "package.json — ai-meter — Cursor"),
            "ai-meter"
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

    func testDisplayNameIgnoresModifiedSuffix() {
        XCTAssertEqual(
            WindowTitleParser.projectDisplayName(from: "declined-work-and-recommendations.md — shift-sms-ts — Modified"),
            "shift-sms-ts"
        )
        XCTAssertEqual(
            WindowTitleParser.projectDisplayName(from: "● App.swift — cursor-stack — Modified"),
            "cursor-stack"
        )
    }

    func testProjectTokenIgnoresModifiedSuffix() {
        XCTAssertEqual(
            WindowTitleParser.projectToken(from: "declined-work-and-recommendations.md — shift-sms-ts — Modified"),
            "shift-sms-ts"
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
        let panel = ScreenCoordinateConverter.tabPanelFrame(
            windowFrame: window,
            position: .top,
            thickness: 36,
            visibleFrame: visible
        )
        XCTAssertEqual(panel.minX, 100)
        XCTAssertEqual(panel.width, 800)
        XCTAssertEqual(panel.minY, 800)
        XCTAssertEqual(panel.maxY, 836)
        XCTAssertEqual(panel.height, 36)
    }

    func testTabPanelSitsBelowCursor() {
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = ScreenCoordinateConverter.tabPanelFrame(
            windowFrame: window,
            position: .bottom,
            thickness: 36,
            visibleFrame: visible
        )
        XCTAssertEqual(panel.minX, 100)
        XCTAssertEqual(panel.width, 800)
        XCTAssertEqual(panel.minY, 164)
        XCTAssertEqual(panel.maxY, 200)
        XCTAssertEqual(panel.height, 36)
    }

    func testTabPanelSitsLeftOfCursor() {
        let window = CGRect(x: 200, y: 200, width: 800, height: 600)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = ScreenCoordinateConverter.tabPanelFrame(
            windowFrame: window,
            position: .left,
            thickness: 148,
            visibleFrame: visible
        )
        XCTAssertEqual(panel.minX, 52)
        XCTAssertEqual(panel.width, 148)
        XCTAssertEqual(panel.minY, 200)
        XCTAssertEqual(panel.height, 600)
    }

    func testTabPanelSitsRightOfCursor() {
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = ScreenCoordinateConverter.tabPanelFrame(
            windowFrame: window,
            position: .right,
            thickness: 148,
            visibleFrame: visible
        )
        XCTAssertEqual(panel.minX, 900)
        XCTAssertEqual(panel.width, 148)
        XCTAssertEqual(panel.minY, 200)
        XCTAssertEqual(panel.height, 600)
    }

    func testMaximizeLeavesRoomForTabBar() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.maximizedContentFrame(
            visibleFrame: visible,
            position: .top,
            thickness: 36
        )
        XCTAssertEqual(content.height, 908)
        XCTAssertEqual(content.width, 1512)
        XCTAssertEqual(content.maxY, 908)
    }

    func testMaximizeLeavesRoomForBottomTabBar() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.maximizedContentFrame(
            visibleFrame: visible,
            position: .bottom,
            thickness: 36
        )
        XCTAssertEqual(content.minY, 36)
        XCTAssertEqual(content.height, 908)
        XCTAssertEqual(content.width, 1512)
    }

    func testMaximizeLeavesRoomForLeftTabBar() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.maximizedContentFrame(
            visibleFrame: visible,
            position: .left,
            thickness: 148
        )
        XCTAssertEqual(content.minX, 148)
        XCTAssertEqual(content.width, 1364)
        XCTAssertEqual(content.height, 944)
    }

    func testMaximizeLeavesRoomForRightTabBar() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.maximizedContentFrame(
            visibleFrame: visible,
            position: .right,
            thickness: 148
        )
        XCTAssertEqual(content.minX, 0)
        XCTAssertEqual(content.width, 1364)
        XCTAssertEqual(content.height, 944)
    }

    func testFullHeightWindowShrinksToLeaveTabRoom() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.contentFrameLeavingTabRoom(
            visible,
            position: .top,
            thickness: 36,
            visibleFrame: visible
        )
        XCTAssertEqual(content, CGRect(x: 0, y: 0, width: 1512, height: 908))
    }

    func testFullWidthWindowShrinksToLeaveLeftTabRoom() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.contentFrameLeavingTabRoom(
            visible,
            position: .left,
            thickness: 148,
            visibleFrame: visible
        )
        XCTAssertEqual(content, CGRect(x: 148, y: 0, width: 1364, height: 944))
    }

    func testFullHeightWindowShrinksToLeaveBottomTabRoom() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.contentFrameLeavingTabRoom(
            visible,
            position: .bottom,
            thickness: 36,
            visibleFrame: visible
        )
        XCTAssertEqual(content, CGRect(x: 0, y: 36, width: 1512, height: 908))
    }

    func testFullWidthWindowShrinksToLeaveRightTabRoom() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.contentFrameLeavingTabRoom(
            visible,
            position: .right,
            thickness: 148,
            visibleFrame: visible
        )
        XCTAssertEqual(content, CGRect(x: 0, y: 0, width: 1364, height: 944))
    }

    func testFloatingWindowMovesDownToLeaveTabRoomWithoutShrinking() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let original = CGRect(x: 100, y: 400, width: 800, height: 500)
        let content = ScreenCoordinateConverter.contentFrameLeavingTabRoom(
            original,
            position: .top,
            thickness: 36,
            visibleFrame: visible
        )
        XCTAssertEqual(content, CGRect(x: 100, y: 364, width: 800, height: 500))
    }

    func testFloatingWindowMovesRightToLeaveLeftTabRoomWithoutShrinking() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let original = CGRect(x: 0, y: 200, width: 800, height: 500)
        let content = ScreenCoordinateConverter.contentFrameLeavingTabRoom(
            original,
            position: .left,
            thickness: 148,
            visibleFrame: visible
        )
        XCTAssertEqual(content, CGRect(x: 148, y: 200, width: 800, height: 500))
    }

    func testWindowFollowsPanelBelowItsBottomEdge() {
        let panel = CGRect(x: 100, y: 800, width: 800, height: 36)
        let window = ScreenCoordinateConverter.windowFrame(
            matchingTabPanel: panel,
            windowSize: CGSize(width: 800, height: 600),
            position: .top
        )
        XCTAssertEqual(window.minX, 100)
        XCTAssertEqual(window.maxY, 800)
        XCTAssertEqual(window.height, 600)
    }

    func testWindowFollowsPanelAboveItsTopEdge() {
        let panel = CGRect(x: 100, y: 164, width: 800, height: 36)
        let window = ScreenCoordinateConverter.windowFrame(
            matchingTabPanel: panel,
            windowSize: CGSize(width: 800, height: 600),
            position: .bottom
        )
        XCTAssertEqual(window.minX, 100)
        XCTAssertEqual(window.minY, 200)
        XCTAssertEqual(window.height, 600)
    }

    func testWindowFollowsPanelToTheRight() {
        let panel = CGRect(x: 52, y: 200, width: 148, height: 600)
        let window = ScreenCoordinateConverter.windowFrame(
            matchingTabPanel: panel,
            windowSize: CGSize(width: 800, height: 600),
            position: .left
        )
        XCTAssertEqual(window.minX, 200)
        XCTAssertEqual(window.minY, 200)
        XCTAssertEqual(window.width, 800)
        XCTAssertEqual(window.height, 600)
    }

    func testWindowFollowsPanelToTheLeft() {
        let panel = CGRect(x: 900, y: 200, width: 148, height: 600)
        let window = ScreenCoordinateConverter.windowFrame(
            matchingTabPanel: panel,
            windowSize: CGSize(width: 800, height: 600),
            position: .right
        )
        XCTAssertEqual(window.maxX, 900)
        XCTAssertEqual(window.minY, 200)
        XCTAssertEqual(window.width, 800)
        XCTAssertEqual(window.height, 600)
    }

    func testApproximateEquality() {
        let a = CGRect(x: 10, y: 10, width: 100, height: 100)
        let b = CGRect(x: 11, y: 9.5, width: 100.5, height: 101)
        XCTAssertTrue(ScreenCoordinateConverter.framesApproximatelyEqual(a, b, tolerance: 2))
    }
}

final class TabBarSettingsTests: XCTestCase {
    func testMissingPositionAndWidthDecodeToDefaults() throws {
        var object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AppSettings())
        ) as! [String: Any]
        object.removeValue(forKey: "tabBarPosition")
        object.removeValue(forKey: "tabWidth")
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.effectiveTabBarPosition, .top)
        XCTAssertEqual(decoded.effectiveTabWidth, 148)
        XCTAssertEqual(decoded.tabBarThickness, 36)
        XCTAssertEqual(decoded.effectiveTabBarPosition.isVertical, false)
    }

    func testMissingSparkStyleDecodesToBoth() throws {
        var object = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(AppSettings())
        ) as! [String: Any]
        object.removeValue(forKey: "claudeSparkStyle")
        let decoded = try JSONDecoder().decode(
            AppSettings.self,
            from: try JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.effectiveClaudeSparkStyle, .both)
    }

    func testBreatheFadesTheWholeSparkTogether() {
        let dim = ClaudeSparkStyle.breathe.spokeOpacity(index: 0, wave: 0)
        let bright = ClaudeSparkStyle.breathe.spokeOpacity(index: 0, wave: 1)
        XCTAssertEqual(dim, ClaudeSparkStyle.breathe.spokeOpacity(index: 3, wave: 0), accuracy: 0.001)
        XCTAssertLessThan(dim, bright)
    }

    func testSpokeKeepsOneArmBrighter() {
        let lead = ClaudeSparkStyle.spoke.spokeOpacity(index: 0, wave: 0.2)
        let opposite = ClaudeSparkStyle.spoke.spokeOpacity(index: 3, wave: 0.2)
        XCTAssertGreaterThan(lead, opposite)
        XCTAssertGreaterThan(ClaudeSparkStyle.spoke.spokeOpacity(index: 0, wave: 1), lead)
        XCTAssertEqual(
            opposite,
            ClaudeSparkStyle.spoke.spokeOpacity(index: 3, wave: 1),
            accuracy: 0.001
        )
    }

    func testBothFadesAndKeepsTheLeadArm() {
        XCTAssertGreaterThan(
            ClaudeSparkStyle.both.spokeOpacity(index: 0, wave: 0.4),
            ClaudeSparkStyle.both.spokeOpacity(index: 3, wave: 0.4)
        )
        XCTAssertLessThan(
            ClaudeSparkStyle.both.spokeOpacity(index: 0, wave: 0),
            ClaudeSparkStyle.both.spokeOpacity(index: 0, wave: 1)
        )
    }

    func testVerticalThicknessUsesTabWidth() {
        var settings = AppSettings()
        settings.tabBarPosition = .left
        settings.tabWidth = 148
        XCTAssertEqual(settings.tabBarThickness, 148)
        settings.tabBarPosition = .top
        XCTAssertEqual(settings.tabBarThickness, 36)
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
    func testStopGenerationIsWorking() {
        let observation = AccessibilityAttentionProvider.interpret(
            labels: ["Stop generation"],
            regionReadable: true
        )
        XCTAssertEqual(observation.state, .working)
    }

    func testWaitingForApprovalNeedsYou() {
        let observation = AccessibilityAttentionProvider.interpret(
            labels: ["Waiting for approval"],
            regionReadable: true
        )
        XCTAssertEqual(observation.state, .attention)
    }

    func testReadableComposerWithNoControlsIsIdle() {
        let observation = AccessibilityAttentionProvider.interpret(
            labels: ["Send"],
            regionReadable: true
        )
        XCTAssertEqual(observation.state, .idle)
    }

    func testEditorLineIsNotASignal() {
        let observation = AccessibilityAttentionProvider.interpret(
            labels: ["waiting-for-approval.ts", "error: something failed"],
            regionReadable: true
        )
        XCTAssertEqual(observation.state, .idle)
    }

    func testUnreadableComposerStaysUnknown() {
        let observation = AccessibilityAttentionProvider.interpret(
            labels: [],
            regionReadable: false
        )
        XCTAssertEqual(observation.state, .unknown)
    }

    func testWorkingStatusIsRunning() {
        let observation = AccessibilityAttentionProvider.interpret(
            labels: ["2 Working"],
            regionReadable: true
        )
        XCTAssertEqual(observation.state, .working)
    }

    func testPullRequestReviewersAreNotASignal() {
        let observation = AccessibilityAttentionProvider.interpret(
            labels: ["Waiting for Reviewers"],
            regionReadable: true
        )
        XCTAssertEqual(observation.state, .idle)
    }

    func testDirtyFileBulletIsNotAttention() {
        let observation = WindowMetadataAttentionProvider.interpret(title: "● backend — Cursor")
        XCTAssertEqual(observation.state, .unknown)
    }
}

final class ComposerActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let workspaces = [
        ComposerWorkspace(id: "stack", folderName: "cursor-stack"),
        ComposerWorkspace(id: "shift-a", folderName: "shift-sms-ts"),
        ComposerWorkspace(id: "shift-b", folderName: "shift-sms-ts")
    ]

    func testFreshCheckpointWhileARunIsOpenIsWorking() {
        let headers = [
            header(workspace: "stack", unfinished: true, checkpoint: now.addingTimeInterval(-12))
        ]
        XCTAssertEqual(activity(headers), .working)
    }

    func testFreshCheckpointAfterTheRunEndsIsIdle() {
        let headers = [
            header(workspace: "stack", unfinished: false, checkpoint: now.addingTimeInterval(-8))
        ]
        XCTAssertEqual(activity(headers), .idle)
    }

    func testDaysOldUnfinishedRunIsIdle() {
        let headers = [
            header(workspace: "shift-a", unfinished: true, checkpoint: now.addingTimeInterval(-25 * 24 * 3600))
        ]
        XCTAssertEqual(activity(headers), .idle)
    }

    func testBlockingQuestionNeedsYou() {
        let headers = [
            header(
                workspace: "stack",
                blocking: true,
                unfinished: true,
                checkpoint: now.addingTimeInterval(-30),
                updated: now.addingTimeInterval(-3600)
            )
        ]
        XCTAssertEqual(activity(headers), .attention)
    }

    func testStuckBlockingFlagIsNotWaiting() {
        let headers = [
            header(
                workspace: "shift-a",
                blocking: true,
                checkpoint: now.addingTimeInterval(-57 * 3600),
                updated: now.addingTimeInterval(-57 * 3600)
            )
        ]
        XCTAssertEqual(activity(headers), .idle)
    }

    func testModifiedTitleMapsToTheProjectNotTheDirtyWord() {
        let state = ComposerActivity.state(
            matching: "declined-work-and-recommendations.md — shift-sms-ts — Modified",
            workspaces: workspaces,
            headers: [
                header(workspace: "shift-b", unfinished: true, checkpoint: now.addingTimeInterval(-20))
            ],
            now: now
        )
        XCTAssertEqual(state, .working)
    }

    func testFinishedRunBecomesADotUntilTheTabIsOpened() {
        let ended = FinishedChatSignal.resolve(live: .idle, previous: .working, holding: false)
        XCTAssertEqual(ended.state, .completed)
        XCTAssertTrue(ended.holding)

        let still = FinishedChatSignal.resolve(live: .idle, previous: .completed, holding: true)
        XCTAssertEqual(still.state, .completed)
        XCTAssertTrue(still.holding)

        let unrelated = FinishedChatSignal.resolve(live: .idle, previous: .unknown, holding: false)
        XCTAssertEqual(unrelated.state, .idle)
        XCTAssertFalse(unrelated.holding)
    }

    func testVisibleWorkingBeatsAComposerRowWithNoOpenRun() {
        let resolved = AttentionSignals.resolve(
            composer: .idle,
            live: AttentionObservation(state: .working, confidence: 0.85, source: .accessibility)
        )
        XCTAssertEqual(resolved, .working)
    }

    func testComposerWorkingStandsWhenTheWindowCannotBeRead() {
        let resolved = AttentionSignals.resolve(
            composer: .working,
            live: AttentionObservation(state: .unknown, confidence: 0.1, source: .accessibility)
        )
        XCTAssertEqual(resolved, .working)
    }

    func testComposerIdleStandsWhenTheLiveTreeIsUnreadable() {
        let resolved = AttentionSignals.resolve(
            composer: .idle,
            live: AttentionObservation(state: .unknown, confidence: 0.1, source: .accessibility)
        )
        XCTAssertEqual(resolved, .idle)
    }

    func testNewRunClearsTheFinishedDot() {
        let running = FinishedChatSignal.resolve(live: .working, previous: .completed, holding: true)
        XCTAssertEqual(running.state, .working)
        XCTAssertFalse(running.holding)
    }

    func testUnknownProjectDoesNotInventAState() {
        let state = ComposerActivity.state(
            matching: "Cursor Agents",
            workspaces: workspaces,
            headers: [
                header(workspace: "stack", unfinished: true, checkpoint: now.addingTimeInterval(-5))
            ],
            now: now
        )
        XCTAssertNil(state)
    }

    func testChatsInEitherWorkspaceCopyCount() {
        let state = ComposerActivity.state(
            matching: "notes.md — shift-sms-ts — Cursor",
            workspaces: workspaces,
            headers: [
                header(workspace: "shift-a", unfinished: false, checkpoint: now.addingTimeInterval(-10_000)),
                header(workspace: "shift-b", unfinished: true, checkpoint: now.addingTimeInterval(-40))
            ],
            now: now
        )
        XCTAssertEqual(state, .working)
    }

    private func activity(_ headers: [ComposerChatHeader]) -> AttentionState? {
        ComposerActivity.state(
            matching: "index.html — cursor-stack — Cursor",
            workspaces: workspaces,
            headers: headers,
            now: now
        )
    }

    private func header(
        workspace: String,
        blocking: Bool = false,
        unfinished: Bool = false,
        checkpoint: Date? = nil,
        updated: Date? = nil
    ) -> ComposerChatHeader {
        ComposerChatHeader(
            workspaceID: workspace,
            blocking: blocking,
            hasUnfinishedRun: unfinished,
            checkpoint: checkpoint,
            updated: updated
        )
    }
}

final class AttentionScanOrderTests: XCTestCase {
    func testRefreshedWindowIsCheckedBeforeTheSelectedOne() {
        let refreshed = UUID()
        let selected = UUID()
        let other = UUID()
        let order = AttentionCoordinator.scanOrder(
            ids: [other, selected, refreshed],
            forced: refreshed,
            selected: selected
        )
        XCTAssertEqual(order, [refreshed, selected, other])
    }

    func testSelectedWindowStaysFirstWhenNothingWasRefreshed() {
        let selected = UUID()
        let other = UUID()
        let order = AttentionCoordinator.scanOrder(
            ids: [other, selected],
            forced: nil,
            selected: selected
        )
        XCTAssertEqual(order.first, selected)
    }
}

final class ChatControlLabelTests: XCTestCase {
    func testThinkingStatusIsARunningChat() {
        XCTAssertEqual(ChatControlLabel.classify("Thinking"), .working)
        XCTAssertEqual(ChatControlLabel.classify("thinking…"), .working)
    }

    func testStopControlIsStillRunning() {
        XCTAssertEqual(ChatControlLabel.classify("Stop"), .working)
        XCTAssertEqual(ChatControlLabel.classify("Stop generation"), .working)
    }
}

final class ClaudeCodeActivityTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testBusyClaudeSessionMatchesTheProjectFolder() {
        let session = session(folder: "ai-meter", status: "busy", updated: now.addingTimeInterval(-12), pid: 4242)
        XCTAssertTrue(ClaudeCodeActivity.matches(
            title: "index.html — ai-meter — Cursor",
            sessions: [session],
            isAlive: { $0 == 4242 }
        ))
    }

    func testLongBusySessionStaysBusyWhileProcessLives() {
        let session = session(
            folder: "ai-meter",
            status: "busy",
            updated: now.addingTimeInterval(-ComposerActivity.runningWindow - 5),
            pid: 4242
        )
        XCTAssertTrue(ClaudeCodeActivity.isBusy(session, isAlive: { $0 == 4242 }))
        XCTAssertTrue(ClaudeCodeActivity.matches(
            title: "index.html — ai-meter — Cursor",
            sessions: [session],
            isAlive: { $0 == 4242 }
        ))
    }

    func testDeadProcessDoesNotMatch() {
        let session = session(folder: "ai-meter", status: "busy", updated: now.addingTimeInterval(-12), pid: 4242)
        XCTAssertFalse(ClaudeCodeActivity.isBusy(session, isAlive: { _ in false }))
        XCTAssertFalse(ClaudeCodeActivity.matches(
            title: "index.html — ai-meter — Cursor",
            sessions: [session],
            isAlive: { _ in false }
        ))
    }

    func testMissingPidDoesNotMatch() {
        let session = session(folder: "ai-meter", status: "busy", updated: now.addingTimeInterval(-12), pid: nil)
        XCTAssertFalse(ClaudeCodeActivity.isBusy(session, isAlive: { _ in true }))
        XCTAssertFalse(ClaudeCodeActivity.matches(
            title: "index.html — ai-meter — Cursor",
            sessions: [session],
            isAlive: { _ in true }
        ))
    }

    func testIdleSessionDoesNotMatch() {
        let idle = session(folder: "ai-meter", status: "idle", updated: now.addingTimeInterval(-4), pid: 4242)
        XCTAssertFalse(ClaudeCodeActivity.isBusy(idle, isAlive: { _ in true }))
        XCTAssertFalse(ClaudeCodeActivity.matches(
            title: "index.html — ai-meter — Cursor",
            sessions: [idle],
            isAlive: { _ in true }
        ))
    }

    func testParserKeepsCursorSessionsAndDropsTheTerminal() throws {
        let fresh = Int(now.timeIntervalSince1970 * 1000)
        let cursor = Data(#"{"entrypoint":"claude-vscode","cwd":"/Users/jewhurst/GitHub/projects/ai-meter","status":"busy","statusUpdatedAt":\#(fresh),"pid":4242}"#.utf8)
        let terminal = Data(#"{"entrypoint":"cli","cwd":"/tmp/ai-meter","status":"busy","statusUpdatedAt":\#(fresh),"pid":99}"#.utf8)
        let parsed = try XCTUnwrap(ClaudeCodeActivity.session(from: cursor))
        XCTAssertEqual(parsed.folderName, "ai-meter")
        XCTAssertEqual(parsed.status, "busy")
        XCTAssertEqual(parsed.pid, 4242)
        XCTAssertNil(ClaudeCodeActivity.session(from: terminal))
        XCTAssertTrue(ClaudeCodeActivity.isBusy(parsed, isAlive: { $0 == 4242 }))
    }

    func testReaderSkipsKeyFilesAndNonCursorEntrypoints() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("claude-code-activity-\(UUID().uuidString)", isDirectory: true)
        let sessions = root.appendingPathComponent("sessions", isDirectory: true)
        try FileManager.default.createDirectory(at: sessions, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let fresh = Int(now.timeIntervalSince1970 * 1000)
        try Data(#"{"entrypoint":"claude-vscode","cwd":"/work/ai-meter","status":"busy","statusUpdatedAt":\#(fresh),"pid":84806}"#.utf8)
            .write(to: sessions.appendingPathComponent("84806.json"))
        try Data("secret".utf8).write(to: sessions.appendingPathComponent("84806.key"))
        try Data(#"{"entrypoint":"cli","cwd":"/work/other","status":"busy","statusUpdatedAt":\#(fresh),"pid":9}"#.utf8)
            .write(to: sessions.appendingPathComponent("9.json"))

        let reader = ClaudeCodeActivityReader(claudeDirectory: root)
        let loaded = expectation(description: "claude sessions")
        var snapshot = ClaudeCodeSnapshot.empty
        reader.load { value in
            snapshot = value
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 2)

        XCTAssertTrue(snapshot.readable)
        XCTAssertEqual(snapshot.sessions.map(\.folderName), ["ai-meter"])
        XCTAssertEqual(snapshot.sessions.map(\.pid), [84806])
        XCTAssertTrue(ClaudeCodeActivity.matches(
            title: "notes.md — ai-meter — Cursor",
            sessions: snapshot.sessions,
            isAlive: { $0 == 84806 }
        ))
    }

    func testMenuPrefixKeepsTheRingAndAddsTheSpark() {
        XCTAssertEqual(AttentionState.menuPrefix(attention: .working, claudeBusy: false), "○ ")
        XCTAssertEqual(AttentionState.menuPrefix(attention: .idle, claudeBusy: true), "✶ ")
        XCTAssertEqual(AttentionState.menuPrefix(attention: .working, claudeBusy: true), "○ ✶ ")
        XCTAssertEqual(AttentionState.menuPrefix(attention: .attention, claudeBusy: true), "● ✶ ")
    }

    private func session(folder: String, status: String, updated: Date?, pid: Int32?) -> ClaudeCodeSession {
        ClaudeCodeSession(folderName: folder, status: status, statusUpdated: updated, pid: pid)
    }
}

final class GroupMembershipPolicyTests: XCTestCase {
    func testParksAfterThreeMisses() {
        XCTAssertFalse(GroupMembershipPolicy.shouldParkAsUnresolved(consecutiveMisses: 2))
        XCTAssertTrue(GroupMembershipPolicy.shouldParkAsUnresolved(consecutiveMisses: 3))
    }

    func testSkipIngestOnEnumerationFailure() {
        XCTAssertTrue(GroupMembershipPolicy.shouldSkipIngest(enumerationFailed: true))
        XCTAssertFalse(GroupMembershipPolicy.shouldSkipIngest(enumerationFailed: false))
    }
}

@MainActor
final class GroupStoreGuardTests: XCTestCase {
    func testRefusesToOverwriteSavedGroupsWithAnEmptyList() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GroupStore(directory: directory)
        let saved = sampleGroup(name: "Work")
        store.save([saved])
        XCTAssertEqual(store.load().count, 1)

        store.save([])
        XCTAssertEqual(store.load().map(\.id), [saved.id])

        store.save([], allowingEmpty: true)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testResetAllowsALaterEmptySave() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = GroupStore(directory: directory)
        store.save([sampleGroup(name: "Work")])
        store.reset()
        store.save([])
        XCTAssertTrue(store.load().isEmpty)
    }
}

@MainActor
final class GroupRestoreAndReconnectTests: XCTestCase {
    func testRestoreKeepsUnresolvedWhenLiveWindowsAreMissing() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        let persistedID = UUID()
        manager.restore(
            persisted: [sampleGroup(name: "Work", memberID: persistedID, project: "ai-meter")],
            live: []
        )

        XCTAssertEqual(manager.groups.count, 1)
        XCTAssertTrue(manager.groups[0].windows.isEmpty)
        XCTAssertEqual(manager.groups[0].unresolved.map(\.id), [persistedID])
    }

    func testEmptyIngestParksMembersInsteadOfDeletingTheGroup() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        let window = ManagedCursorWindow(
            snapshot: makeSnapshot(title: "App.swift — ai-meter — Cursor", pid: 4_101)
        )
        manager.createGroup(name: "Work", windows: [window])
        XCTAssertEqual(manager.groups.count, 1)
        XCTAssertEqual(manager.groups[0].windows.count, 1)

        for _ in 0..<GroupMembershipPolicy.missThreshold {
            manager.ingestLiveWindows([])
        }

        XCTAssertEqual(manager.groups.count, 1)
        XCTAssertTrue(manager.groups[0].windows.isEmpty)
        XCTAssertEqual(manager.groups[0].unresolved.count, 1)
        XCTAssertEqual(manager.groups[0].unresolved[0].projectDisplayName, "ai-meter")
    }

    func testLaterLiveWindowReconnectsToSavedGroup() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        let persistedID = UUID()
        manager.restore(
            persisted: [sampleGroup(name: "Work", memberID: persistedID, project: "ai-meter")],
            live: []
        )
        XCTAssertEqual(manager.groups[0].unresolved.count, 1)

        manager.ingestLiveWindows([
            makeSnapshot(title: "main.ts — ai-meter — Cursor", pid: 4_202)
        ])

        XCTAssertEqual(manager.groups.count, 1)
        XCTAssertEqual(manager.groups[0].windows.count, 1)
        XCTAssertEqual(manager.groups[0].windows[0].id, persistedID)
        XCTAssertTrue(manager.groups[0].unresolved.isEmpty)
        XCTAssertTrue(manager.ungroupedWindows.isEmpty)
    }

    func testForgetUnresolvedRemovesOneSavedTab() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        let kept = UUID()
        let removed = UUID()
        manager.restore(
            persisted: [
                sampleGroup(
                    name: "Work",
                    members: [
                        (id: kept, project: "ai-meter"),
                        (id: removed, project: "weight")
                    ]
                )
            ],
            live: []
        )

        manager.forgetUnresolved(removed, in: manager.groups[0].id)

        XCTAssertEqual(manager.groups.count, 1)
        XCTAssertEqual(manager.groups[0].unresolved.map(\.id), [kept])
    }

    func testForgetAllUnresolvedRemovesAnEmptyGroup() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        manager.restore(
            persisted: [
                sampleGroup(
                    name: "Work",
                    members: [
                        (id: UUID(), project: "ai-meter"),
                        (id: UUID(), project: "weight")
                    ]
                )
            ],
            live: []
        )

        manager.forgetAllUnresolved(in: manager.groups[0].id)

        XCTAssertTrue(manager.groups.isEmpty)
    }

    func testForgetAllUnresolvedKeepsLiveWindows() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        let liveID = UUID()
        let closedID = UUID()
        manager.restore(
            persisted: [
                sampleGroup(
                    name: "Work",
                    members: [
                        (id: liveID, project: "ai-meter"),
                        (id: closedID, project: "weight")
                    ]
                )
            ],
            live: [ManagedCursorWindow(id: liveID, snapshot: makeSnapshot(title: "App.swift — ai-meter — Cursor", pid: 4_303))]
        )
        XCTAssertEqual(manager.groups[0].windows.map(\.id), [liveID])
        XCTAssertEqual(manager.groups[0].unresolved.map(\.id), [closedID])

        manager.forgetAllUnresolved(in: manager.groups[0].id)

        XCTAssertEqual(manager.groups.count, 1)
        XCTAssertEqual(manager.groups[0].windows.map(\.id), [liveID])
        XCTAssertTrue(manager.groups[0].unresolved.isEmpty)
    }

    func testReplacementWindowRebindsInsteadOfCreatingADuplicate() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        let original = ManagedCursorWindow(
            snapshot: makeSnapshot(title: "App.swift — weight — Cursor", pid: 5_101)
        )
        manager.createGroup(name: "Work", windows: [original])
        let originalID = original.id

        manager.ingestLiveWindows([
            makeSnapshot(title: "App.swift — weight — Cursor", pid: 5_202)
        ])

        XCTAssertEqual(manager.groups.count, 1)
        XCTAssertEqual(manager.groups[0].windows.map(\.id), [originalID])
        XCTAssertTrue(manager.groups[0].unresolved.isEmpty)
        XCTAssertTrue(manager.ungroupedWindows.isEmpty)
        XCTAssertFalse(manager.groups[0].windows[0].isUnavailable)
    }

    func testParkedTabCollapsesWhenTheSameProjectIsAlreadyLive() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        let live = ManagedCursorWindow(
            snapshot: makeSnapshot(title: "App.swift — weight — Cursor", pid: 5_303)
        )
        manager.createGroup(name: "Work", windows: [live])
        manager.groups[0].unresolved = [
            PersistedWindowReference(
                id: UUID(),
                lastTitle: "App.swift — weight — Cursor",
                projectDisplayName: "weight",
                alias: nil,
                lastSeen: Date()
            )
        ]

        manager.ingestLiveWindows([live.snapshot])

        XCTAssertEqual(manager.groups[0].windows.map(\.id), [live.id])
        XCTAssertTrue(manager.groups[0].unresolved.isEmpty)
    }

    func testAddReconnectsMatchingClosedTabInsteadOfDuplicating() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        let closedID = UUID()
        manager.restore(
            persisted: [sampleGroup(name: "Work", memberID: closedID, project: "hook")],
            live: []
        )
        let replacement = ManagedCursorWindow(
            snapshot: makeSnapshot(title: "index.ts — hook — Cursor", pid: 5_404)
        )

        manager.add(windows: [replacement], to: manager.groups[0].id)

        XCTAssertEqual(manager.groups[0].windows.map(\.id), [closedID])
        XCTAssertTrue(manager.groups[0].unresolved.isEmpty)
        XCTAssertTrue(manager.ungroupedWindows.isEmpty)
    }

    func testOverlappingReplacementParksThenCollapsesTheDuplicate() {
        let manager = GroupManager(
            accessibility: AccessibilityService(),
            discovery: CursorDiscoveryService()
        )
        let original = ManagedCursorWindow(
            snapshot: makeSnapshot(title: "App.swift — weight — Cursor", pid: 5_505)
        )
        let replacement = ManagedCursorWindow(
            snapshot: makeSnapshot(title: "App.swift — weight — Cursor", pid: 5_606)
        )
        manager.createGroup(name: "Work", windows: [original, replacement])

        for _ in 0..<GroupMembershipPolicy.missThreshold {
            manager.ingestLiveWindows([replacement.snapshot])
        }

        XCTAssertEqual(manager.groups[0].windows.map(\.id), [replacement.id])
        XCTAssertTrue(manager.groups[0].unresolved.isEmpty)
    }
}

final class CursorAppIdentityTests: XCTestCase {
    func testMatchesTheSignedCursorEditor() {
        XCTAssertTrue(
            CursorAppIdentity.matches(
                bundleID: "com.todesktop.230313mzl4w4u92",
                localizedName: "Cursor",
                bundleFileName: "Cursor.app",
                activationPolicy: .regular,
                excludingBundleID: "dev.jewhurst.CursorStack"
            )
        )
    }

    func testIgnoresAppleCursorUIViewService() {
        XCTAssertFalse(
            CursorAppIdentity.matches(
                bundleID: "com.apple.TextInputUI.xpc.CursorUIViewService",
                localizedName: "CursorUIViewService",
                bundleFileName: "CursorUIViewService.xpc",
                activationPolicy: .prohibited,
                excludingBundleID: "dev.jewhurst.CursorStack"
            )
        )
    }

    func testIgnoresCursorHelpers() {
        XCTAssertFalse(
            CursorAppIdentity.matches(
                bundleID: "com.todesktop.230313mzl4w4u92.helper",
                localizedName: "Cursor Helper: shared-process",
                bundleFileName: "Cursor Helper.app",
                activationPolicy: .accessory,
                excludingBundleID: "dev.jewhurst.CursorStack"
            )
        )
    }

    func testIgnoresCursorStack() {
        XCTAssertFalse(
            CursorAppIdentity.matches(
                bundleID: "dev.jewhurst.CursorStack",
                localizedName: "CursorStack",
                bundleFileName: "CursorStack.app",
                activationPolicy: .regular,
                excludingBundleID: "dev.jewhurst.CursorStack"
            )
        )
    }

    func testMatchesCursorNightly() {
        XCTAssertTrue(
            CursorAppIdentity.matches(
                bundleID: "com.todesktop.cursor-nightly",
                localizedName: "Cursor Nightly",
                bundleFileName: "Cursor Nightly.app",
                activationPolicy: .regular,
                excludingBundleID: "dev.jewhurst.CursorStack"
            )
        )
    }
}

private func sampleGroup(
    name: String,
    memberID: UUID = UUID(),
    project: String = "ai-meter"
) -> CursorWindowGroup {
    sampleGroup(name: name, members: [(id: memberID, project: project)])
}

private func sampleGroup(
    name: String,
    members: [(id: UUID, project: String)]
) -> CursorWindowGroup {
    CursorWindowGroup(
        id: UUID(),
        name: name,
        members: members.map { member in
            PersistedWindowReference(
                id: member.id,
                lastTitle: "App.swift — \(member.project) — Cursor",
                projectDisplayName: member.project,
                alias: nil,
                lastSeen: Date()
            )
        },
        activeMemberID: members.first?.id,
        frame: CodableRect(CGRect(x: 0, y: 0, width: 800, height: 600)),
        settings: GroupSettings()
    )
}

private func makeSnapshot(title: String, pid: pid_t) -> AXWindowSnapshot {
    AXWindowSnapshot(
        pid: pid,
        element: AXUIElementCreateApplication(pid),
        title: title,
        role: kAXWindowRole as String,
        subrole: nil,
        frame: CGRect(x: 40, y: 40, width: 800, height: 600),
        isMinimized: false,
        isMain: true,
        isFocused: true
    )
}
