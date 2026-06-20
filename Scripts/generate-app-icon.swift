#!/usr/bin/env swift

import AppKit
import Foundation

enum MatrixLogoIcon {
    static func draw(in rect: NSRect) {
        let side = min(rect.width, rect.height)
        let bounds = NSRect(
            x: rect.midX - side / 2,
            y: rect.midY - side / 2,
            width: side,
            height: side
        )

        let background = NSBezierPath(
            roundedRect: bounds.insetBy(dx: side * 0.074, dy: side * 0.074),
            xRadius: side * 0.191,
            yRadius: side * 0.191
        )
        NSColor.white.setFill()
        background.fill()

        let strokeWidth = side * 0.117
        let markOuterInset = side * 0.247
        let markCenterInset = markOuterInset + strokeWidth / 2
        let leftX = bounds.minX + markCenterInset
        let rightX = bounds.maxX - markCenterInset
        let topY = bounds.maxY - markCenterInset
        let bottomY = bounds.minY + markCenterInset
        let notchY = bounds.minY + side * 0.473

        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: leftX, y: bottomY))
        mark.line(to: NSPoint(x: leftX, y: topY))
        mark.line(to: NSPoint(x: bounds.midX, y: notchY))
        mark.line(to: NSPoint(x: rightX, y: topY))
        mark.line(to: NSPoint(x: rightX, y: bottomY))
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        mark.lineWidth = strokeWidth

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        NSColor.black.setStroke()
        mark.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}

let iconsetPath = CommandLine.arguments.dropFirst().first ?? ".build/MatrixCodeRainWallpaper.iconset"
let iconsetURL = URL(fileURLWithPath: iconsetPath)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

let icons: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for icon in icons {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: icon.pixels,
        pixelsHigh: icon.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("Unable to create bitmap representation for \(icon.name)")
    }

    representation.size = NSSize(width: icon.pixels, height: icon.pixels)
    guard let context = NSGraphicsContext(bitmapImageRep: representation) else {
        fatalError("Unable to create graphics context for \(icon.name)")
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    MatrixLogoIcon.draw(in: NSRect(x: 0, y: 0, width: icon.pixels, height: icon.pixels))
    NSGraphicsContext.restoreGraphicsState()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(icon.name)")
    }

    try png.write(to: iconsetURL.appendingPathComponent(icon.name))
}
