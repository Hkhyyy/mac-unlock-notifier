#!/bin/bash
set -e

BUILD_DIR="build"
APP_NAME="UnlockNotifier"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS"

echo "==> Compiling unlock-notifier.swift..."
swiftc -framework AVFoundation -framework Cocoa \
    unlock-notifier.swift \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> Copying Info.plist..."
cp Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "==> Generating app icon..."
if [ ! -f AppIcon.icns ]; then
    swiftc -framework Cocoa generate-icon.swift -o /tmp/generate-icon && /tmp/generate-icon
    iconutil -c icns AppIcon.iconset -o AppIcon.icns
    rm -rf AppIcon.iconset
fi
mkdir -p "$APP_BUNDLE/Contents/Resources"
cp AppIcon.icns "$APP_BUNDLE/Contents/Resources/"

echo "==> Build complete: $APP_BUNDLE"
