# WindowSwitcher for macOS (Apple Silicon Native)

A fast, lightweight, native macOS window switcher inspired by Windows Alt-Tab and [alt-tab.app](https://alt-tab.app/), built specifically for Apple Silicon (M1/M2/M3/M4) Macs using Swift 6, AppKit, SwiftUI, and ScreenCaptureKit.

---

## Features

- **Apple Silicon Optimized (`arm64`)**: Compiled natively with zero Rosetta overhead and 0% idle CPU footprint.
- **Hardware-Accelerated Previews**: Uses macOS `ScreenCaptureKit` to capture live window thumbnails directly onto GPU textures.
- **Signature Windows Alt-Tab Feel**:
  - Press and hold `Option` (Alt) and tap `Tab` to cycle forward.
  - Hold `Shift` + tap `Tab` to cycle backward.
  - Use Left/Right Arrow keys or mouse hover to pick a window.
  - Release `Option` to immediately switch to and raise that window.
- **Search-to-Filter**: Start typing while the switcher is open to instantly filter windows by title or application name.
- **Quick Close (`W`)**: Press `W` or click the `✕` close button on any thumbnail card to close that window without switching first.
- **Multi-Window & State Badges**: Identifies standard, minimized, and hidden windows across apps.
- **Clean macOS Translucent UI**: Built with native SwiftUI vibrancy materials, crisp SF Pro typography, and 4px grid rhythm.
- **Menu Bar Controller**: Sits silently in the macOS menu bar with quick access to trigger the switcher, open Preferences, or quit.

---

## System Permissions Setup

On first launch, macOS requires two permissions in **System Settings > Privacy & Security**:

1. **Accessibility**: Allows WindowSwitcher to detect the `Option + Tab` global shortcut and programmatically raise the selected window.
2. **Screen Recording**: Allows `ScreenCaptureKit` to capture window preview thumbnails.

The Preferences window provides one-click shortcut buttons to open the exact System Settings panes.

---

## Build & Install

```bash
# Build the application bundle
./build.sh

# Install into /Applications and launch
./install.sh
```
