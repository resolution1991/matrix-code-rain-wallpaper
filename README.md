# Matrix code rain wallpaper

当前基线版本 / Current baseline version: **0.5.0**

## 中文

**Matrix code rain wallpaper** 是一款轻量级 macOS 菜单栏动态壁纸应用。它使用 Metal 在桌面层渲染代码雨和由字符点阵构成的数字时钟，并通过低帧率、字形图集、实例化绘制和按需更新控制 CPU、GPU 与内存占用。

### 主要功能

- Matrix 风格代码雨桌面动画。
- 由代码雨字符簇构成的数字时钟，可随时关闭。
- 雨滴密度可选择低、中（默认）、高，分别为基准密度的 80%、100%、120%。
- 数字时钟采用紧凑字符间距和经过调整的绿色亮度。
- 支持拉丁字母、数字、片假名、符号和希腊大写字母。
- 支持开机自启动、全屏自动暂停和离电自动暂停。
- 所有设置通过 `UserDefaults` 自动保存。
- 使用自定义应用图标和菜单栏图标。

### 0.5.0 更新

- 增加数字时钟显示开关。
- 增加低、中、高三档雨滴密度。
- 关闭时钟后释放相关纹理、缓冲和字符状态，并停止时钟更新与绘制。
- 收紧数字时钟字符簇内及字符簇间距，调整字符亮度。
- 更换正式应用图标。
- 修复并稳定应用打包及 ICNS 生成流程。

### 构建

要求：macOS 13 或更高版本、Xcode Command Line Tools、Swift Package Manager。

```sh
Scripts/build-app.sh
```

应用包生成位置：

```text
dist/Matrix code rain wallpaper.app
```

## English

**Matrix code rain wallpaper** is a lightweight macOS menu-bar wallpaper app. It uses Metal to render animated code rain and a character-mosaic digital clock on the desktop layer while keeping CPU, GPU, and memory usage low through a reduced frame rate, a reusable glyph atlas, instanced drawing, and event-driven updates.

### Features

- Matrix-style animated code rain rendered as a desktop wallpaper.
- Character-mosaic digital clock that can be turned off.
- Low, medium (default), and high rain density at 80%, 100%, and 120% of the baseline density.
- Compact clock-character spacing with tuned green brightness.
- Latin letters, numbers, katakana, symbols, and Greek uppercase characters.
- Launch at login, pause in full screen, and pause on battery controls.
- Persistent settings through `UserDefaults`.
- Custom application and menu-bar icons.

### What's New in 0.5.0

- Added a digital-clock visibility toggle.
- Added low, medium, and high rain-density settings.
- Clock textures, buffers, and glyph state are released when the clock is disabled; clock updates and drawing are also skipped.
- Tightened spacing within and between clock character clusters and tuned character brightness.
- Replaced the official application icon.
- Stabilized application packaging and ICNS generation.

### Build

Requirements: macOS 13 or later, Xcode Command Line Tools, and Swift Package Manager.

```sh
Scripts/build-app.sh
```

The packaged application is generated at:

```text
dist/Matrix code rain wallpaper.app
```

## Project Structure

```text
Assets/                         Application icon source assets
Packaging/                      macOS application bundle metadata
Scripts/                        Build and icon generation scripts
Sources/MatrixCodeRainWallpaper AppKit, Metal rendering, settings, and services
```

Local build output, packaged applications, performance samples, and rollback snapshots are excluded from version control.

## Author

Designed, iterated, optimized, and packaged by **Algernon** with assistance from **Codex**, OpenAI's coding agent.
