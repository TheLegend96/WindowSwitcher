#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/build/WindowSwitcher.app"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Building application first..."
    "$PROJECT_DIR/build.sh"
fi

echo "🛑 Stopping any running instances..."
killall WindowSwitcher 2>/dev/null || true
sleep 0.5

DEST_DIR="/Applications"
if [ -w "$DEST_DIR" ]; then
    TARGET="$DEST_DIR/WindowSwitcher.app"
    rm -rf "$TARGET"
    cp -R "$APP_BUNDLE" "$DEST_DIR/"
    echo "✅ Installed to $TARGET"
else
    TARGET="$HOME/Applications/WindowSwitcher.app"
    mkdir -p "$HOME/Applications"
    rm -rf "$TARGET"
    cp -R "$APP_BUNDLE" "$HOME/Applications/"
    echo "✅ Installed to $TARGET"
fi

echo "🚀 Opening WindowSwitcher..."
open "$TARGET"
