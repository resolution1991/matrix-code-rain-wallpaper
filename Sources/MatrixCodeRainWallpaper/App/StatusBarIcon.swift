import AppKit

enum StatusBarIcon {
    static func makeLogoIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            drawLogo(in: rect)
            return true
        }
        image.accessibilityDescription = "Matrix code rain wallpaper"
        image.isTemplate = false
        return image
    }

    private static func drawLogo(in rect: NSRect) {
        let side = min(rect.width, rect.height)
        let bounds = NSRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )

        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: bounds).addClip()

        let background = NSBezierPath(
            roundedRect: bounds.insetBy(dx: side * 0.074, dy: side * 0.074),
            xRadius: side * 0.191,
            yRadius: side * 0.191
        )
        NSColor.white.setFill()
        background.fill()

        drawMonogram(in: bounds)

        NSGraphicsContext.restoreGraphicsState()
    }

    private static func drawMonogram(in bounds: NSRect) {
        let side = bounds.width
        let strokeWidth = side * 0.117
        let markOuterInset = side * 0.247
        let markCenterInset = markOuterInset + strokeWidth / 2
        let leftX = bounds.minX + markCenterInset
        let rightX = bounds.maxX - markCenterInset
        let topY = bounds.maxY - markCenterInset
        let bottomY = bounds.minY + markCenterInset
        let notchY = bounds.minY + side * 0.473

        let path = NSBezierPath()
        path.move(to: NSPoint(x: leftX, y: bottomY))
        path.line(to: NSPoint(x: leftX, y: topY))
        path.line(to: NSPoint(x: bounds.midX, y: notchY))
        path.line(to: NSPoint(x: rightX, y: topY))
        path.line(to: NSPoint(x: rightX, y: bottomY))
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = strokeWidth

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        path.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
