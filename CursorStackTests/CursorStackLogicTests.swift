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
    func testTabPanelSitsOnTopAndClamps() {
        let window = CGRect(x: 100, y: 200, width: 800, height: 600)
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let panel = ScreenCoordinateConverter.tabPanelFrame(windowFrame: window, height: 36, visibleFrame: visible)
        XCTAssertEqual(panel.minX, 100)
        XCTAssertEqual(panel.width, 800)
        XCTAssertEqual(panel.minY, 800)
        XCTAssertEqual(panel.height, 36)
    }

    func testTabPanelClampsToMenuBar() {
        let window = CGRect(x: 0, y: 40, width: 1000, height: 860)
        let visible = CGRect(x: 0, y: 0, width: 1000, height: 878)
        let panel = ScreenCoordinateConverter.tabPanelFrame(windowFrame: window, height: 36, visibleFrame: visible)
        XCTAssertLessThanOrEqual(panel.maxY, visible.maxY)
    }

    func testMaximizeLeavesRoomForTabs() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 944)
        let content = ScreenCoordinateConverter.maximizedContentFrame(visibleFrame: visible, tabHeight: 36)
        XCTAssertEqual(content.height, 908)
        XCTAssertEqual(content.width, 1512)
    }

    func testApproximateEquality() {
        let a = CGRect(x: 10, y: 10, width: 100, height: 100)
        let b = CGRect(x: 11, y: 9.5, width: 100.5, height: 101)
        XCTAssertTrue(ScreenCoordinateConverter.framesApproximatelyEqual(a, b, tolerance: 2))
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
