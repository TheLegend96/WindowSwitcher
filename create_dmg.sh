#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="WindowSwitcher"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="WindowSwitcher.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
VOLUME_NAME="Window Switcher"
TEMP_DMG="$BUILD_DIR/temp.dmg"
BG_1X="$BUILD_DIR/dmg_bg_1x.png"
BG_2X="$BUILD_DIR/dmg_bg_2x.png"
BG_TIFF="$BUILD_DIR/dmg_background.tiff"

echo "🔨 Using latest compiled WindowSwitcher.app or building if missing..."
if [ ! -d "$APP_BUNDLE" ]; then
    "$PROJECT_DIR/build.sh"
fi

echo "🎨 Generating Retina DMG installer background..."
swift "$PROJECT_DIR/Resources/dmg_background_gen.swift" "$BG_1X" "$BG_2X"
tiffutil -cathidpicheck "$BG_1X" "$BG_2X" -out "$BG_TIFF"

echo "🧹 Ejecting any existing mounted volumes..."
for d in /Volumes/"$VOLUME_NAME"*; do
    if [ -d "$d" ]; then
        hdiutil detach "$d" -force 2>/dev/null || true
    fi
done
sleep 1

echo "📦 Preparing temporary disk image..."
rm -f "$TEMP_DMG" "$DMG_PATH"
hdiutil create -size 70m -fs HFS+ -volname "$VOLUME_NAME" "$TEMP_DMG"

echo "💿 Mounting temporary disk image..."
MOUNT_DIR=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*' | head -n 1)
echo "Mounted at: $MOUNT_DIR"

echo "📂 Copying WindowSwitcher.app and custom Retina background..."
cp -R "$APP_BUNDLE" "$MOUNT_DIR/WindowSwitcher.app"
mkdir -p "$MOUNT_DIR/.background"
cp "$BG_TIFF" "$MOUNT_DIR/.background/background.tiff"

echo "🔗 Creating Applications alias..."
ln -s /Applications "$MOUNT_DIR/Applications"

echo "🎨 Setting volume custom icon..."
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

echo "🎨 Applying custom Finder DMG visual layout via AppleScript..."
osascript << EOF || true
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        try
            set pathbar visible of container window to false
        end try
        try
            set sidebar width of container window to 0
        end try
        set the bounds of container window to {280, 180, 880, 610}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 112
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        delay 0.8
        set position of item "WindowSwitcher.app" of container window to {165, 170}
        set position of item "Applications" of container window to {435, 170}
        set the bounds of container window to {280, 180, 880, 610}
        update without registering applications
        delay 1.5
        close
    end tell
end tell
EOF

# Ensure changes are flushed
sync
sleep 1

echo "⏏️ Detaching disk image..."
hdiutil detach "$MOUNT_DIR" -force || true

echo "🗜️ Converting to compressed read-only DMG..."
hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"

rm -f "$TEMP_DMG" "$BG_1X" "$BG_2X" "$BG_TIFF"

# Copy to user Downloads folder
DOWNLOADS_DMG="$HOME/Downloads/$DMG_NAME"
cp "$DMG_PATH" "$DOWNLOADS_DMG"

echo "✅ Custom Styled DMG created successfully!"
echo "📍 Workspace Path: $DMG_PATH"
echo "📥 Downloads Path: $DOWNLOADS_DMG"
ls -lh "$DMG_PATH" "$DOWNLOADS_DMG"
