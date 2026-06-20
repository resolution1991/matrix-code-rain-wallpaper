#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Matrix code rain wallpaper"
SWIFT_EXECUTABLE_NAME="MatrixCodeRainWallpaper"
BUNDLE_EXECUTABLE_NAME="$APP_NAME"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BUILD_PATH=".build/wallpaper-build"
ICON_NAME="MatrixCodeRainWallpaper"
ICONSET_DIR="$BUILD_PATH/$ICON_NAME.iconset"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache-wallpaper"

cd "$ROOT_DIR"

swift build \
  -c release \
  --disable-sandbox \
  --build-path "$BUILD_PATH" \
  --cache-path .build/cache-wallpaper \
  --config-path .build/config-wallpaper \
  --security-path .build/security-wallpaper \
  --manifest-cache local

install -d "$MACOS_DIR"
install -d "$RESOURCES_DIR"

install -m 755 "$BUILD_PATH/release/$SWIFT_EXECUTABLE_NAME" "$MACOS_DIR/$BUNDLE_EXECUTABLE_NAME"
install -m 644 "Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
swift "$ROOT_DIR/Scripts/generate-app-icon.swift" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/$ICON_NAME.icns"

codesign --force --deep --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "$APP_BUNDLE"
