import AppKit
import CoreGraphics

final class WallpaperWindow: NSWindow {
    private var rainView: MetalRainView?

    init(screen: NSScreen, isPaused: Bool, settings: AppSettings) {
        let frame = screen.frame

        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        let desktopLevel = CGWindowLevelForKey(.desktopWindow)
        level = NSWindow.Level(rawValue: Int(desktopLevel + 1))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        hasShadow = false
        isOpaque = true
        backgroundColor = .black
        isReleasedWhenClosed = false
        canHide = false

        let view = MetalRainView(
            frame: NSRect(origin: .zero, size: frame.size),
            settings: settings
        )
        view.autoresizingMask = [.width, .height]
        contentView = view
        rainView = view

        if isPaused {
            view.pause()
        }
    }

    func pauseAnimation() {
        rainView?.pause()
    }

    func resumeAnimation() {
        rainView?.resume()
    }

    func updateVisualSettings(_ settings: AppSettings) {
        rainView?.updateVisualSettings(settings)
    }

    func showWallpaper() {
        orderFrontRegardless()
    }

    func hideWallpaper() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
