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

    static func clampedThickness(_ thickness: CGFloat, position: TabBarPosition) -> CGFloat {
        position.isVertical ? max(80, thickness) : max(24, thickness)
    }

    /// Places the CursorStack bar on the chosen edge of Cursor. Top leaves Cursor's
    /// native titlebar and command-center search field fully usable.
    static func tabPanelFrame(
        windowFrame: CGRect,
        position: TabBarPosition,
        thickness: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect {
        let thickness = clampedThickness(thickness, position: position)
        switch position {
        case .top:
            return CGRect(
                x: windowFrame.minX,
                y: windowFrame.maxY,
                width: max(120, windowFrame.width),
                height: thickness
            )
        case .bottom:
            return CGRect(
                x: windowFrame.minX,
                y: windowFrame.minY - thickness,
                width: max(120, windowFrame.width),
                height: thickness
            )
        case .left:
            return CGRect(
                x: windowFrame.minX - thickness,
                y: windowFrame.minY,
                width: thickness,
                height: max(120, windowFrame.height)
            )
        case .right:
            return CGRect(
                x: windowFrame.maxX,
                y: windowFrame.minY,
                width: thickness,
                height: max(120, windowFrame.height)
            )
        }
    }

    static func maximizedContentFrame(
        visibleFrame: CGRect,
        position: TabBarPosition,
        thickness: CGFloat
    ) -> CGRect {
        let thickness = clampedThickness(thickness, position: position)
        switch position {
        case .top:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width,
                height: max(200, visibleFrame.height - thickness)
            )
        case .bottom:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY + thickness,
                width: visibleFrame.width,
                height: max(200, visibleFrame.height - thickness)
            )
        case .left:
            return CGRect(
                x: visibleFrame.minX + thickness,
                y: visibleFrame.minY,
                width: max(200, visibleFrame.width - thickness),
                height: visibleFrame.height
            )
        case .right:
            return CGRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: max(200, visibleFrame.width - thickness),
                height: visibleFrame.height
            )
        }
    }

    /// Returns a Cursor frame that leaves enough room for the bar on the screen
    /// containing most of the window.
    static func contentFrameLeavingTabRoom(
        _ windowFrame: CGRect,
        position: TabBarPosition,
        thickness: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect {
        let thickness = clampedThickness(thickness, position: position)
        switch position {
        case .top:
            let maximumWindowTop = visibleFrame.maxY - thickness
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
        case .bottom:
            let minimumWindowBottom = visibleFrame.minY + thickness
            guard windowFrame.minY < minimumWindowBottom else { return windowFrame }
            let deficit = minimumWindowBottom - windowFrame.minY
            if windowFrame.maxY + deficit <= visibleFrame.maxY {
                return windowFrame.offsetBy(dx: 0, dy: deficit)
            }
            return CGRect(
                x: windowFrame.minX,
                y: minimumWindowBottom,
                width: windowFrame.width,
                height: max(200, windowFrame.height - deficit)
            )
        case .left:
            let minimumWindowLeading = visibleFrame.minX + thickness
            guard windowFrame.minX < minimumWindowLeading else { return windowFrame }
            let deficit = minimumWindowLeading - windowFrame.minX
            if windowFrame.maxX + deficit <= visibleFrame.maxX {
                return windowFrame.offsetBy(dx: deficit, dy: 0)
            }
            return CGRect(
                x: minimumWindowLeading,
                y: windowFrame.minY,
                width: max(200, windowFrame.width - deficit),
                height: windowFrame.height
            )
        case .right:
            let maximumWindowTrailing = visibleFrame.maxX - thickness
            guard windowFrame.maxX > maximumWindowTrailing else { return windowFrame }
            let excess = windowFrame.maxX - maximumWindowTrailing
            if windowFrame.minX - excess >= visibleFrame.minX {
                return windowFrame.offsetBy(dx: -excess, dy: 0)
            }
            return CGRect(
                x: max(windowFrame.minX, visibleFrame.minX),
                y: windowFrame.minY,
                width: max(200, windowFrame.width - excess),
                height: windowFrame.height
            )
        }
    }

    /// Places Cursor against the strip so they move as one unit.
    static func windowFrame(
        matchingTabPanel panelFrame: CGRect,
        windowSize: CGSize,
        position: TabBarPosition
    ) -> CGRect {
        let width = max(200, windowSize.width)
        let height = max(200, windowSize.height)
        switch position {
        case .top:
            return CGRect(
                x: panelFrame.minX,
                y: panelFrame.minY - height,
                width: panelFrame.width,
                height: height
            )
        case .bottom:
            return CGRect(
                x: panelFrame.minX,
                y: panelFrame.maxY,
                width: panelFrame.width,
                height: height
            )
        case .left:
            return CGRect(
                x: panelFrame.maxX,
                y: panelFrame.minY,
                width: width,
                height: panelFrame.height
            )
        case .right:
            return CGRect(
                x: panelFrame.minX - width,
                y: panelFrame.minY,
                width: width,
                height: panelFrame.height
            )
        }
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
