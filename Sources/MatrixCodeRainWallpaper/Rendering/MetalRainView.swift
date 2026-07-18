import AppKit
import Metal
import MetalKit

final class MetalRainView: MTKView {
    private var rainRenderer: MetalRainRenderer?

    init(frame frameRect: NSRect, settings: AppSettings) {
        let device = MTLCreateSystemDefaultDevice()
        super.init(frame: frameRect, device: device)

        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        preferredFramesPerSecond = 16
        enableSetNeedsDisplay = false
        framebufferOnly = true
        isPaused = false

        guard let device else {
            layer?.backgroundColor = NSColor.black.cgColor
            return
        }

        let renderer = MetalRainRenderer(
            device: device,
            pixelFormat: colorPixelFormat,
            showsDigitalClock: settings.showsDigitalClock,
            rainDensity: settings.rainDensity
        )
        delegate = renderer
        rainRenderer = renderer
        renderer.resize(to: bounds.size)
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func pause() {
        isPaused = true
    }

    func resume() {
        rainRenderer?.resetFrameClock()
        isPaused = false
    }

    func updateVisualSettings(_ settings: AppSettings) {
        rainRenderer?.updateVisualSettings(
            showsDigitalClock: settings.showsDigitalClock,
            rainDensity: settings.rainDensity
        )
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        rainRenderer?.resize(to: newSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        rainRenderer?.resize(to: bounds.size)
    }
}
