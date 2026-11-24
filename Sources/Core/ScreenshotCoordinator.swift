import AppKit
import SwiftUI
import ScreenCaptureKit

@MainActor
public class ScreenshotCoordinator: NSObject {
    public static let shared = ScreenshotCoordinator()

    private var currentPanel: ScreenshotSelectionPanel?
    private var isCapturing: Bool = false
    private var windowSnapshotTasks: [CGWindowID: Task<CGImage?, Never>] = [:]
    private var localEscMonitor: Any?
    private var globalEscMonitor: Any?

    private let excludedSystemBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.Spotlight",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.loginwindow",
        "com.apple.wallpaper.agent"
    ]

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
                // 1. Capture authoritative Quartz window Z-order & visibility BEFORE freezing screen
                let cgWindowInfo = Self.queryVisibleLayer0WindowsZOrder()

                // 2. Capture full display frame immediately to freeze videos & dynamic UI
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
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
                config.capturesAudio = false

                let filter = SCContentFilter(display: display, excludingWindows: [])
                let frozenCGImage = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                if let fSample = Self.sampleCenterPixel(of: frozenCGImage) {
                    print("📸 Freeze captured: \(frozenCGImage.width)x\(frozenCGImage.height), centerPixel=\(fSample)")
                }

                // 3. Filter and sort visible application windows on targetScreen in exact Z-order
                let currentPid = ProcessInfo.processInfo.processIdentifier
                let primaryHeight = NSScreen.screens[0].frame.height

                var candidateEntries: [(rank: Int, window: SCWindow, viewRect: NSRect)] = []
                for win in content.windows {
                    // Strictly require normal layer-0 visible windows present in CGWindowList with alpha > 0.05
                    guard win.windowLayer == 0,
                          win.isOnScreen,
                          let rank = cgWindowInfo[win.windowID]
                    else { continue }

                    let bid = win.owningApplication?.bundleIdentifier ?? ""
                    if self.excludedSystemBundleIDs.contains(bid) { continue }

                    // Exclude our own hidden/untitled overlay panels, while still permitting Preferences if visible
                    if win.owningApplication?.processID == currentPid || bid.lowercased().contains("windowswitcher") {
                        let title = (win.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                        if title.isEmpty { continue }
                    }

                    // Convert Quartz (top-left of primary display) to Cocoa (bottom-left of primary display)
                    let cocoaX = win.frame.origin.x
                    let cocoaY = primaryHeight - (win.frame.origin.y + win.frame.size.height)
                    let cocoaRect = NSRect(x: cocoaX, y: cocoaY, width: win.frame.width, height: win.frame.height)

                    // Position relative to targetScreen view coordinates
                    let viewRect = NSRect(
                        x: cocoaRect.origin.x - targetScreen.frame.origin.x,
                        y: cocoaRect.origin.y - targetScreen.frame.origin.y,
                        width: cocoaRect.width,
                        height: cocoaRect.height
                    )

                    // Ensure a meaningful portion of the window is actually visible on this display
                    let visibleIntersection = viewRect.intersection(NSRect(origin: .zero, size: targetScreen.frame.size))
                    guard !visibleIntersection.isNull,
                          visibleIntersection.width >= 50,
                          visibleIntersection.height >= 50
                    else { continue }

                    candidateEntries.append((rank, win, viewRect))
                }

                // Sort strictly front-to-back matching screen stacking order
                candidateEntries.sort { $0.rank < $1.rank }
                let displayWindows: [(window: SCWindow, viewRect: NSRect)] = candidateEntries.map { ($0.window, $0.viewRect) }
                print("🪟 Discovered \(displayWindows.count) layer-0 windows:")
                for item in displayWindows.prefix(6) {
                    print("   • wid=\(item.window.windowID) app=\(item.window.owningApplication?.applicationName ?? "?") viewRect=\(item.viewRect)")
                }

                // 4. Pre-capture isolated window images at freeze timestamp T0 (so playing video stays frozen inside windows too)
                self.windowSnapshotTasks.removeAll()
                for entry in displayWindows.prefix(8) {
                    let win = entry.window
                    self.windowSnapshotTasks[win.windowID] = Task {
                        await Self.captureIsolatedWindowCGImage(window: win, scale: scale)
                    }
                }

                // 5. Present the Freeze-Frame Selection Panel immediately
                let initialMouseInView = NSPoint(
                    x: mouseLoc.x - targetScreen.frame.origin.x,
                    y: mouseLoc.y - targetScreen.frame.origin.y
                )
                let panel = ScreenshotSelectionPanel(
                    screen: targetScreen,
                    frozenImage: frozenCGImage,
                    windows: displayWindows,
                    initialMousePoint: initialMouseInView,
                    scale: scale
                )
                self.currentPanel = panel

                panel.areaSelectedCallback = { [weak self] selRect in
                    self?.handleAreaSelected(rect: selRect, on: targetScreen, frozenImage: frozenCGImage, scale: scale)
                }

                panel.windowSelectedCallback = { [weak self] selectedWindow, windowRect in
                    self?.handleWindowSelected(window: selectedWindow, rect: windowRect, on: targetScreen, scale: scale, frozenImage: frozenCGImage)
                }

                panel.cancelCallback = { [weak self] in
                    self?.cleanup()
                }

                panel.orderFrontRegardless()
                panel.makeKey()
                if let contentView = panel.contentView {
                    panel.makeFirstResponder(contentView)
                }
                self.installEscapeMonitors()
            } catch {
                print("⚠️ Freeze capture setup error: \(error)")
                self.cleanup()
                ToastHUDController.shared.showSimpleToast(message: "Screenshot failed to freeze screen", icon: "exclamationmark.triangle")
            }
        }
    }

    /// Triggers unified capture mode (both area drag and window click).
    public func captureActiveWindow() {
        startAreaCapture()
    }

    /// Simulates clicking the hovered window on the active overlay (for automated end-to-end verification).
    public func simulateWindowClickForTesting() {
        (currentPanel?.contentView as? ScreenshotSelectionOverlayView)?.triggerTopWindowClickForTesting()
    }

    private func installEscapeMonitors() {
        removeEscapeMonitors()
        localEscMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self?.cleanup() }
                return nil
            }
            return event
        }
        globalEscMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {
                DispatchQueue.main.async { self?.cleanup() }
            }
        }
    }

    private func removeEscapeMonitors() {
        if let local = localEscMonitor {
            NSEvent.removeMonitor(local)
            localEscMonitor = nil
        }
        if let global = globalEscMonitor {
            NSEvent.removeMonitor(global)
            globalEscMonitor = nil
        }
    }

    // MARK: - Window Filtering & Snapshot Helpers
    private static func queryVisibleLayer0WindowsZOrder() -> [CGWindowID: Int] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        var zOrder: [CGWindowID: Int] = [:]
        for (index, dict) in infoList.enumerated() {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let wid = dict[kCGWindowNumber as String] as? CGWindowID
            else { continue }

            let alpha = dict[kCGWindowAlpha as String] as? Double ?? 1.0
            guard alpha > 0.05 else { continue }

            zOrder[wid] = index
        }
        return zOrder
    }

    private static func captureIsolatedWindowCGImage(window: SCWindow, scale: CGFloat) async -> CGImage? {
        guard window.frame.width >= 4 && window.frame.height >= 4 else { return nil }
        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            // Omit sourceRect so ScreenCaptureKit captures the full desktop-independent window bounds cleanly
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))
            config.scalesToFit = true
            config.showsCursor = false
            config.capturesAudio = false

            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let sample = Self.sampleCenterPixel(of: image) ?? "nil"
            guard hasVisiblePixels(image) else {
                print("⚠️ Window \(window.windowID) (\(window.owningApplication?.applicationName ?? "?")) had no visible pixels (center=\(sample))")
                return nil
            }
            print("✅ Isolated capture OK for wid=\(window.windowID) (\(window.owningApplication?.applicationName ?? "?")): \(image.width)x\(image.height), center=\(sample)")
            return image
        } catch {
            print("⚠️ Isolated window capture failed for \(window.owningApplication?.applicationName ?? "window"): \(error)")
            return nil
        }
    }

    private static func sampleCenterPixel(of image: CGImage) -> String? {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let c = rep.colorAt(x: image.width / 2, y: image.height / 2) else { return nil }
        return String(format: "(R:%.2f G:%.2f B:%.2f A:%.2f)", c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
    }

    /// Checks a sparse grid of sample pixels so empty transparent helper windows never slip through.
    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 4 && h > 4 else { return false }

        let steps = 5
        for iy in 1..<steps {
            for ix in 1..<steps {
                let x = (w * ix) / steps
                let y = (h * iy) / steps
                if let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.02 {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Area Drag Selection Completed
    private func handleAreaSelected(rect: NSRect, on screen: NSScreen, frozenImage: CGImage, scale: CGFloat) {
        cleanup()

        guard rect.width >= 4 && rect.height >= 4 else { return }

        guard let cropped = cropFromFrozenImage(rect: rect, on: screen, frozenImage: frozenImage, scale: scale) else {
            ToastHUDController.shared.showSimpleToast(message: "Failed to crop selection", icon: "xmark.circle", on: screen)
            return
        }

        playCaptureSound()
        copyToClipboard(cgImage: cropped)

        let nsImage = NSImage(cgImage: cropped, size: rect.size)

        if SettingsManager.shared.autoOpenEditor {
            ScreenshotEditorWindowController.shared.show(image: nsImage, sourceRect: rect, on: screen)
        } else {
            ToastHUDController.shared.showSimpleToast(message: "Area screenshot copied to clipboard", icon: "camera.viewfinder", on: screen)
        }
    }

    private func cropFromFrozenImage(rect: NSRect, on screen: NSScreen, frozenImage: CGImage, scale: CGFloat) -> CGImage? {
        let screenBounds = screen.frame
        let relX = rect.origin.x - screenBounds.origin.x
        let relY = screenBounds.height - (rect.origin.y - screenBounds.origin.y + rect.height)

        let rawCrop = CGRect(
            x: relX * scale,
            y: relY * scale,
            width: rect.width * scale,
            height: rect.height * scale
        )
        let imageBounds = CGRect(x: 0, y: 0, width: frozenImage.width, height: frozenImage.height)
        let clampedCrop = rawCrop.intersection(imageBounds)
        guard !clampedCrop.isNull && clampedCrop.width >= 2 && clampedCrop.height >= 2 else {
            return nil
        }
        return frozenImage.cropping(to: clampedCrop)
    }

    // MARK: - Window Clicked: Render with Authentic Apple Drop Shadow
    private func handleWindowSelected(window: SCWindow, rect: NSRect, on screen: NSScreen, scale: CGFloat, frozenImage: CGImage) {
        let snapshotTask = windowSnapshotTasks[window.windowID]
        cleanup()

        Task { @MainActor [weak self] in
            guard let self else { return }

            // 1. Prefer exact frozen T0 window snapshot, fallback to fresh capture or frozen screen crop
            var resolvedWindowCG: CGImage?
            if let task = snapshotTask {
                resolvedWindowCG = await task.value
            }
            if resolvedWindowCG == nil {
                resolvedWindowCG = await Self.captureIsolatedWindowCGImage(window: window, scale: scale)
            }

            let appName = window.owningApplication?.applicationName ?? "Window"
            print("🖱️ handleWindowSelected: wid=\(window.windowID) app=\(appName) resolvedCG=\(resolvedWindowCG != nil)")
            if let windowCGImage = resolvedWindowCG {
                // Render onto padded transparent canvas using window's true alpha silhouette for Apple drop shadow
                let rendered = Self.renderAppleWindowWithDropShadow(
                    windowImage: windowCGImage,
                    windowSize: window.frame.size,
                    scale: scale
                )
                print("🎨 Rendered shadowed window: size=\(rendered.nsImage.size), center=\(Self.sampleCenterPixel(of: rendered.cgImage) ?? "nil")")
                self.presentCapturedWindowResult(rendered, appName: appName, sourceRect: rect, on: screen)
            } else if let croppedFallback = self.cropFromFrozenImage(rect: rect, on: screen, frozenImage: frozenImage, scale: scale) {
                print("📦 Using frozen fallback crop: \(croppedFallback.width)x\(croppedFallback.height), center=\(Self.sampleCenterPixel(of: croppedFallback) ?? "nil")")
                // Fallback for edge-case windows that block independent capture
                let clippedSize = NSSize(width: CGFloat(croppedFallback.width) / scale, height: CGFloat(croppedFallback.height) / scale)
                let roundedMaskImage = Self.applyCornerMaskIfNeeded(to: croppedFallback, size: clippedSize, scale: scale) ?? croppedFallback
                let rendered = Self.renderAppleWindowWithDropShadow(
                    windowImage: roundedMaskImage,
                    windowSize: clippedSize,
                    scale: scale
                )
                print("🎨 Rendered fallback shadowed: size=\(rendered.nsImage.size), center=\(Self.sampleCenterPixel(of: rendered.cgImage) ?? "nil")")
                self.presentCapturedWindowResult(rendered, appName: appName, sourceRect: rect, on: screen)
            } else {
                ToastHUDController.shared.showSimpleToast(message: "Window capture failed", icon: "xmark.circle", on: screen)
            }
        }
    }

    private func presentCapturedWindowResult(_ rendered: (nsImage: NSImage, cgImage: CGImage), appName: String, sourceRect: NSRect, on screen: NSScreen) {
        playCaptureSound()
        copyToClipboard(cgImage: rendered.cgImage)

        if SettingsManager.shared.autoOpenEditor {
            ScreenshotEditorWindowController.shared.show(image: rendered.nsImage, sourceRect: sourceRect, hasEmbeddedShadow: true, on: screen)
        } else {
            ToastHUDController.shared.showSimpleToast(message: "\(appName) captured with shadow", icon: "macwindow.badge.plus", on: screen)
        }
    }

    private static func applyCornerMaskIfNeeded(to cgImage: CGImage, size: CGSize, scale: CGFloat) -> CGImage? {
        let pixelW = cgImage.width
        let pixelH = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        let rect = CGRect(origin: .zero, size: size)
        let path = CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(path)
        ctx.clip()
        ctx.draw(cgImage, in: rect)
        return ctx.makeImage()
    }

    // MARK: - Apple Window Drop Shadow Engine
    public static func renderAppleWindowWithDropShadow(windowImage: CGImage, windowSize: CGSize, scale: CGFloat) -> (nsImage: NSImage, cgImage: CGImage) {
        let padding: CGFloat = 50.0
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
            return (NSImage(cgImage: windowImage, size: windowSize), windowImage)
        }

        ctx.scaleBy(x: scale, y: scale)

        let windowRect = CGRect(x: padding, y: padding, width: windowSize.width, height: windowSize.height)

        // Layer 1: Soft Ambient Outer Shadow (Blur 36px, Y -14px, 28% Opacity) cast from true window alpha silhouette
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -14),
            blur: 36,
            color: NSColor.black.withAlphaComponent(0.28).cgColor
        )
        ctx.draw(windowImage, in: windowRect)
        ctx.restoreGState()

        // Layer 2: Tight Directional Contact Shadow (Blur 10px, Y -4px, 20% Opacity)
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -4),
            blur: 10,
            color: NSColor.black.withAlphaComponent(0.20).cgColor
        )
        ctx.draw(windowImage, in: windowRect)
        ctx.restoreGState()

        // Erase only the interior footprint via destinationOut so anti-aliased edges and translucent areas never double-blend,
        // while keeping 100% of the outer drop shadow intact without any solid black backdrop box
        ctx.saveGState()
        ctx.setBlendMode(.destinationOut)
        ctx.draw(windowImage, in: windowRect)
        ctx.restoreGState()

        // Composite crisp window content cleanly on top
        ctx.saveGState()
        ctx.draw(windowImage, in: windowRect)
        ctx.restoreGState()

        guard let resultCG = ctx.makeImage() else {
            return (NSImage(cgImage: windowImage, size: windowSize), windowImage)
        }

        return (NSImage(cgImage: resultCG, size: CGSize(width: canvasWidth, height: canvasHeight)), resultCG)
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

    private func copyToClipboard(cgImage: CGImage) {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        if let pngData = rep.representation(using: .png, properties: [:]) {
            let pboard = NSPasteboard.general
            pboard.clearContents()
            pboard.setData(pngData, forType: .png)
            if let tiffData = rep.tiffRepresentation {
                pboard.setData(tiffData, forType: .tiff)
            }
        }
    }

    private func cleanup() {
        removeEscapeMonitors()
        for task in windowSnapshotTasks.values {
            task.cancel()
        }
        windowSnapshotTasks.removeAll()
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

    init(screen: NSScreen, frozenImage: CGImage, windows: [(window: SCWindow, viewRect: NSRect)], initialMousePoint: NSPoint, scale: CGFloat) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.level = .screenSaver
        self.becomesKeyOnlyIfNeeded = false
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true

        let overlayView = ScreenshotSelectionOverlayView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            frozenImage: frozenImage,
            windows: windows,
            initialMousePoint: initialMousePoint,
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

    init(frame: NSRect, frozenImage: CGImage, windows: [(window: SCWindow, viewRect: NSRect)], initialMousePoint: NSPoint, scale: CGFloat) {
        self.frozenImage = frozenImage
        self.frozenNSImage = NSImage(cgImage: frozenImage, size: frame.size)
        self.windows = windows
        self.scale = scale
        self.currentPoint = initialMousePoint
        self.hoveredWindowItem = windows.first { $0.viewRect.contains(initialMousePoint) }
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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
            window?.invalidateCursorRects(for: self)
            if hoveredWindowItem != nil {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.crosshair.set()
            }
        }
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        startPoint = loc
        currentPoint = loc
        isDragging = false
        if hoveredWindowItem == nil {
            hoveredWindowItem = windows.first { $0.viewRect.contains(loc) }
        }
        print("🖱️ Overlay mouseDown at \(loc), hovered=\(hoveredWindowItem?.window.owningApplication?.applicationName ?? "nil")")
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
                NSCursor.crosshair.set()
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let releasePoint = convert(event.locationInWindow, from: nil)
        guard let s = startPoint else {
            onCancel?()
            return
        }

        if isDragging {
            let selRect = normalizedRect(from: s, to: releasePoint)
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
        }

        // Single click without dragging -> Capture the window directly under click point
        if let (win, viewRect) = hoveredWindowItem ?? windows.first(where: { $0.viewRect.contains(releasePoint) }) {
            print("🖱️ Overlay mouseUp -> capturing window wid=\(win.windowID) (\(win.owningApplication?.applicationName ?? "?")) rect=\(viewRect)")
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

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            onCancel?()
        }
    }

    func triggerTopWindowClickForTesting() {
        guard let (win, viewRect) = hoveredWindowItem ?? windows.first else {
            onCancel?()
            return
        }
        let screenOrigin = window?.frame.origin ?? .zero
        let absoluteRect = NSRect(
            x: screenOrigin.x + viewRect.origin.x,
            y: screenOrigin.y + viewRect.origin.y,
            width: viewRect.width,
            height: viewRect.height
        )
        onWindowComplete?(win, absoluteRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw the Frozen Frame across entire screen (Freezes video & dynamic UI instantly!)
        frozenNSImage.draw(in: bounds)

        let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.95)

        // 2. Render Overlay State
        if isDragging, let s = startPoint, let c = currentPoint, s != c {
            let sel = normalizedRect(from: s, to: c)

            // Dim outside selection
            NSColor.black.withAlphaComponent(0.35).setFill()
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(rect: sel).reversed)
            outside.fill()

            // Accent border around selection
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

            drawCrosshairs(at: c, in: context)

        } else if let (win, viewRect) = hoveredWindowItem {
            let clampedRect = viewRect.intersection(bounds)

            // Dim outside window
            NSColor.black.withAlphaComponent(0.22).setFill()
            let outside = NSBezierPath(rect: bounds)
            outside.append(NSBezierPath(roundedRect: clampedRect, xRadius: 10, yRadius: 10).reversed)
            outside.fill()

            // Subtle Cobalt Azure Tint + Border on Hovered Window
            let winPath = NSBezierPath(roundedRect: clampedRect, xRadius: 10, yRadius: 10)
            NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.08).setFill()
            winPath.fill()

            accent.setStroke()
            winPath.lineWidth = 2.0
            winPath.stroke()

            // Clean Window Information Pill Badge (No emoji per design standard)
            let appName = win.owningApplication?.applicationName ?? "Window"
            let badgeText = "\(appName) — Click to capture window" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let textSize = badgeText.size(withAttributes: attrs)
            let badgeW = textSize.width + 24
            let badgeH: CGFloat = 24
            let badgeX = min(max(clampedRect.midX - badgeW / 2, 12), bounds.width - badgeW - 12)
            let badgeY = min(max(clampedRect.maxY - badgeH - 12, 12), bounds.height - badgeH - 44)
            let badgeRect = NSRect(x: badgeX, y: badgeY, width: badgeW, height: badgeH)

            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.86).setFill()
            badgePath.fill()
            accent.withAlphaComponent(0.6).setStroke()
            badgePath.lineWidth = 1.0
            badgePath.stroke()

            badgeText.draw(at: NSPoint(x: badgeRect.origin.x + 12, y: badgeRect.origin.y + 4.5), withAttributes: attrs)

            if let c = currentPoint {
                drawCrosshairs(at: c, in: context)
            }
        } else {
            // Idle State: Light Dim & Crosshairs
            NSColor.black.withAlphaComponent(0.22).setFill()
            NSBezierPath(rect: bounds).fill()

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
