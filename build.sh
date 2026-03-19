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

echo "==> Build complete: $APP_BUNDLE"
