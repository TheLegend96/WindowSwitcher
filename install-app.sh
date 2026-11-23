#!/bin/bash
set -e

# ==============================================================================
# Window Switcher - 1-Line Seamless macOS Installer
# Installs the latest release directly to /Applications and configures Gatekeeper.
# ==============================================================================

echo "🪟 Installing Window Switcher for macOS..."

REPO="TheLegend96/WindowSwitcher"
DOWNLOAD_URL="https://github.com/$REPO/releases/latest/download/WindowSwitcher.dmg"
TEMP_DMG="/tmp/WindowSwitcher.dmg"
MOUNT_DIR="/tmp/WindowSwitcher_Mount"

# 1. Download latest release DMG
echo "📥 Downloading latest WindowSwitcher release from GitHub..."
curl -fL --progress-bar -o "$TEMP_DMG" "$DOWNLOAD_URL"

# 2. Mount DMG
echo "💿 Mounting installer..."
mkdir -p "$MOUNT_DIR"
hdiutil attach "$TEMP_DMG" -mountpoint "$MOUNT_DIR" -nobrowse -quiet

# 3. Terminate running instance if any
killall WindowSwitcher 2>/dev/null || true
sleep 0.5

# 4. Copy to Applications
echo "📂 Installing WindowSwitcher to /Applications..."
rm -rf /Applications/WindowSwitcher.app
cp -R "$MOUNT_DIR/WindowSwitcher.app" /Applications/

# 5. Clean Gatekeeper quarantine attribute (prevents unverified developer warning)
echo "🛡️ Configuring macOS security permissions..."
xattr -cr /Applications/WindowSwitcher.app 2>/dev/null || true

# 6. Unmount and cleanup
echo "🧹 Cleaning up..."
hdiutil detach "$MOUNT_DIR" -quiet || true
rm -f "$TEMP_DMG"

# 7. Launch application
echo "🚀 Launching Window Switcher..."
open /Applications/WindowSwitcher.app

echo ""
echo "✨ Installation complete! Window Switcher is running."
echo "💡 Use ⌥ Option + Tab (or ⌘ Command + Tab) to switch windows."
