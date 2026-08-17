import AppKit
import CoreGraphics

enum ScreenCoordinateConverter {
    static func cocoaRect(fromAX rect: CGRect) -> CGRect {
        cocoaRect(fromAX: rect, primaryScreenMaxY: primaryScreenMaxY)
    }

    static func cocoaRect(fromAX rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func axRect(fromCocoa rect: CGRect) -> CGRect {
        axRect(fromCocoa: rect, primaryScreenMaxY: primaryScreenMaxY)
    }

    static func axRect(fromCocoa rect: CGRect, primaryScreenMaxY: CGFloat) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenMaxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    static func visibleFraction(of frame: CGRect, in visibleFrames: [CGRect]) -> CGFloat {
        guard frame.width > 0, frame.height > 0 else { return 0 }
        let visibleArea = visibleFrames.reduce(CGFloat.zero) {
            $0 + $1.intersection(frame).standardizedArea
        }
        return min(1, visibleArea / frame.standardizedArea)
    }

    static func recoveredFrame(_ frame: CGRect, visibleFrames: [CGRect]) -> CGRect {
        guard !visibleFrames.isEmpty else { return frame }
        if visibleFraction(of: frame, in: visibleFrames) >= 0.1 {
            return frame
        }

        let target = visibleFrames.max {
            $0.standardizedArea < $1.standardizedArea
        } ?? visibleFrames[0]
        let width = min(max(frame.width, 640), target.width)
        let height = min(max(frame.height, 480), target.height)
        return CGRect(
            x: target.midX - width / 2,
            y: target.midY - height / 2,
            width: width,
            height: height
        )
    }

    /// Places the CursorStack bar directly above Cursor, leaving Cursor's native
    /// titlebar and command-center search field fully usable.
    static func tabPanelFrame(
        windowFrame: CGRect,
        height: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect {
        let height = max(24, height)
        return CGRect(
            x: windowFrame.minX,
            y: windowFrame.maxY,
            width: max(120, windowFrame.width),
            height: height
        )
    }

    static func maximizedContentFrame(visibleFrame: CGRect, tabHeight: CGFloat) -> CGRect {
        let height = max(24, tabHeight)
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
            height: max(200, visibleFrame.height - height)
        )
    }

    /// Returns a Cursor frame that leaves enough room for the bar on the screen
    /// containing most of the window.
    static func contentFrameLeavingTabRoom(
        _ windowFrame: CGRect,
        tabHeight: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect {
        let tabHeight = max(24, tabHeight)
        let maximumWindowTop = visibleFrame.maxY - tabHeight
        guard windowFrame.maxY > maximumWindowTop else { return windowFrame }

        let excess = windowFrame.maxY - maximumWindowTop
        if windowFrame.minY - excess >= visibleFrame.minY {
            return windowFrame.offsetBy(dx: 0, dy: -excess)
        }

        return CGRect(
            x: windowFrame.minX,
            y: max(windowFrame.minY, visibleFrame.minY),
            width: windowFrame.width,
            height: max(200, windowFrame.height - excess)
        )
    }

    /// Cursor's top edge sits immediately below the bar.
    static func windowFrame(matchingTabPanel panelFrame: CGRect, windowHeight: CGFloat) -> CGRect {
        let height = max(200, windowHeight)
        return CGRect(
            x: panelFrame.minX,
            y: panelFrame.minY - height,
            width: panelFrame.width,
            height: height
        )
    }

    static func framesApproximatelyEqual(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= tolerance
            && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance
            && abs(a.height - b.height) <= tolerance
    }

    static func looksFullScreen(_ frame: CGRect, screenFrame: CGRect) -> Bool {
        abs(frame.width - screenFrame.width) <= 2 && abs(frame.height - screenFrame.height) <= 2
    }

    private static var primaryScreenMaxY: CGFloat {
        let screens = NSScreen.screens
        return screens.first(where: { $0.frame.contains(CGPoint.zero) })?.frame.maxY
            ?? screens.first?.frame.maxY
            ?? 0
    }
}

private extension CGRect {
    var standardizedArea: CGFloat {
        let rect = standardized
        return max(0, rect.width) * max(0, rect.height)
    }
}
