#!/bin/bash
set -e

APP_NAME="UnlockNotifier"
DMG_NAME="$APP_NAME.dmg"
BUILD_DIR="build"
DMG_DIR="$BUILD_DIR/dmg"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"

# Build first if needed
if [ ! -d "$APP_BUNDLE" ]; then
    echo "==> App bundle not found, building..."
    ./build.sh
fi

echo "==> Preparing DMG contents..."
rm -rf "$DMG_DIR"
mkdir -p "$DMG_DIR"
cp -R "$APP_BUNDLE" "$DMG_DIR/"
ln -s /Applications "$DMG_DIR/Applications"

echo "==> Creating DMG..."
rm -f "$BUILD_DIR/$DMG_NAME"
hdiutil create "$BUILD_DIR/$DMG_NAME" \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_DIR" \
    -ov -format UDZO

rm -rf "$DMG_DIR"

echo "==> DMG created: $BUILD_DIR/$DMG_NAME"
