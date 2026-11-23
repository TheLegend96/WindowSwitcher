#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="WindowSwitcher"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_BUNDLE/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo "🔨 Building $APP_NAME for Apple Silicon (arm64)..."

rm -rf "$BUILD_DIR"
mkdir -p "$MACOS"
mkdir -p "$RESOURCES"

# Copy Info.plist and Resources
cp "$PROJECT_DIR/Resources/Info.plist" "$CONTENTS/Info.plist"
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES/AppIcon.icns"
fi
if [ -f "$PROJECT_DIR/Resources/AppIcon-CobaltAzure.png" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon-CobaltAzure.png" "$RESOURCES/AppIcon-CobaltAzure.png"
fi

# Collect all swift source files
SOURCES=$(find "$PROJECT_DIR/Sources" -name "*.swift")

echo "📦 Compiling Swift sources..."
swiftc -O \
    -parse-as-library \
    -target arm64-apple-macos14.0 \
    -framework Cocoa \
    -framework SwiftUI \
    -framework Combine \
    -framework ApplicationServices \
    -framework ScreenCaptureKit \
    -framework CoreMedia \
    -framework VideoToolbox \
    -framework ServiceManagement \
    -framework Metal \
    -framework CoreImage \
    -o "$MACOS/$APP_NAME" \
    $SOURCES

echo "✍️ Signing application bundle..."
ENTITLEMENTS="$PROJECT_DIR/Resources/Entitlements.plist"

# Check if a Developer ID certificate is available
DEV_ID="${DEVELOPER_ID:-}"
if [ -z "$DEV_ID" ]; then
    DEV_ID=$(security find-identity -p codesigning -v | grep "Developer ID Application:" | head -n 1 | awk -F '"' '{print $2}' || true)
fi

if [ -n "$DEV_ID" ]; then
    echo "🔑 Signing with Apple Developer ID: $DEV_ID..."
    codesign --force --deep --options runtime --timestamp \
        --entitlements "$ENTITLEMENTS" \
        --sign "$DEV_ID" \
        "$APP_BUNDLE"
    echo "🔒 Hardened runtime and Apple Developer signature verified."
else
    echo "ℹ️ No Apple Developer ID found. Signing ad-hoc with designated identifier..."
    codesign --force --deep \
        --entitlements "$ENTITLEMENTS" \
        --sign - \
        --requirements '=designated => identifier "com.custom.windowswitcher"' \
        "$APP_BUNDLE"
fi

echo "✅ Build successful!"
echo "📍 Application created at: $APP_BUNDLE"
