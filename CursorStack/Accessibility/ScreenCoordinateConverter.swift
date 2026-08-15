import Foundation
import CoreGraphics

enum ScreenCoordinateConverter {
    /// Accessibility and AppKit window frames both use global Cocoa coordinates
    /// (origin at the bottom-left of the primary display). Keep conversion centralized
    /// so a future coordinate-space change lives in one place.
    static func cocoaRect(fromAX rect: CGRect) -> CGRect { rect }

    static func axRect(fromCocoa rect: CGRect) -> CGRect { rect }

    static func tabPanelFrame(
        windowFrame: CGRect,
        height: CGFloat,
        visibleFrame: CGRect
    ) -> CGRect {
        let height = max(24, height)
        var width = max(120, windowFrame.width)
        var x = windowFrame.minX
        var y = windowFrame.maxY

        if y + height > visibleFrame.maxY {
            y = visibleFrame.maxY - height
        }
        if y < visibleFrame.minY {
            y = visibleFrame.minY
        }

        if x < visibleFrame.minX {
            x = visibleFrame.minX
        }
        if x + width > visibleFrame.maxX {
            width = max(120, visibleFrame.maxX - x)
        }
        if width > visibleFrame.width {
            width = visibleFrame.width
            x = visibleFrame.minX
        }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func maximizedContentFrame(visibleFrame: CGRect, tabHeight: CGFloat) -> CGRect {
        let tabHeight = max(24, tabHeight)
        let height = max(200, visibleFrame.height - tabHeight)
        return CGRect(
            x: visibleFrame.minX,
            y: visibleFrame.minY,
            width: visibleFrame.width,
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
}
