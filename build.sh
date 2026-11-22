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
codesign --force --deep --sign - --requirements '=designated => identifier "com.custom.windowswitcher"' "$APP_BUNDLE"

echo "✅ Build successful!"
echo "📍 Application created at: $APP_BUNDLE"
