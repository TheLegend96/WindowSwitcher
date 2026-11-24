import AppKit
import SwiftUI
import ScreenCaptureKit

@MainActor
public class ScreenshotCoordinator: NSObject {
    public static let shared = ScreenshotCoordinator()

    private var currentPanel: ScreenshotSelectionPanel?
    private var isCapturing: Bool = false

    private override init() {
        super.init()
    }

    /// Starts interactive Area Screenshot capture on the display where the cursor is.
    public func startAreaCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        SwitcherState.shared.dismiss()

        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        let panel = ScreenshotSelectionPanel(screen: targetScreen)
        self.currentPanel = panel

        panel.selectionCallback = { [weak self] selectedRect in
            self?.handleAreaSelected(rect: selectedRect, on: targetScreen)
        }

        panel.cancelCallback = { [weak self] in
            self?.cleanup()
        }

        panel.orderFrontRegardless()
        panel.makeKey()
    }

    /// Captures the active / frontmost application window with full shadow and borders.
    public func captureActiveWindow() {
        SwitcherState.shared.dismiss()

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
                guard let window = content.windows.first(where: {
                    $0.isOnScreen && $0.frame.width > 100 && $0.frame.height > 100 &&
                    !($0.owningApplication?.bundleIdentifier.lowercased().contains("windowswitcher") ?? false)
                }) else {
                    ToastHUDController.shared.showSimpleToast(message: "No active window found", icon: "macwindow.badge.plus")
                    return
                }

                let targetScreen = NSScreen.screens.first { $0.frame.intersects(window.frame) } ?? NSScreen.main ?? NSScreen.screens[0]
                let scale = targetScreen.backingScaleFactor

                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(x: 0, y: 0, width: window.frame.width, height: window.frame.height)
                config.width = max(1, Int(window.frame.width * scale))
                config.height = max(1, Int(window.frame.height * scale))
                config.showsCursor = false

                let filter = SCContentFilter(desktopIndependentWindow: window)
                let capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                playCaptureSound()
                copyToClipboard(image: capturedImage)

                let nsImage = NSImage(cgImage: capturedImage, size: window.frame.size)
                ScreenshotEditorWindowController.shared.show(image: nsImage, sourceRect: window.frame, on: targetScreen)
            } catch {
                print("⚠️ Window capture error: \(error)")
                ToastHUDController.shared.showSimpleToast(message: "Capture failed", icon: "xmark.circle")
            }
        }
    }

    private func handleAreaSelected(rect: NSRect, on screen: NSScreen) {
        cleanup()

        guard rect.width >= 4 && rect.height >= 4 else { return }

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                guard let display = content.displays.first(where: { $0.displayID == screenNumber }) ?? content.displays.first else {
                    ToastHUDController.shared.showSimpleToast(message: "Could not access display", icon: "exclamationmark.triangle", on: screen)
                    return
                }

                let screenBounds = screen.frame
                let relX = rect.origin.x - screenBounds.origin.x
                let relY = screenBounds.height - (rect.origin.y - screenBounds.origin.y + rect.height)

                let scale = screen.backingScaleFactor
                let sourceRect = CGRect(x: max(0, relX), y: max(0, relY), width: rect.width, height: rect.height)

                let config = SCStreamConfiguration()
                config.sourceRect = sourceRect
                config.width = max(1, Int(rect.width * scale))
                config.height = max(1, Int(rect.height * scale))
                config.scalesToFit = false
                config.showsCursor = false

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let capturedImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                playCaptureSound()
                copyToClipboard(image: capturedImage)

                let nsImage = NSImage(cgImage: capturedImage, size: rect.size)

                if SettingsManager.shared.autoOpenEditor {
                    ScreenshotEditorWindowController.shared.show(image: nsImage, sourceRect: rect, on: screen)
                } else {
                    ToastHUDController.shared.showSimpleToast(message: "Screenshot copied to clipboard", icon: "camera.viewfinder", on: screen)
                }
            } catch {
                print("⚠️ Area capture failed: \(error)")
                ToastHUDController.shared.showSimpleToast(message: "Capture failed", icon: "xmark.circle", on: screen)
            }
        }
    }

    private func playCaptureSound() {
        guard SettingsManager.shared.playShutterSound else { return }
        let soundPath = "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif"
        if FileManager.default.fileExists(atPath: soundPath) {
            NSSound(contentsOfFile: soundPath, byReference: true)?.play()
        } else {
            NSSound.beep()
        }
    }

    private func copyToClipboard(image: CGImage) {
        let rep = NSBitmapImageRep(cgImage: image)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            let pboard = NSPasteboard.general
            pboard.clearContents()
            pboard.setData(pngData, forType: .png)
        }
    }

    private func cleanup() {
        currentPanel?.orderOut(nil)
        currentPanel = nil
        isCapturing = false
    }
}

// MARK: - Interactive Retina Selection Panel
private class ScreenshotSelectionPanel: NSPanel {
    var selectionCallback: ((NSRect) -> Void)?
    var cancelCallback: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        let overlayView = ScreenshotSelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
        overlayView.onComplete = { [weak self] rect in
            self?.selectionCallback?(rect)
        }
        overlayView.onCancel = { [weak self] in
            self?.cancelCallback?()
        }
        self.contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Interactive Canvas Overlay with Crosshair & Telemetry
private class ScreenshotSelectionOverlayView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var trackingAreaRef: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        startPoint = loc
        currentPoint = loc
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseMoved(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = startPoint, let c = currentPoint else {
            onCancel?()
            return
        }
        let selRect = normalizedRect(from: s, to: c)
        if selRect.width > 4 && selRect.height > 4 {
            let screenOrigin = window?.frame.origin ?? .zero
            let absoluteRect = NSRect(
                x: screenOrigin.x + selRect.origin.x,
                y: screenOrigin.y + selRect.origin.y,
                width: selRect.width,
                height: selRect.height
            )
            onComplete?(absoluteRect)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Dim background
        context.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.fill(bounds)

        // Clear selected area
        if let s = startPoint, let c = currentPoint, s != c {
            let sel = normalizedRect(from: s, to: c)
            context.clear(sel)

            // Accent border
            context.setStrokeColor(NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.95).cgColor)
            context.setLineWidth(1.5)
            context.stroke(sel)

            // Dimension Badge (w × h pt)
            let badgeText = "\(Int(sel.width)) × \(Int(sel.height)) pt" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let textSize = badgeText.size(withAttributes: attrs)
            let badgeRect = NSRect(
                x: min(max(sel.midX - (textSize.width + 14)/2, 8), bounds.width - textSize.width - 20),
                y: sel.minY >= 30 ? sel.minY - 26 : sel.maxY + 8,
                width: textSize.width + 14,
                height: 20
            )

            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
            NSColor.black.withAlphaComponent(0.85).setFill()
            badgePath.fill()

            badgeText.draw(at: NSPoint(x: badgeRect.origin.x + 7, y: badgeRect.origin.y + 3), withAttributes: attrs)
        } else if let c = currentPoint {
            // Fullscreen Crosshair Guides
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(0.8)
            context.strokeLineSegments(between: [
                CGPoint(x: 0, y: c.y), CGPoint(x: bounds.width, y: c.y),
                CGPoint(x: c.x, y: 0), CGPoint(x: c.x, y: bounds.height)
            ])
        }
    }

    private func normalizedRect(from p1: NSPoint, to p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let w = abs(p1.x - p2.x)
        let h = abs(p1.y - p2.y)
        return NSRect(x: x, y: y, width: w, height: h)
    }
}
