#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_BUNDLE="$BUILD_DIR/WindowSwitcher.app"
DMG_NAME="WindowSwitcher.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"
VOLUME_NAME="Window Switcher"
TEMP_DMG="$BUILD_DIR/temp.dmg"

echo "🔨 Building app bundle first to ensure latest binaries..."
"$PROJECT_DIR/build.sh"

echo "🧹 Ejecting any existing mounted volumes..."
for d in /Volumes/"$VOLUME_NAME"*; do
    if [ -d "$d" ]; then
        hdiutil detach "$d" -force 2>/dev/null || true
    fi
done
sleep 1

echo "📦 Preparing temporary disk image..."
rm -f "$TEMP_DMG" "$DMG_PATH"
hdiutil create -size 60m -fs HFS+ -volname "$VOLUME_NAME" "$TEMP_DMG"

echo "💿 Mounting temporary disk image..."
MOUNT_DIR=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen | grep -o '/Volumes/.*' | head -n 1)
echo "Mounted at: $MOUNT_DIR"

echo "📂 Copying WindowSwitcher.app and guides..."
cp -R "$APP_BUNDLE" "$MOUNT_DIR/WindowSwitcher.app"
cp "$PROJECT_DIR/Resources/Security-Guide.txt" "$MOUNT_DIR/First Launch Guide.txt"

echo "🔗 Creating Applications alias..."
ln -s /Applications "$MOUNT_DIR/Applications"

echo "🎨 Setting volume custom icon..."
if [ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]; then
    cp "$PROJECT_DIR/Resources/AppIcon.icns" "$MOUNT_DIR/.VolumeIcon.icns"
    SetFile -c icnC "$MOUNT_DIR/.VolumeIcon.icns" 2>/dev/null || true
    SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi

echo "🎨 Applying Finder visual layout via AppleScript..."
osascript << EOF || true
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {320, 220, 860, 580}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 110
        set text size of viewOptions to 12
        delay 1
        set position of item "WindowSwitcher.app" of container window to {150, 140}
        set position of item "Applications" of container window to {390, 140}
        set position of item "First Launch Guide.txt" of container window to {270, 260}
        update without registering applications
        delay 1
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

rm -f "$TEMP_DMG"

# Copy to user Downloads folder
DOWNLOADS_DMG="$HOME/Downloads/$DMG_NAME"
cp "$DMG_PATH" "$DOWNLOADS_DMG"

echo "✅ Clean Apple Drag & Drop DMG created successfully!"
echo "📍 Workspace Path: $DMG_PATH"
echo "📥 Downloads Path: $DOWNLOADS_DMG"
ls -lh "$DMG_PATH" "$DOWNLOADS_DMG"
