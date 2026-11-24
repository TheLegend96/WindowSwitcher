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

    /// Triggers instant freeze-frame capture on the active display.
    /// Supports both:
    /// 1. Dragging a custom area box.
    /// 2. Clicking any hovered window to capture with Apple drop shadow.
    public func startAreaCapture() {
        guard !isCapturing else { return }
        isCapturing = true

        SwitcherState.shared.dismiss()

        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // 1. Capture screen contents & window hierarchy immediately to freeze the frame
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let screenNumber = targetScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                guard let display = content.displays.first(where: { $0.displayID == screenNumber }) ?? content.displays.first else {
                    self.cleanup()
                    return
                }

                let scale = targetScreen.backingScaleFactor
                let config = SCStreamConfiguration()
                config.width = max(1, Int(targetScreen.frame.width * scale))
                config.height = max(1, Int(targetScreen.frame.height * scale))
                config.scalesToFit = false
                config.showsCursor = false

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let frozenCGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                // 2. Discover visible windows on this screen (excluding our own app)
                let currentPid = ProcessInfo.processInfo.processIdentifier
                let primaryHeight = NSScreen.screens[0].frame.height

                var displayWindows: [(window: SCWindow, viewRect: NSRect)] = []
                for win in content.windows {
                    guard win.isOnScreen,
                          win.frame.width >= 100,
                          win.frame.height >= 80,
                          win.owningApplication?.processID != currentPid,
                          !(win.owningApplication?.bundleIdentifier.lowercased().contains("windowswitcher") ?? false)
                    else { continue }

                    // Convert Quartz (top-left) to Cocoa (bottom-left) coordinates
                    let cocoaX = win.frame.origin.x
                    let cocoaY = primaryHeight - (win.frame.origin.y + win.frame.size.height)
                    let cocoaRect = NSRect(x: cocoaX, y: cocoaY, width: win.frame.width, height: win.frame.height)

                    if targetScreen.frame.intersects(cocoaRect) {
                        // Position relative to targetScreen view origin
                        let viewRect = NSRect(
                            x: cocoaRect.origin.x - targetScreen.frame.origin.x,
                            y: cocoaRect.origin.y - targetScreen.frame.origin.y,
                            width: cocoaRect.width,
                            height: cocoaRect.height
                        )
                        displayWindows.append((win, viewRect))
                    }
                }

                // 3. Present the Freeze-Frame Selection Panel
                let panel = ScreenshotSelectionPanel(
                    screen: targetScreen,
                    frozenImage: frozenCGImage,
                    windows: displayWindows,
                    scale: scale
                )
                self.currentPanel = panel

                // Callback: User dragged a custom area
                panel.areaSelectedCallback = { [weak self] selRect in
                    self?.handleAreaSelected(rect: selRect, on: targetScreen, frozenImage: frozenCGImage, scale: scale)
                }

                // Callback: User clicked a window
                panel.windowSelectedCallback = { [weak self] selectedWindow, windowRect in
                    self?.handleWindowSelected(window: selectedWindow, rect: windowRect, on: targetScreen, scale: scale, frozenImage: frozenCGImage)
                }

                panel.cancelCallback = { [weak self] in
                    self?.cleanup()
                }

                panel.orderFrontRegardless()
                panel.makeKey()
            } catch {
                print("⚠️ Freeze capture setup error: \(error)")
                self.cleanup()
                ToastHUDController.shared.showSimpleToast(message: "Screenshot failed to freeze screen", icon: "exclamationmark.triangle")
            }
        }
    }

    /// Captures the active / frontmost window with full Apple drop shadow.
    public func captureActiveWindow() {
        startAreaCapture()
    }

    // MARK: - Area Drag Selection Completed
    private func handleAreaSelected(rect: NSRect, on screen: NSScreen, frozenImage: CGImage, scale: CGFloat) {
        cleanup()

        guard rect.width >= 4 && rect.height >= 4 else { return }

        // Fast in-memory cropping from frozen image
        let screenBounds = screen.frame
        let relX = rect.origin.x - screenBounds.origin.x
        // Flip Y for CGImage coordinates (where Y=0 is top)
        let relY = screenBounds.height - (rect.origin.y - screenBounds.origin.y + rect.height)

        let cropRect = CGRect(
            x: max(0, relX * scale),
            y: max(0, relY * scale),
            width: rect.width * scale,
            height: rect.height * scale
        )

        guard let cropped = frozenImage.cropping(to: cropRect) else {
            ToastHUDController.shared.showSimpleToast(message: "Failed to crop selection", icon: "xmark.circle", on: screen)
            return
        }

        playCaptureSound()
        copyToClipboard(image: cropped)

        let nsImage = NSImage(cgImage: cropped, size: rect.size)

        if SettingsManager.shared.autoOpenEditor {
            ScreenshotEditorWindowController.shared.show(image: nsImage, sourceRect: rect, on: screen)
        } else {
            ToastHUDController.shared.showSimpleToast(message: "Area screenshot copied to clipboard", icon: "camera.viewfinder", on: screen)
        }
    }

    // MARK: - Window Clicked: Render with Authentic Apple Drop Shadow
    private func handleWindowSelected(window: SCWindow, rect: NSRect, on screen: NSScreen, scale: CGFloat, frozenImage: CGImage) {
        cleanup()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // 1. Capture isolated window contents via ScreenCaptureKit filter
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.sourceRect = CGRect(origin: .zero, size: window.frame.size)
                config.width = max(1, Int(window.frame.size.width * scale))
                config.height = max(1, Int(window.frame.size.height * scale))
                config.showsCursor = false

                let windowCGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)

                // 2. Render onto transparent padded canvas with authentic Apple multi-layer drop shadow
                let shadowedImage = Self.renderAppleWindowWithDropShadow(
                    windowImage: windowCGImage,
                    windowSize: window.frame.size,
                    scale: scale
                )

                playCaptureSound()
                if let tiff = shadowedImage.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
                    let pboard = NSPasteboard.general
                    pboard.clearContents()
                    pboard.setData(png, forType: .png)
                }

                if SettingsManager.shared.autoOpenEditor {
                    ScreenshotEditorWindowController.shared.show(image: shadowedImage, sourceRect: rect, on: screen)
                } else {
                    let appName = window.owningApplication?.applicationName ?? "Window"
                    ToastHUDController.shared.showSimpleToast(message: "\(appName) captured with shadow", icon: "macwindow.badge.plus", on: screen)
                }
            } catch {
                print("⚠️ Window capture with shadow error: \(error)")
                // Fallback: Crop from frozen image
                self.handleAreaSelected(rect: rect, on: screen, frozenImage: frozenImage, scale: scale)
            }
        }
    }

    // MARK: - Apple Window Drop Shadow Engine
    public static func renderAppleWindowWithDropShadow(windowImage: CGImage, windowSize: CGSize, scale: CGFloat) -> NSImage {
        let padding: CGFloat = 50.0 // Shadow padding around window
        let canvasWidth = windowSize.width + padding * 2
        let canvasHeight = windowSize.height + padding * 2
        let pixelW = max(1, Int(canvasWidth * scale))
        let pixelH = max(1, Int(canvasHeight * scale))

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return NSImage(cgImage: windowImage, size: windowSize)
        }

        ctx.scaleBy(x: scale, y: scale)

        let windowRect = CGRect(x: padding, y: padding, width: windowSize.width, height: windowSize.height)
        let cornerRadius: CGFloat = 10.0
        let roundedPath = CGPath(roundedRect: windowRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)

        // Layer 1: Soft Ambient Outer Shadow (Blur 36px, Y -14px, 28% Opacity)
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 36,
            color: NSColor.black.withAlphaComponent(0.28).cgColor
        )
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(roundedPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Layer 2: Directional Contact Shadow (Blur 10px, Y -4px, 22% Opacity)
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: 10,
            color: NSColor.black.withAlphaComponent(0.22).cgColor
        )
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(roundedPath)
        ctx.fillPath()
        ctx.restoreGState()

        // Draw the window image clipped to rounded corners
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.clip()
        ctx.draw(windowImage, in: windowRect)
        ctx.restoreGState()

        // Apple Hairline Border (1px, 12% opacity)
        ctx.saveGState()
        ctx.addPath(roundedPath)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.12).cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokePath()
        ctx.restoreGState()

        guard let resultCG = ctx.makeImage() else {
            return NSImage(cgImage: windowImage, size: windowSize)
        }

        return NSImage(cgImage: resultCG, size: CGSize(width: canvasWidth, height: canvasHeight))
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
    var areaSelectedCallback: ((NSRect) -> Void)?
    var windowSelectedCallback: ((SCWindow, NSRect) -> Void)?
    var cancelCallback: (() -> Void)?

    init(screen: NSScreen, frozenImage: CGImage, windows: [(window: SCWindow, viewRect: NSRect)], scale: CGFloat) {
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

        let overlayView = ScreenshotSelectionOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            frozenImage: frozenImage,
            windows: windows,
            scale: scale
        )
        overlayView.onAreaComplete = { [weak self] rect in
            self?.areaSelectedCallback?(rect)
        }
        overlayView.onWindowComplete = { [weak self] win, rect in
            self?.windowSelectedCallback?(win, rect)
        }
        overlayView.onCancel = { [weak self] in
            self?.cancelCallback?()
        }
        self.contentView = overlayView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Freeze-Frame Canvas with Dual-Mode (Area Drag + Window Hover/Click)
private class ScreenshotSelectionOverlayView: NSView {
    var onAreaComplete: ((NSRect) -> Void)?
    var onWindowComplete: ((SCWindow, NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private let frozenImage: CGImage
    private let frozenNSImage: NSImage
    private let windows: [(window: SCWindow, viewRect: NSRect)]
    private let scale: CGFloat

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var isDragging: Bool = false
    private var hoveredWindowItem: (window: SCWindow, viewRect: NSRect)?
    private var trackingAreaRef: NSTrackingArea?

    init(frame: NSRect, frozenImage: CGImage, windows: [(window: SCWindow, viewRect: NSRect)], scale: CGFloat) {
        self.frozenImage = frozenImage
        self.frozenNSImage = NSImage(cgImage: frozenImage, size: frame.size)
        self.windows = windows
        self.scale = scale
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
        if hoveredWindowItem != nil && !isDragging {
            NSCursor.pointingHand.set()
        } else {
            NSCursor.crosshair.set()
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        currentPoint = loc

        if !isDragging {
            hoveredWindowItem = windows.first { $0.viewRect.contains(loc) }
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        startPoint = loc
        currentPoint = loc
        isDragging = false
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        currentPoint = loc
        if let s = startPoint {
            let dx = abs(loc.x - s.x)
            let dy = abs(loc.y - s.y)
            if dx > 4 || dy > 4 {
                isDragging = true
                hoveredWindowItem = nil
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let s = startPoint, let c = currentPoint else {
            onCancel?()
            return
        }

        if isDragging {
            let selRect = normalizedRect(from: s, to: c)
            if selRect.width > 4 && selRect.height > 4 {
                let screenOrigin = window?.frame.origin ?? .zero
                let absoluteRect = NSRect(
                    x: screenOrigin.x + selRect.origin.x,
                    y: screenOrigin.y + selRect.origin.y,
                    width: selRect.width,
                    height: selRect.height
                )
                onAreaComplete?(absoluteRect)
                return
            }
        } else if let (win, viewRect) = hoveredWindowItem {
            // Clicked a window without dragging -> Capture window with Apple drop shadow!
            let screenOrigin = window?.frame.origin ?? .zero
            let absoluteRect = NSRect(
                x: screenOrigin.x + viewRect.origin.x,
                y: screenOrigin.y + viewRect.origin.y,
                width: viewRect.width,
                height: viewRect.height
            )
            onWindowComplete?(win, absoluteRect)
            return
        }

        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw the Frozen Frame across entire screen (Freezes video & dynamic UI instantly!)
        frozenNSImage.draw(in: bounds)

        // 2. Render Overlay State
        if isDragging, let s = startPoint, let c = currentPoint, s != c {
            // Drag Area Selection Mode
            let sel = normalizedRect(from: s, to: c)

            // Dim outside selection
            context.setFillColor(NSColor.black.withAlphaComponent(0.35).cgColor)
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(rect: sel).reversed)
            outside.fill()

            // Accent border around selection
            let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.95)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(1.5)
            context.stroke(sel)

            // Dimension Badge: W × H pt
            let badgeText = "\(Int(sel.width)) × \(Int(sel.height)) pt" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let textSize = badgeText.size(withAttributes: attrs)
            let badgeRect = NSRect(
                x: min(max(sel.midX - (textSize.width + 16)/2, 8), bounds.width - textSize.width - 24),
                y: sel.minY >= 30 ? sel.minY - 26 : sel.maxY + 8,
                width: textSize.width + 16,
                height: 20
            )

            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
            NSColor.black.withAlphaComponent(0.85).setFill()
            badgePath.fill()
            badgeText.draw(at: NSPoint(x: badgeRect.origin.x + 8, y: badgeRect.origin.y + 3), withAttributes: attrs)

            // Crosshair Guides
            drawCrosshairs(at: c, in: context)

        } else if let (win, viewRect) = hoveredWindowItem {
            // Window Hover Mode: Highlight the window under cursor
            // Dim outside window
            context.setFillColor(NSColor.black.withAlphaComponent(0.20).cgColor)
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(roundedRect: viewRect, xRadius: 10, yRadius: 10).reversed)
            outside.fill()

            // Cobalt Azure Tint and Stroke
            let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.95)
            context.setFillColor(NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.08).cgColor)
            let winPath = NSBezierPath(roundedRect: viewRect, xRadius: 10, yRadius: 10)
            winPath.fill()

            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(2.5)
            winPath.stroke()

            // Window Information Pill Badge
            let appName = win.owningApplication?.applicationName ?? "Window"
            let badgeText = "📸 \(appName) • Click to capture window with shadow" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .semibold),
                .foregroundColor: NSColor.white
            ]
            let textSize = badgeText.size(withAttributes: attrs)
            let badgeRect = NSRect(
                x: max(viewRect.midX - (textSize.width + 24) / 2, 12),
                y: viewRect.maxY >= 36 ? viewRect.maxY - 32 : viewRect.minY + 12,
                width: textSize.width + 24,
                height: 24
            )

            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.88).setFill()
            badgePath.fill()
            accent.setStroke()
            badgePath.lineWidth = 1.0
            badgePath.stroke()

            badgeText.draw(at: NSPoint(x: badgeRect.origin.x + 12, y: badgeRect.origin.y + 4.5), withAttributes: attrs)

            if let c = currentPoint {
                drawCrosshairs(at: c, in: context)
            }
        } else {
            // Idle State: Light Dim & Crosshairs
            context.setFillColor(NSColor.black.withAlphaComponent(0.22).cgColor)
            context.fill(bounds)

            if let c = currentPoint {
                drawCrosshairs(at: c, in: context)
            }
        }
    }

    private func drawCrosshairs(at pt: NSPoint, in context: CGContext) {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        context.setLineWidth(0.8)
        context.strokeLineSegments(between: [
            CGPoint(x: 0, y: pt.y), CGPoint(x: bounds.width, y: pt.y),
            CGPoint(x: pt.x, y: 0), CGPoint(x: pt.x, y: bounds.height)
        ])
    }

    private func normalizedRect(from p1: NSPoint, to p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let w = abs(p1.x - p2.x)
        let h = abs(p1.y - p2.y)
        return NSRect(x: x, y: y, width: w, height: h)
    }
}
