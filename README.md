# Matrix code rain wallpaper

Current baseline version: **0.2.0**

**Matrix code rain wallpaper** is a lightweight macOS menu-bar wallpaper app inspired by the digital-rain atmosphere of *The Matrix*. It renders animated code rain and a large digital clock directly on the desktop, while keeping system resource usage low through a Metal/GPU rendering pipeline.

This project was designed, iterated, optimized, and packaged by **Algernon** with the assistance of **Codex**, OpenAI's coding agent tool. Codex was used throughout the development process for implementation, performance tuning, UI behavior refinement, packaging, and project maintenance.

## Features

- Matrix-style animated code rain rendered as a desktop wallpaper.
- Large digital clock built from code-rain character clusters.
- Character sets including Latin letters, numbers, katakana, symbols, and Greek uppercase letters.
- Pseudo-random glyph mutation designed to reduce CPU cost while preserving a natural visual effect.
- Metal-backed renderer using `MTKView`, glyph atlases, and instanced drawing.
- Menu-bar-only app with no Dock icon.
- Menu-bar controls for:
  - launch at login,
  - auto-pause when all screens are covered by fullscreen apps,
  - auto-pause when running on battery power.
- Persistent user settings through `UserDefaults`.
- Custom black-and-white app icon and menu-bar icon.

## Performance Direction

The project started as a visual experiment and was later optimized around a GPU-first rendering model. The current renderer avoids high-frequency AppKit text drawing, reuses a generated glyph atlas, keeps random updates time-driven, and runs at a reduced but visually smooth frame rate.

## Build

Requirements:

- macOS 13 or later
- Xcode command line tools
- Swift Package Manager

Build and package the app:

```sh
Scripts/build-app.sh
```

The packaged app is generated at:

```text
dist/Matrix code rain wallpaper.app
```

## Project Structure

```text
Assets/                         Vector source for the app logo
Packaging/                      macOS app bundle metadata
Scripts/                        Build and icon generation scripts
Sources/MatrixCodeRainWallpaper AppKit, Metal rendering, settings, and services
```

## Notes

This repository contains the source project. Local build output, packaged apps, performance samples, and rollback snapshots are intentionally excluded from version control.

## Author

by Algernon
