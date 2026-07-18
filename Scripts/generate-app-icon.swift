#!/usr/bin/env swift

import AppKit
import Foundation

let sourceURL = URL(fileURLWithPath: "Assets/AppIcon.png")
guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fatalError("Unable to load app icon at \(sourceURL.path)")
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
    sourceImage.draw(
        in: NSRect(x: 0, y: 0, width: icon.pixels, height: icon.pixels),
        from: .zero,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = representation.representation(using: .png, properties: [:]) else {
        fatalError("Unable to encode \(icon.name)")
    }

    try png.write(to: iconsetURL.appendingPathComponent(icon.name))
}
