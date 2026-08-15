import AppKit
import Foundation
import ScreenCaptureKit

@MainActor
final class VisualAttentionProvider: AttentionSignalProvider {
    var onStateChanged: ((UUID, AttentionObservation) -> Void)?

    private var monitored = Set<UUID>()
    private var lastSample: [UUID: Double] = [:]

    func startMonitoring(window: ManagedCursorWindow) {
        monitored.insert(window.id)
    }

    func stopMonitoring(window: ManagedCursorWindow) {
        monitored.remove(window.id)
        lastSample[window.id] = nil
    }

    func poll(window: ManagedCursorWindow) -> AttentionObservation? {
        guard monitored.contains(window.id) else { return nil }
        let saturation = sampleSaturation(for: window)
        guard let saturation else {
            return AttentionObservation(state: .unknown, confidence: 0.05, source: .visual)
        }

        let previous = lastSample[window.id]
        lastSample[window.id] = saturation

        if saturation > 0.18, previous != nil, saturation > (previous ?? 0) + 0.05 {
            let observation = AttentionObservation(state: .attention, confidence: 0.45, source: .visual)
            onStateChanged?(window.id, observation)
            return observation
        }
        return AttentionObservation(state: .unknown, confidence: 0.1, source: .visual)
    }

    private func sampleSaturation(for window: ManagedCursorWindow) -> Double? {
        guard let cgWindowID = matchingCGWindowID(for: window) else { return nil }
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            cgWindowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else { return nil }

        let height = max(1, image.height)
        let cropHeight = max(8, Int(CGFloat(height) * 0.08))
        let crop = CGRect(x: 0, y: 0, width: image.width, height: cropHeight)
        guard let cropped = image.cropping(to: crop) else { return nil }
        return averageSaturation(of: cropped)
    }

    private func matchingCGWindowID(for window: ManagedCursorWindow) -> CGWindowID? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        let title = window.title
        let pid = Int(window.pid)
        let frame = window.frame

        var best: (id: CGWindowID, score: Int)?
        for entry in info {
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? Int, ownerPID == pid else { continue }
            guard let number = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
            var score = 0
            if let name = entry[kCGWindowName as String] as? String, !name.isEmpty {
                if name == title { score += 50 }
                else if title.contains(name) || name.contains(title) { score += 20 }
            }
            if let bounds = entry[kCGWindowBounds as String] as? [String: CGFloat] {
                let cgFrame = CGRect(
                    x: bounds["X"] ?? 0,
                    y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 0,
                    height: bounds["Height"] ?? 0
                )
                // CGWindow bounds are top-left relative to the main display.
                let cocoa = cgWindowRectToCocoa(cgFrame)
                if ScreenCoordinateConverter.framesApproximatelyEqual(cocoa, frame, tolerance: 40) {
                    score += 40
                }
            }
            if score > (best?.score ?? 0) {
                best = (number, score)
            }
        }
        return (best?.score ?? 0) >= 20 ? best?.id : nil
    }

    private func cgWindowRectToCocoa(_ rect: CGRect) -> CGRect {
        let screenHeight = NSScreen.screens.map(\.frame.maxY).max() ?? NSScreen.main?.frame.maxY ?? 0
        return CGRect(
            x: rect.origin.x,
            y: screenHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    private func averageSaturation(of image: CGImage) -> Double {
        let width = min(image.width, 80)
        let height = min(image.height, 24)
        guard width > 0, height > 0 else { return 0 }
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return 0 }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return 0 }
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var total = 0.0
        var count = 0.0
        var i = 0
        while i < width * height * 4 {
            let r = Double(buffer[i]) / 255.0
            let g = Double(buffer[i + 1]) / 255.0
            let b = Double(buffer[i + 2]) / 255.0
            let maxC = max(r, max(g, b))
            let minC = min(r, min(g, b))
            let sat = maxC == 0 ? 0 : (maxC - minC) / maxC
            total += sat
            count += 1
            i += 4
        }
        return count == 0 ? 0 : total / count
    }
}
