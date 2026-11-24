import AppKit
import SwiftUI
import ScreenCaptureKit
import Vision

@MainActor
public class ScreenOCRCoordinator: NSObject {
    public static let shared = ScreenOCRCoordinator()

    private var currentPanel: OCRSelectionPanel?
    private var isCapturing: Bool = false

    private override init() {
        super.init()
    }

    public func startSelection() {
        guard !isCapturing else { return }
        isCapturing = true

        // Dismiss window switcher if it happens to be open
        SwitcherState.shared.dismiss()

        // Detect the active screen where the user is currently working (based on cursor position)
        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first { NSMouseInRect(mouseLoc, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]

        let panel = OCRSelectionPanel(screen: targetScreen)
        self.currentPanel = panel

        panel.selectionCallback = { [weak self] selectedRect in
            self?.handleSelectionCompleted(rect: selectedRect, on: targetScreen)
        }

        panel.cancelCallback = { [weak self] in
            self?.cleanup()
        }

        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func handleSelectionCompleted(rect: NSRect, on screen: NSScreen) {
        cleanup()

        Task {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

                // Match display corresponding to this screen
                let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                guard let display = content.displays.first(where: { $0.displayID == screenNumber }) ?? content.displays.first else {
                    ToastHUDController.shared.showToast(message: "Could not access display", icon: "exclamationmark.triangle", on: screen)
                    return
                }

                // Coordinate conversion: Cocoa (bottom-left) -> ScreenCaptureKit (top-left)
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

                // Run Apple Vision OCR
                TextRecognitionService.shared.recognizeAndCopyText(from: capturedImage) { result in
                    if let result = result {
                        NSSound.beep()
                        ToastHUDController.shared.showToast(message: result.summary, icon: "checkmark.circle.fill", on: screen)
                    } else {
                        ToastHUDController.shared.showToast(message: "No text found in selection", icon: "doc.text.magnifyingglass", on: screen)
                    }
                }
            } catch {
                print("⚠️ OCR capture failed: \(error)")
                ToastHUDController.shared.showToast(message: "Capture failed", icon: "xmark.circle", on: screen)
            }
        }
    }

    private func cleanup() {
        currentPanel?.orderOut(nil)
        currentPanel = nil
        isCapturing = false
    }
}

// MARK: - Fullscreen Translucent Selection Panel
private class OCRSelectionPanel: NSPanel {
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

        let view = OCRSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), screenFrame: screen.frame)
        view.onComplete = { [weak self] rect in
            self?.selectionCallback?(rect)
        }
        view.onCancel = { [weak self] in
            self?.cancelCallback?()
        }
        self.contentView = view
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Interactive Selection Canvas View
private class OCRSelectionView: NSView {
    var onComplete: ((NSRect) -> Void)?
    var onCancel: (() -> Void)?

    private let screenFrame: NSRect
    private var startPoint: NSPoint = .zero
    private var currentRect: NSRect = .zero
    private var isDragging: Bool = false

    init(frame: NSRect, screenFrame: NSRect) {
        self.screenFrame = screenFrame
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Dark semi-translucent scrim over the active screen
        NSColor.black.withAlphaComponent(0.24).setFill()
        dirtyRect.fill()

        // 2. Clear out and highlight selection rectangle
        if isDragging && currentRect.width > 2 && currentRect.height > 2 {
            // Cut hole in scrim
            context.saveGState()
            context.setBlendMode(.clear)
            NSColor.black.setFill()
            currentRect.fill()
            context.restoreGState()

            // Soft accent tint inside selection
            let accentHex = SettingsManager.shared.customAccentColorHex
            let accent = NSColor(Color(hex: accentHex) ?? Color.blue)
            accent.withAlphaComponent(0.08).setFill()
            currentRect.fill()

            // Crisp 1.5px accent border
            accent.setStroke()
            let path = NSBezierPath(rect: currentRect)
            path.lineWidth = 1.5
            path.stroke()

            // Draw dimension badge
            drawDimensionBadge(for: currentRect)
        }
    }

    private func drawDimensionBadge(for rect: NSRect) {
        let text = "\(Int(rect.width)) × \(Int(rect.height)) px"
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let badgeW = size.width + 16
        let badgeH: CGFloat = 22

        // Position badge below selection or above if near screen bottom
        var badgeY = rect.origin.y - badgeH - 6
        if badgeY < 10 {
            badgeY = rect.origin.y + rect.height + 6
        }
        let badgeX = max(10, min(rect.origin.x + (rect.width - badgeW) / 2, bounds.width - badgeW - 10))
        let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)

        // Pill background
        let pillPath = NSBezierPath(roundedRect: badgeRect, xRadius: 5, yRadius: 5)
        NSColor.black.withAlphaComponent(0.75).setFill()
        pillPath.fill()

        NSColor.white.withAlphaComponent(0.25).setStroke()
        pillPath.lineWidth = 0.8
        pillPath.stroke()

        let textRect = NSRect(
            x: badgeRect.origin.x + 8,
            y: badgeRect.origin.y + (badgeH - size.height) / 2,
            width: size.width,
            height: size.height
        )
        (text as NSString).draw(in: textRect, withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentRect = .zero
        isDragging = true
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDragging else { return }
        let currentPoint = convert(event.locationInWindow, from: nil)

        currentRect = NSRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard isDragging else { return }
        isDragging = false

        if currentRect.width > 6 && currentRect.height > 6 {
            // Convert local view rect to global screen coordinates
            let globalRect = NSRect(
                x: screenFrame.origin.x + currentRect.origin.x,
                y: screenFrame.origin.y + currentRect.origin.y,
                width: currentRect.width,
                height: currentRect.height
            )
            onComplete?(globalRect)
        } else {
            onCancel?()
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}
