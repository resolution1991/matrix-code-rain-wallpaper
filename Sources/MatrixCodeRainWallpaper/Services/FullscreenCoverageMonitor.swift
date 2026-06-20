import AppKit
import CoreGraphics
import Foundation

enum FullscreenCoverageMonitor {
    static func areAllScreensCoveredByFullscreenWindows() -> Bool {
        let screens = screenRectsInWindowCoordinates()
        guard !screens.isEmpty else {
            return false
        }

        let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] ?? []

        return screens.allSatisfy { screen in
            windows.contains { windowInfo in
                covers(screen: screen, with: windowInfo)
            }
        }
    }

    private static func screenRectsInWindowCoordinates() -> [CGRect] {
        let screens = NSScreen.screens
        guard let firstFrame = screens.first?.frame else {
            return []
        }

        let union = screens.dropFirst().reduce(firstFrame) { partial, screen in
            partial.union(screen.frame)
        }

        return screens.map { screen in
            CGRect(
                x: screen.frame.minX - union.minX,
                y: union.maxY - screen.frame.maxY,
                width: screen.frame.width,
                height: screen.frame.height
            )
        }
    }

    private static func covers(screen: CGRect, with windowInfo: [String: Any]) -> Bool {
        guard
            let layer = windowInfo[kCGWindowLayer as String] as? Int,
            layer == 0,
            let ownerPID = windowInfo[kCGWindowOwnerPID as String] as? pid_t,
            ownerPID != ProcessInfo.processInfo.processIdentifier,
            let boundsDictionary = windowInfo[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else {
            return false
        }

        if let alpha = windowInfo[kCGWindowAlpha as String] as? Double, alpha <= 0.05 {
            return false
        }

        let intersection = screen.intersection(bounds)
        guard !intersection.isNull, !intersection.isEmpty else {
            return false
        }

        let screenArea = screen.width * screen.height
        guard screenArea > 0 else {
            return false
        }

        let coveredArea = intersection.width * intersection.height
        let coverage = coveredArea / screenArea

        return coverage >= 0.92
            && bounds.width >= screen.width * 0.90
            && bounds.height >= screen.height * 0.90
    }
}
