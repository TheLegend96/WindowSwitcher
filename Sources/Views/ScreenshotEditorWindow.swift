import AppKit
import SwiftUI
import CoreImage

// MARK: - Annotation Tool Types
public enum AnnotationTool: String, CaseIterable, Identifiable {
    case pointer = "Pointer"
    case distance = "Dimension"
    case arrow = "Arrow"
    case text = "Text"
    case numberedPin = "Numbered Pin"
    case rectangle = "Rectangle"
    case roundedRect = "Card"
    case pencil = "Highlighter"
    case blur = "Blur"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .pointer: return "arrow.up.left"
        case .distance: return "ruler"
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .numberedPin: return "1.circle"
        case .rectangle: return "rectangle"
        case .roundedRect: return "app"
        case .pencil: return "pencil.tip"
        case .blur: return "circle.lefthalf.filled"
        }
    }

    public var tooltip: String {
        switch self {
        case .pointer: return "Select & Move (V)"
        case .distance: return "Smart Dimension Ruler — Horizontal & Vertical Snapping (D)"
        case .arrow: return "Callout Arrow (A)"
        case .text: return "Text Callout (T) • Double-click note to edit"
        case .numberedPin: return "Numbered QA Pin (N)"
        case .rectangle: return "Component Box (R)"
        case .roundedRect: return "Rounded Card (C)"
        case .pencil: return "Highlighter (P)"
        case .blur: return "Mosaic Redaction Blur (B)"
        }
    }
}

// MARK: - Designer Annotation Color Swatches
public enum DesignerInk: String, CaseIterable, Identifiable {
    case azure = "#0A84FF"
    case coral = "#FF453A"
    case amber = "#FF9F0A"
    case emerald = "#30D158"

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .azure: return "Accent Blue"
        case .coral: return "Error / Bug Red"
        case .amber: return "Warning Amber"
        case .emerald: return "Verified Green"
        }
    }

    public var nsColor: NSColor {
        switch self {
        case .azure: return NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)
        case .coral: return NSColor(red: 255/255, green: 69/255, blue: 58/255, alpha: 1.0)
        case .amber: return NSColor(red: 255/255, green: 159/255, blue: 10/255, alpha: 1.0)
        case .emerald: return NSColor(red: 48/255, green: 209/255, blue: 88/255, alpha: 1.0)
        }
    }

    public var swiftUIColor: Color { Color(nsColor) }
}

// MARK: - Vector Annotation Primitive
public struct CanvasAnnotation: Identifiable, Equatable {
    public let id = UUID()
    public var tool: AnnotationTool
    public var startPoint: CGPoint        // In image point coordinates (0,0 = top-left)
    public var endPoint: CGPoint          // In image point coordinates
    public var pathPoints: [CGPoint] = [] // For freehand pencil
    public var text: String = ""
    public var number: Int = 1
    public var color: NSColor = DesignerInk.azure.nsColor

    public static func == (lhs: CanvasAnnotation, rhs: CanvasAnnotation) -> Bool {
        lhs.id == rhs.id &&
        lhs.startPoint == rhs.startPoint &&
        lhs.endPoint == rhs.endPoint &&
        lhs.text == rhs.text &&
        lhs.number == rhs.number &&
        lhs.pathPoints == rhs.pathPoints
    }
}

// MARK: - Fast sRGB Pixel & UI Edge Inspection Buffer
public final class PixelInspectBuffer {
    public let pixelsWide: Int
    public let pixelsHigh: Int
    public let imagePointSize: CGSize
    private let bytesPerRow: Int
    private let rgba: [UInt8]

    public init?(image: NSImage) {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let w = max(1, cg.width)
        let h = max(1, cg.height)
        let bpr = w * 4
        var buffer = [UInt8](repeating: 0, count: h * bpr)

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &buffer,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: bpr,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        self.pixelsWide = w
        self.pixelsHigh = h
        self.imagePointSize = image.size
        self.bytesPerRow = bpr
        self.rgba = buffer
    }

    private var scaleX: CGFloat {
        imagePointSize.width > 0 ? CGFloat(pixelsWide) / imagePointSize.width : 1.0
    }
    private var scaleY: CGFloat {
        imagePointSize.height > 0 ? CGFloat(pixelsHigh) / imagePointSize.height : 1.0
    }

    @inline(__always)
    public func pixelRGBA(bx: Int, by: Int) -> (r: Int, g: Int, b: Int, a: Int) {
        let cx = max(0, min(pixelsWide - 1, bx))
        let cy = max(0, min(pixelsHigh - 1, by))
        let offset = cy * bytesPerRow + cx * 4
        let r = Int(rgba[offset])
        let g = Int(rgba[offset + 1])
        let b = Int(rgba[offset + 2])
        let a = Int(rgba[offset + 3])
        if a > 0 && a < 255 {
            // Un-premultiply for crisp color matching near rounded corners
            return (min(255, (r * 255) / a), min(255, (g * 255) / a), min(255, (b * 255) / a), a)
        }
        return (r, g, b, a)
    }

    public func sampleColor(at imagePt: CGPoint) -> (r: Int, g: Int, b: Int, hex: String)? {
        let bx = Int(round(imagePt.x * scaleX))
        let by = Int(round(imagePt.y * scaleY))
        guard bx >= 0 && bx < pixelsWide && by >= 0 && by < pixelsHigh else { return nil }
        let (r, g, b, _) = pixelRGBA(bx: bx, by: by)
        let hex = String(format: "#%02X%02X%02X", r, g, b)
        return (r, g, b, hex)
    }

    /// Computes WCAG 2.1 luminance contrast ratio between two hex colors (1.0...21.0).
    public static func contrastRatio(hex1: String, hex2: String) -> Double? {
        guard let c1 = parseHex(hex1), let c2 = parseHex(hex2) else { return nil }
        let l1 = relativeLuminance(r: c1.r, g: c1.g, b: c1.b)
        let l2 = relativeLuminance(r: c2.r, g: c2.g, b: c2.b)
        let bright = max(l1, l2)
        let dark = min(l1, l2)
        return (bright + 0.05) / (dark + 0.05)
    }

    private static func parseHex(_ hex: String) -> (r: Int, g: Int, b: Int)? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let val = Int(cleaned, radix: 16) else { return nil }
        return ((val >> 16) & 0xFF, (val >> 8) & 0xFF, val & 0xFF)
    }

    private static func relativeLuminance(r: Int, g: Int, b: Int) -> Double {
        func lin(_ channel: Int) -> Double {
            let v = Double(channel) / 255.0
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    // MARK: - Smart UI Contrast Edge Snapping & Raycast
    @inline(__always)
    private func isEdge(bx1: Int, by1: Int, bx2: Int, by2: Int, threshold: Int = 28) -> Bool {
        let c1 = pixelRGBA(bx: bx1, by: by1)
        let c2 = pixelRGBA(bx: bx2, by: by2)
        let diff = abs(c1.r - c2.r) + abs(c1.g - c2.g) + abs(c1.b - c2.b) + abs(c1.a - c2.a)
        return diff >= threshold
    }

    /// Searches ±radiusPt along the horizontal or vertical axis for the sharpest UI contrast transition edge.
    public func snapCoordinate(near imagePt: CGPoint, horizontal: Bool, searchRadiusPt: CGFloat = 9.0) -> CGFloat? {
        let sy = scaleY
        let sx = scaleX
        let fixedCoord = horizontal ? Int(round(imagePt.y * sy)) : Int(round(imagePt.x * sx))
        let centerCoord = horizontal ? Int(round(imagePt.x * sx)) : Int(round(imagePt.y * sy))
        let radiusPx = Int(round(searchRadiusPt * (horizontal ? sx : sy)))
        let maxBound = horizontal ? pixelsWide - 2 : pixelsHigh - 2

        var bestSignedOffset = Int.max
        var minDist = Int.max
        var maxDiff = 0

        for offset in -radiusPx...radiusPx {
            let pos = centerCoord + offset
            guard pos >= 1 && pos < maxBound else { continue }
            let cPrev = horizontal ? pixelRGBA(bx: pos - 1, by: fixedCoord) : pixelRGBA(bx: fixedCoord, by: pos - 1)
            let cCurr = horizontal ? pixelRGBA(bx: pos, by: fixedCoord) : pixelRGBA(bx: fixedCoord, by: pos)
            let diff = abs(cCurr.r - cPrev.r) + abs(cCurr.g - cPrev.g) + abs(cCurr.b - cPrev.b) + abs(cCurr.a - cPrev.a)
            if diff >= 32 {
                let d = abs(offset)
                if d < minDist || (d == minDist && diff > maxDiff) {
                    minDist = d
                    maxDiff = diff
                    bestSignedOffset = offset
                }
            }
        }

        guard bestSignedOffset != Int.max else { return nil }
        let targetPx = centerCoord + bestSignedOffset
        return CGFloat(targetPx) / (horizontal ? sx : sy)
    }

    public struct SmartSpan {
        public let originPt: CGPoint
        public let leftX: CGFloat
        public let rightX: CGFloat
        public let topY: CGFloat
        public let bottomY: CGFloat

        public var horizontalDistance: Int { Int(round(abs(rightX - leftX))) }
        public var verticalDistance: Int { Int(round(abs(bottomY - topY))) }
    }

    /// Raycasts left, right, up, down from `imagePt` to detect surrounding button, card, or spacing boundaries.
    public func raycastSpan(at imagePt: CGPoint, maxScanPt: CGFloat = 650.0) -> SmartSpan? {
        let cx = Int(round(imagePt.x * scaleX))
        let cy = Int(round(imagePt.y * scaleY))
        guard cx >= 1 && cx < pixelsWide - 1 && cy >= 1 && cy < pixelsHigh - 1 else { return nil }

        let base = pixelRGBA(bx: cx, by: cy)
        let maxPxH = Int(maxScanPt * scaleX)
        let maxPxV = Int(maxScanPt * scaleY)
        let edgeThresh = 30

        func deviates(_ c: (r: Int, g: Int, b: Int, a: Int)) -> Bool {
            abs(c.r - base.r) + abs(c.g - base.g) + abs(c.b - base.b) + abs(c.a - base.a) >= edgeThresh
        }

        // Left ray
        var leftPx = cx
        for step in 1...maxPxH {
            let tx = cx - step
            if tx <= 0 { leftPx = 0; break }
            if deviates(pixelRGBA(bx: tx, by: cy)) { leftPx = tx + 1; break }
            leftPx = tx
        }

        // Right ray
        var rightPx = cx
        for step in 1...maxPxH {
            let tx = cx + step
            if tx >= pixelsWide - 1 { rightPx = pixelsWide - 1; break }
            if deviates(pixelRGBA(bx: tx, by: cy)) { rightPx = tx; break }
            rightPx = tx
        }

        // Up ray (decreasing Y in top-left image space)
        var topPx = cy
        for step in 1...maxPxV {
            let ty = cy - step
            if ty <= 0 { topPx = 0; break }
            if deviates(pixelRGBA(bx: cx, by: ty)) { topPx = ty + 1; break }
            topPx = ty
        }

        // Down ray (increasing Y)
        var bottomPx = cy
        for step in 1...maxPxV {
            let ty = cy + step
            if ty >= pixelsHigh - 1 { bottomPx = pixelsHigh - 1; break }
            if deviates(pixelRGBA(bx: cx, by: ty)) { bottomPx = ty; break }
            bottomPx = ty
        }

        return SmartSpan(
            originPt: imagePt,
            leftX: CGFloat(leftPx) / scaleX,
            rightX: CGFloat(rightPx) / scaleX,
            topY: CGFloat(topPx) / scaleY,
            bottomY: CGFloat(bottomPx) / scaleY
        )
    }
}

// MARK: - Editor Observable State
@MainActor
public final class ScreenshotEditorState: ObservableObject {
    @Published public var currentTool: AnnotationTool = .distance
    @Published public var activeInk: DesignerInk = .azure
    @Published public var annotations: [CanvasAnnotation] = []
    @Published public var canUndo: Bool = false
    @Published public var canRedo: Bool = false
    @Published public var isPinned: Bool = false

    @Published public var hoveredHexColor: String = "#0A84FF"
    @Published public var pinnedBgHexColor: String? = nil

    @Published public var zoomScale: CGFloat = 1.0           // Multiplier relative to initial fit scale
    @Published public var effectiveDisplayScale: CGFloat = 1.0
    @Published public var panOffset: CGPoint = .zero
    @Published public var isSpacePanning: Bool = false

    @Published public var nextPinNumber: Int = 1
    @Published public var selectedAnnotationIndex: Int? = nil

    public var image: NSImage?
    public var imageSize: CGSize = .zero      // Logical points (CSS px)
    public var pixelSize: CGSize = .zero      // Physical bitmap pixels
    public var hasEmbeddedShadow: Bool = false

    private var undoHistory: [[CanvasAnnotation]] = []
    private var redoHistory: [[CanvasAnnotation]] = []

    // Action hooks triggered from both toolbar & keyboard shortcuts
    public var onRequestCopy: (() -> Void)?
    public var onRequestSave: (() -> Void)?
    public var onRequestTogglePin: (() -> Void)?
    public var onRequestZoomBy: ((CGFloat) -> Void)?
    public var onRequestZoomFit: (() -> Void)?
    public var onRequestZoomActual: (() -> Void)?
    public var onCancelTextOrSelection: (() -> Void)?
    public var onCanvasMutated: (() -> Void)?

    public func resetHistory() {
        undoHistory.removeAll()
        redoHistory.removeAll()
        canUndo = false
        canRedo = false
        nextPinNumber = 1
        selectedAnnotationIndex = nil
        pinnedBgHexColor = nil
        panOffset = .zero
        zoomScale = 1.0
    }

    public func pushUndoSnapshot() {
        undoHistory.append(annotations)
        redoHistory.removeAll()
        canUndo = !undoHistory.isEmpty
        canRedo = false
    }

    public func addAnnotation(_ ann: CanvasAnnotation) {
        pushUndoSnapshot()
        annotations.append(ann)
        selectedAnnotationIndex = annotations.count - 1
        recomputeNextPin()
        onCanvasMutated?()
    }

    public func deleteSelected() {
        guard let idx = selectedAnnotationIndex, idx >= 0 && idx < annotations.count else { return }
        pushUndoSnapshot()
        annotations.remove(at: idx)
        selectedAnnotationIndex = nil
        recomputeNextPin()
        onCanvasMutated?()
    }

    public func undo() {
        guard let prev = undoHistory.popLast() else { return }
        redoHistory.append(annotations)
        annotations = prev
        selectedAnnotationIndex = nil
        canUndo = !undoHistory.isEmpty
        canRedo = !redoHistory.isEmpty
        recomputeNextPin()
        onCanvasMutated?()
    }

    public func redo() {
        guard let next = redoHistory.popLast() else { return }
        let prevCount = annotations.count
        undoHistory.append(annotations)
        annotations = next
        selectedAnnotationIndex = next.count > prevCount ? next.count - 1 : nil
        canUndo = !undoHistory.isEmpty
        canRedo = !redoHistory.isEmpty
        recomputeNextPin()
        onCanvasMutated?()
    }

    public func recomputeNextPin() {
        let maxPin = annotations.filter { $0.tool == .numberedPin }.map(\.number).max() ?? 0
        nextPinNumber = maxPin + 1
    }

    public var contrastInfo: (ratio: Double, badge: String, passedAA: Bool)? {
        guard let bg = pinnedBgHexColor,
              let ratio = PixelInspectBuffer.contrastRatio(hex1: bg, hex2: hoveredHexColor) else { return nil }
        let badge: String
        if ratio >= 7.0 { badge = "AAA" }
        else if ratio >= 4.5 { badge = "AA" }
        else if ratio >= 3.0 { badge = "AA Lg" }
        else { badge = "Fail" }
        return (ratio, badge, ratio >= 4.5)
    }
}

// MARK: - Window Controller with Guaranteed Keyboard Shortcut Dispatch
@MainActor
public class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {
    public static let shared = ScreenshotEditorWindowController()

    private var window: NSWindow?
    private let state = ScreenshotEditorState()
    private var localKeyDownMonitor: Any?
    private var localKeyUpMonitor: Any?

    private override init() {
        super.init()
    }

    public func show(image: NSImage, sourceRect: NSRect, hasEmbeddedShadow: Bool = false, on screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens[0]

        state.image = image
        state.imageSize = image.size
        state.hasEmbeddedShadow = hasEmbeddedShadow
        state.annotations.removeAll()
        state.resetHistory()

        if let rep = image.representations.first(where: { $0.pixelsWide > 0 && $0.pixelsHigh > 0 }) {
            state.pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            state.pixelSize = CGSize(width: cg.width, height: cg.height)
        } else {
            state.pixelSize = image.size
        }

        let toolbarH: CGFloat = 54
        let minW: CGFloat = 940
        let minH: CGFloat = 540

        let maxW = targetScreen.visibleFrame.width * 0.90
        let maxH = targetScreen.visibleFrame.height * 0.90

        let desiredW = min(max(image.size.width + 64, minW), maxW)
        let desiredH = min(max(image.size.height + toolbarH + 64, minH), maxH)

        let contentRect = NSRect(
            x: targetScreen.visibleFrame.midX - desiredW / 2,
            y: targetScreen.visibleFrame.midY - desiredH / 2,
            width: desiredW,
            height: desiredH
        )

        let win = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        win.title = "Designer Studio"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.backgroundColor = NSColor.windowBackgroundColor

        state.onRequestTogglePin = { [weak self] in
            self?.state.isPinned.toggle()
            self?.window?.level = self?.state.isPinned == true ? .floating : .normal
        }

        let rootView = ScreenshotEditorRootView(state: state, onClose: { [weak self] in
            self?.close()
        })
        win.contentView = NSHostingView(rootView: rootView)

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyboardMonitors()
    }

    public func addSampleAnnotationsForTesting() {
        state.annotations = [
            CanvasAnnotation(tool: .distance, startPoint: CGPoint(x: 80, y: 140), endPoint: CGPoint(x: 360, y: 140)),
            CanvasAnnotation(tool: .distance, startPoint: CGPoint(x: 410, y: 200), endPoint: CGPoint(x: 410, y: 245)), // 45px -> highlights off-grid amber
            CanvasAnnotation(tool: .arrow, startPoint: CGPoint(x: 540, y: 310), endPoint: CGPoint(x: 445, y: 215), color: DesignerInk.coral.nsColor),
            CanvasAnnotation(tool: .rectangle, startPoint: CGPoint(x: 80, y: 200), endPoint: CGPoint(x: 380, y: 270)),
            CanvasAnnotation(tool: .roundedRect, startPoint: CGPoint(x: 80, y: 300), endPoint: CGPoint(x: 380, y: 400), color: DesignerInk.emerald.nsColor),
            CanvasAnnotation(tool: .numberedPin, startPoint: CGPoint(x: 428, y: 200), endPoint: CGPoint(x: 428, y: 200), number: 1, color: DesignerInk.coral.nsColor),
            CanvasAnnotation(tool: .numberedPin, startPoint: CGPoint(x: 428, y: 320), endPoint: CGPoint(x: 428, y: 320), number: 2),
            CanvasAnnotation(tool: .text, startPoint: CGPoint(x: 465, y: 310), endPoint: CGPoint(x: 465, y: 310), text: "Fix 4px grid margin", color: DesignerInk.coral.nsColor),
            CanvasAnnotation(tool: .blur, startPoint: CGPoint(x: 520, y: 428), endPoint: CGPoint(x: 775, y: 468)),
        ]
        state.recomputeNextPin()
        state.onCanvasMutated?()
    }

    public func close() {
        removeKeyboardMonitors()
        window?.orderOut(nil)
        window = nil
    }

    public func windowWillClose(_ notification: Notification) {
        removeKeyboardMonitors()
        window = nil
    }

    private func installKeyboardMonitors() {
        removeKeyboardMonitors()

        localKeyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let win = self.window, win.isKeyWindow else { return event }

            // Let inline text editor field receive normal typing keys natively (Esc cancels text editor)
            if win.firstResponder is NSTextView || win.firstResponder is NSTextField {
                if event.keyCode == 53 {
                    self.state.onCancelTextOrSelection?()
                    return nil
                }
                return event
            }

            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmd = flags.contains(.command)
            let isShift = flags.contains(.shift)
            let hasOtherMods = flags.contains(.option) || flags.contains(.control)

            // 1. Command shortcuts (Undo, Redo, Copy, Save, Pin, Zoom)
            if isCmd && !hasOtherMods {
                switch event.keyCode {
                case 6: // Z
                    if isShift {
                        self.state.redo()
                    } else {
                        self.state.undo()
                    }
                    return nil
                case 8: // C
                    self.state.onRequestCopy?()
                    return nil
                case 1: // S
                    self.state.onRequestSave?()
                    return nil
                case 35: // P
                    self.state.onRequestTogglePin?()
                    return nil
                case 24, 69: // =/+
                    self.state.onRequestZoomBy?(1.25)
                    return nil
                case 27, 78: // -
                    self.state.onRequestZoomBy?(0.80)
                    return nil
                case 29, 82: // 0 -> Fit
                    self.state.onRequestZoomFit?()
                    return nil
                case 18, 83: // 1 -> Actual 100%
                    self.state.onRequestZoomActual?()
                    return nil
                default:
                    break
                }
            }

            // 2. Non-command functional keys
            if !isCmd && !flags.contains(.control) {
                switch event.keyCode {
                case 51, 117: // Delete / Forward Delete
                    if self.state.selectedAnnotationIndex != nil {
                        self.state.deleteSelected()
                        return nil
                    }
                case 48: // Tab / Shift+Tab
                    if isShift {
                        if self.state.pinnedBgHexColor == nil {
                            self.state.pinnedBgHexColor = self.state.hoveredHexColor
                            ToastHUDController.shared.showSimpleToast(message: "BG locked: \(self.state.hoveredHexColor)", icon: "circle.lefthalf.filled")
                        } else {
                            self.state.pinnedBgHexColor = nil
                        }
                    } else {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(self.state.hoveredHexColor, forType: .string)
                        ToastHUDController.shared.showSimpleToast(message: "Copied \(self.state.hoveredHexColor)", icon: "checkmark")
                    }
                    return nil
                case 53: // Esc
                    self.state.onCancelTextOrSelection?()
                    return nil
                case 49: // Space (Pan hold)
                    if !self.state.isSpacePanning {
                        self.state.isSpacePanning = true
                    }
                    return nil
                default:
                    break
                }
            }

            // 3. Single-letter Tool Switching (works reliably regardless of SwiftUI toolbar focus)
            if !isCmd && !hasOtherMods && !isShift {
                switch event.keyCode {
                case 9:  self.state.currentTool = .pointer; return nil      // V
                case 2:  self.state.currentTool = .distance; return nil     // D
                case 0:  self.state.currentTool = .arrow; return nil        // A
                case 17: self.state.currentTool = .text; return nil         // T
                case 45: self.state.currentTool = .numberedPin; return nil  // N
                case 15: self.state.currentTool = .rectangle; return nil    // R
                case 8:  self.state.currentTool = .roundedRect; return nil  // C
                case 35: self.state.currentTool = .pencil; return nil       // P
                case 11: self.state.currentTool = .blur; return nil         // B
                default: break
                }
            }

            return event
        }

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 49 { // Space release
                self?.state.isSpacePanning = false
            }
            return event
        }
    }

    private func removeKeyboardMonitors() {
        if let down = localKeyDownMonitor {
            NSEvent.removeMonitor(down)
            localKeyDownMonitor = nil
        }
        if let up = localKeyUpMonitor {
            NSEvent.removeMonitor(up)
            localKeyUpMonitor = nil
        }
    }
}

// MARK: - Root View with Unified Shottr-Inspired Toolbar
public struct ScreenshotEditorRootView: View {
    @ObservedObject var state: ScreenshotEditorState
    let onClose: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            toolbarHeader
                .frame(height: 54)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Rectangle()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )

            ScreenshotEditorCanvasRepresentable(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .edgesIgnoringSafeArea(.top)
        .onAppear {
            state.onRequestCopy = { copyFlattenedImage() }
            state.onRequestSave = { savePNGToDownloads() }
        }
    }

    // MARK: - Toolbar Header
    private var toolbarHeader: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 68)

            // Left Cluster: Copy, Save, Pin, Undo, Redo
            HStack(spacing: 5) {
                toolbarIconButton(icon: "doc.on.doc", tooltip: "Copy annotated image (⌘C)") {
                    copyFlattenedImage()
                }
                toolbarIconButton(icon: "square.and.arrow.down", tooltip: "Save PNG to Downloads (⌘S)") {
                    savePNGToDownloads()
                }
                toolbarIconButton(
                    icon: state.isPinned ? "pin.fill" : "pin",
                    tooltip: state.isPinned ? "Unpin window (⌘P)" : "Pin above all windows (⌘P)",
                    isActive: state.isPinned
                ) {
                    state.onRequestTogglePin?()
                }

                Divider().frame(height: 16).padding(.horizontal, 2)

                toolbarIconButton(
                    icon: "arrow.uturn.backward",
                    tooltip: "Undo (⌘Z)",
                    isDisabled: !state.canUndo
                ) {
                    state.undo()
                }
                toolbarIconButton(
                    icon: "arrow.uturn.forward",
                    tooltip: "Redo (⌘⇧Z)",
                    isDisabled: !state.canRedo
                ) {
                    state.redo()
                }
            }

            Spacer()

            // Center Cluster: Annotation Tools + Compact 4-Ink Color Switcher
            HStack(spacing: 8) {
                HStack(spacing: 3) {
                    ForEach(AnnotationTool.allCases) { tool in
                        Button(action: { state.currentTool = tool }) {
                            Image(systemName: tool.icon)
                                .font(.system(size: 13, weight: state.currentTool == tool ? .semibold : .regular))
                                .foregroundColor(state.currentTool == tool ? state.activeInk.swiftUIColor : .primary.opacity(0.85))
                                .frame(width: 28, height: 26)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(state.currentTool == tool ? state.activeInk.swiftUIColor.opacity(0.14) : Color.clear)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(state.currentTool == tool ? state.activeInk.swiftUIColor.opacity(0.35) : Color.clear, lineWidth: 0.8)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(tool.tooltip)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.04)))
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))

                // 4-Color Ink Dots
                HStack(spacing: 5) {
                    ForEach(DesignerInk.allCases) { ink in
                        Button(action: { state.activeInk = ink }) {
                            Circle()
                                .fill(ink.swiftUIColor)
                                .frame(width: 11, height: 11)
                                .overlay(
                                    Circle()
                                        .stroke(Color.primary.opacity(state.activeInk == ink ? 0.85 : 0.15), lineWidth: state.activeInk == ink ? 1.5 : 0.5)
                                        .padding(-2)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(ink.label)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.primary.opacity(0.04)))
                .overlay(Capsule().stroke(Color.primary.opacity(0.08), lineWidth: 0.8))
            }

            Spacer()

            // Right Cluster: Hex Loupe + Contrast, Pixels + Points Size, Interactive Zoom
            HStack(spacing: 10) {
                // Color Loupe + Contrast Ratio Readout
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.hoveredHexColor, forType: .string)
                    ToastHUDController.shared.showSimpleToast(message: "Copied \(state.hoveredHexColor)", icon: "checkmark")
                }) {
                    HStack(spacing: 6) {
                        if let bg = state.pinnedBgHexColor {
                            HStack(spacing: -4) {
                                Circle().fill(Color(hex: bg) ?? .black)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.white.opacity(0.6), lineWidth: 0.8))
                                Circle().fill(Color(hex: state.hoveredHexColor) ?? .blue)
                                    .frame(width: 12, height: 12)
                                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.6))
                            }
                        } else {
                            Circle()
                                .fill(Color(hex: state.hoveredHexColor) ?? .blue)
                                .frame(width: 12, height: 12)
                                .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.6))
                        }

                        VStack(alignment: .leading, spacing: 0) {
                            Text(verbatim: state.hoveredHexColor)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                                .lineLimit(1)

                            if let contrast = state.contrastInfo {
                                Text(verbatim: String(format: "%.1f:1 %@", contrast.ratio, contrast.badge))
                                    .font(.system(size: 8.5, weight: .semibold))
                                    .foregroundColor(contrast.passedAA ? Color(red: 48/255, green: 209/255, blue: 88/255) : Color(red: 255/255, green: 159/255, blue: 10/255))
                                    .lineLimit(1)
                            } else {
                                Text("Tab to copy")
                                    .font(.system(size: 8.5))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                }
                .buttonStyle(.plain)
                .help("Click or press Tab to copy Hex • ⇧Tab locks contrast background")

                Divider().frame(height: 18)

                // Dual Image Size: Pixels (Primary) + Points (Secondary)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: "\(Int(state.pixelSize.width))×\(Int(state.pixelSize.height)) px")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(verbatim: "\(Int(state.imageSize.width))×\(Int(state.imageSize.height)) pt")
                        .font(.system(size: 8.5))
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .fixedSize(horizontal: true, vertical: false)

                Divider().frame(height: 18)

                // Interactive Zoom Pill (Scroll/Pinch/Cmd± to zoom)
                Menu {
                    Button("Zoom to Fit (⌘0)") { state.onRequestZoomFit?() }
                    Button("Actual Size 100% (⌘1)") { state.onRequestZoomActual?() }
                    Divider()
                    Button("Zoom In 25% (⌘+)") { state.onRequestZoomBy?(1.25) }
                    Button("Zoom Out 25% (⌘-)") { state.onRequestZoomBy?(0.80) }
                } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(verbatim: "\(Int(round(state.effectiveDisplayScale * 100)))%")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text("Zoom")
                            .font(.system(size: 8.5))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Scroll or pinch to zoom under cursor (⌘+ / ⌘- / ⌘0)")
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.trailing, 14)
        }
    }

    private func toolbarIconButton(icon: String, tooltip: String, isActive: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isActive ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(isDisabled ? 0.3 : 0.85))
                .frame(width: 28, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isActive ? Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.12) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isActive ? Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .help(tooltip)
    }

    private func copyFlattenedImage() {
        guard let flattened = ScreenshotEditorCanvasNSView.renderFlattenedImage(state: state) else { return }
        let pboard = NSPasteboard.general
        pboard.clearContents()
        if let tiff = flattened.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            pboard.setData(png, forType: .png)
            pboard.setData(tiff, forType: .tiff)
            NSSound.beep()
            ToastHUDController.shared.showSimpleToast(message: "Image with annotations copied", icon: "doc.on.doc")
        }
    }

    private func savePNGToDownloads() {
        guard let flattened = ScreenshotEditorCanvasNSView.renderFlattenedImage(state: state),
              let tiff = flattened.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dateStr = formatter.string(from: Date())
        let filename = "Screenshot \(dateStr).png"

        let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let fileUrl = downloadsUrl.appendingPathComponent(filename)

        do {
            try pngData.write(to: fileUrl)
            NSSound.beep()
            ToastHUDController.shared.showSimpleToast(message: "Saved to Downloads", icon: "arrow.down.doc")
        } catch {
            print("Failed to save image: \(error)")
        }
    }
}

// MARK: - AppKit Canvas Representable
public struct ScreenshotEditorCanvasRepresentable: NSViewRepresentable {
    @ObservedObject var state: ScreenshotEditorState

    public func makeNSView(context: Context) -> ScreenshotEditorCanvasNSView {
        ScreenshotEditorCanvasNSView(state: state)
    }

    public func updateNSView(_ nsView: ScreenshotEditorCanvasNSView, context: Context) {
        nsView.syncState(state)
    }
}

// MARK: - Interactive AppKit Vector Canvas with Cursor Zoom & Smart UI Edge Snapping
public class ScreenshotEditorCanvasNSView: NSView {
    private var state: ScreenshotEditorState
    private var pixelBuffer: PixelInspectBuffer?
    private var cachedImageID: ObjectIdentifier?
    private var trackingAreaRef: NSTrackingArea?

    // Drag / Pan / Hover state
    private var dragStartImagePoint: CGPoint?
    private var lastPanViewPoint: NSPoint?
    private var isPanningCanvas: Bool = false
    private var hasPushedMoveUndo: Bool = false
    private var liveAnnotation: CanvasAnnotation?
    private var currentHoverImagePoint: CGPoint?
    private var hoverSmartSpan: PixelInspectBuffer.SmartSpan?
    private var activeSnapGuides: (horizontalY: [CGFloat], verticalX: [CGFloat]) = ([], [])

    // Inline text editor
    private var inlineTextField: NSTextField?
    private var editingAnnotationIndex: Int?

    // Core Image context for live Mosaic Redaction
    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var cachedBlurredNSImage: NSImage?
    private var cachedBlurredImageID: ObjectIdentifier?

    public init(state: ScreenshotEditorState) {
        self.state = state
        super.init(frame: .zero)
        self.wantsLayer = true
        updateCaches()
        wireStateCallbacks()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func syncState(_ newState: ScreenshotEditorState) {
        self.state = newState
        updateCaches()
        wireStateCallbacks()
        updateEffectiveDisplayScaleTelemetry()
        needsDisplay = true
    }

    private func wireStateCallbacks() {
        state.onRequestZoomBy = { [weak self] factor in
            guard let self else { return }
            let center = NSPoint(x: self.bounds.midX, y: self.bounds.midY)
            self.applyZoom(factor: factor, anchoredAtViewPoint: center)
        }
        state.onRequestZoomFit = { [weak self] in
            self?.resetZoomToFit()
        }
        state.onRequestZoomActual = { [weak self] in
            self?.zoomToActual100()
        }
        state.onCancelTextOrSelection = { [weak self] in
            self?.cancelActiveInteractions()
        }
        state.onCanvasMutated = { [weak self] in
            self?.needsDisplay = true
        }
    }

    private func updateCaches() {
        guard let img = state.image else {
            pixelBuffer = nil
            cachedImageID = nil
            cachedBlurredNSImage = nil
            cachedBlurredImageID = nil
            return
        }
        let imgID = ObjectIdentifier(img)
        if cachedImageID != imgID {
            cachedImageID = imgID
            self.pixelBuffer = PixelInspectBuffer(image: img)
        }
        if cachedBlurredImageID != imgID {
            cachedBlurredImageID = imgID
            self.cachedBlurredNSImage = Self.buildPixellatedImage(from: img)
        }
    }

    override public var acceptsFirstResponder: Bool { true }
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateEffectiveDisplayScaleTelemetry()
    }

    override public func cursorUpdate(with event: NSEvent) {
        if isPanningCanvas || state.isSpacePanning {
            NSCursor.openHand.set()
            return
        }
        switch state.currentTool {
        case .pointer:     NSCursor.arrow.set()
        case .text:        NSCursor.iBeam.set()
        case .numberedPin: NSCursor.pointingHand.set()
        default:           NSCursor.crosshair.set()
        }
    }

    // MARK: - Coordinate Mapping & Zoom Math
    private func baseFitScale() -> CGFloat {
        guard let img = state.image, img.size.width > 0 && img.size.height > 0 else { return 1.0 }
        guard bounds.width > 80 && bounds.height > 80 else { return 1.0 }
        let availW = bounds.width - 40
        let availH = bounds.height - 40
        return min(min(availW / img.size.width, availH / img.size.height), 1.0)
    }

    private func effectiveScale() -> CGFloat {
        return baseFitScale() * state.zoomScale
    }

    private func updateEffectiveDisplayScaleTelemetry() {
        guard bounds.width > 80 && bounds.height > 80 else { return }
        let eff = effectiveScale()
        if abs(state.effectiveDisplayScale - eff) > 0.005 {
            DispatchQueue.main.async { [weak self] in
                self?.state.effectiveDisplayScale = eff
            }
        }
    }

    private func imageDisplayRect() -> NSRect {
        guard let img = state.image, img.size.width > 0 && img.size.height > 0 else { return bounds }
        let scale = effectiveScale()
        let renderW = img.size.width * scale
        let renderH = img.size.height * scale
        let cx = bounds.midX + state.panOffset.x
        let cy = bounds.midY + state.panOffset.y
        return NSRect(x: cx - renderW / 2, y: cy - renderH / 2, width: renderW, height: renderH)
    }

    private func viewPointToImagePointUnclamped(_ viewPt: NSPoint) -> CGPoint? {
        let r = imageDisplayRect()
        guard r.width > 0 && r.height > 0, let img = state.image else { return nil }
        let relX = (viewPt.x - r.origin.x) / r.width
        let relY = (viewPt.y - r.origin.y) / r.height
        return CGPoint(x: relX * img.size.width, y: (1.0 - relY) * img.size.height)
    }

    private func viewPointToImagePoint(_ viewPt: NSPoint) -> CGPoint? {
        guard let pt = viewPointToImagePointUnclamped(viewPt), let img = state.image else { return nil }
        guard pt.x >= 0 && pt.x <= img.size.width && pt.y >= 0 && pt.y <= img.size.height else { return nil }
        return pt
    }

    private func viewPointToClampedImagePoint(_ viewPt: NSPoint) -> CGPoint? {
        guard let pt = viewPointToImagePointUnclamped(viewPt), let img = state.image else { return nil }
        return CGPoint(
            x: max(0, min(img.size.width, pt.x)),
            y: max(0, min(img.size.height, pt.y))
        )
    }

    private func imagePointToViewPoint(_ imgPt: CGPoint) -> NSPoint {
        let r = imageDisplayRect()
        guard let img = state.image, img.size.width > 0 && img.size.height > 0 else { return .zero }
        let relX = imgPt.x / img.size.width
        let relY = 1.0 - (imgPt.y / img.size.height)
        return NSPoint(x: r.origin.x + relX * r.width, y: r.origin.y + relY * r.height)
    }

    // MARK: - Zoom & Pan Gestures (Anchored at Cursor)
    private func applyZoom(factor: CGFloat, anchoredAtViewPoint anchor: NSPoint) {
        let oldEff = effectiveScale()
        guard oldEff > 0 else { return }

        let oldCenterX = bounds.midX + state.panOffset.x
        let oldCenterY = bounds.midY + state.panOffset.y
        let offsetFromCenterX = (anchor.x - oldCenterX) / oldEff
        let offsetFromCenterY = (anchor.y - oldCenterY) / oldEff

        let minZoom: CGFloat = 0.25
        let maxZoom: CGFloat = 12.0 / max(0.25, baseFitScale())
        let newZoomScale = min(max(state.zoomScale * factor, minZoom), maxZoom)
        state.zoomScale = newZoomScale

        let newEff = effectiveScale()
        let newCenterX = anchor.x - offsetFromCenterX * newEff
        let newCenterY = anchor.y - offsetFromCenterY * newEff

        if newZoomScale <= 1.02 && factor < 1.0 {
            // Gently snap centered when returning to fit zoom
            state.panOffset = .zero
            if abs(newZoomScale - 1.0) < 0.05 { state.zoomScale = 1.0 }
        } else {
            state.panOffset = CGPoint(x: newCenterX - bounds.midX, y: newCenterY - bounds.midY)
        }
        state.effectiveDisplayScale = effectiveScale()
        needsDisplay = true
    }

    private func resetZoomToFit() {
        state.zoomScale = 1.0
        state.panOffset = .zero
        state.effectiveDisplayScale = effectiveScale()
        needsDisplay = true
    }

    private func zoomToActual100() {
        let fit = baseFitScale()
        state.zoomScale = fit > 0 ? (1.0 / fit) : 1.0
        state.panOffset = .zero
        state.effectiveDisplayScale = effectiveScale()
        needsDisplay = true
    }

    override public func scrollWheel(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        // Zoom anchored at cursor on hover scroll (supports both mouse wheel and trackpad)
        if abs(event.scrollingDeltaY) > 0.05 {
            let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.012 : 0.08
            let factor = exp(event.scrollingDeltaY * sensitivity)
            applyZoom(factor: factor, anchoredAtViewPoint: loc)
            return
        }
        if abs(event.scrollingDeltaX) > 0.05 && state.zoomScale > 1.05 {
            state.panOffset.x += event.scrollingDeltaX
            needsDisplay = true
        }
    }

    override public func magnify(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let factor = max(0.5, min(2.0, 1.0 + event.magnification))
        applyZoom(factor: factor, anchoredAtViewPoint: loc)
    }

    override public func flagsChanged(with event: NSEvent) {
        refreshHoverTelemetry(atViewPoint: convert(window?.mouseLocationOutsideOfEventStream ?? .zero, from: nil), modifiers: event.modifierFlags)
    }

    // MARK: - Mouse Hover, Drawing, Dragging
    override public func mouseMoved(with event: NSEvent) {
        let viewLoc = convert(event.locationInWindow, from: nil)
        refreshHoverTelemetry(atViewPoint: viewLoc, modifiers: event.modifierFlags)
    }

    override public func mouseExited(with event: NSEvent) {
        currentHoverImagePoint = nil
        hoverSmartSpan = nil
        needsDisplay = true
    }

    private func refreshHoverTelemetry(atViewPoint viewLoc: NSPoint, modifiers: NSEvent.ModifierFlags) {
        guard let imgPt = viewPointToImagePoint(viewLoc) else {
            currentHoverImagePoint = nil
            hoverSmartSpan = nil
            needsDisplay = true
            return
        }

        currentHoverImagePoint = imgPt
        if let sample = pixelBuffer?.sampleColor(at: imgPt) {
            state.hoveredHexColor = sample.hex
        }

        let isOptionHeld = modifiers.contains(.option)
        let showSmart = (state.currentTool == .distance) || (SettingsManager.shared.enableSmartDistance && isOptionHeld)
        if showSmart && liveAnnotation == nil {
            hoverSmartSpan = pixelBuffer?.raycastSpan(at: imgPt)
        } else {
            hoverSmartSpan = nil
        }

        needsDisplay = true
    }

    override public func otherMouseDown(with event: NSEvent) {
        // Middle mouse drag pans canvas
        isPanningCanvas = true
        lastPanViewPoint = convert(event.locationInWindow, from: nil)
        NSCursor.closedHand.set()
    }

    override public func otherMouseDragged(with event: NSEvent) {
        guard isPanningCanvas, let last = lastPanViewPoint else { return }
        let cur = convert(event.locationInWindow, from: nil)
        state.panOffset.x += (cur.x - last.x)
        state.panOffset.y += (cur.y - last.y)
        lastPanViewPoint = cur
        needsDisplay = true
    }

    override public func otherMouseUp(with event: NSEvent) {
        isPanningCanvas = false
        lastPanViewPoint = nil
        window?.invalidateCursorRects(for: self)
    }

    override public func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        commitInlineTextIfNeeded()

        let viewLoc = convert(event.locationInWindow, from: nil)

        // Space + Drag -> Pan canvas
        if state.isSpacePanning {
            isPanningCanvas = true
            lastPanViewPoint = viewLoc
            NSCursor.closedHand.set()
            return
        }

        guard let imgPt = viewPointToClampedImagePoint(viewLoc) else {
            // Clicking margin outside image with Pointer can pan
            if state.currentTool == .pointer {
                isPanningCanvas = true
                lastPanViewPoint = viewLoc
                state.selectedAnnotationIndex = nil
            }
            return
        }

        // Alt+Click with smart distance enabled OR clicking on pointer double-click
        if event.clickCount == 2, state.currentTool == .pointer {
            if let hitIdx = topAnnotationIndex(at: imgPt), state.annotations[hitIdx].tool == .text {
                beginEditingTextAnnotation(at: hitIdx)
                return
            }
        }

        switch state.currentTool {
        case .pointer:
            if let hitIdx = topAnnotationIndex(at: imgPt) {
                state.selectedAnnotationIndex = hitIdx
                dragStartImagePoint = imgPt
                hasPushedMoveUndo = false
            } else {
                state.selectedAnnotationIndex = nil
                // Dragging empty background inside zoomed image with Pointer also pans seamlessly
                if state.zoomScale > 1.05 {
                    isPanningCanvas = true
                    lastPanViewPoint = viewLoc
                }
            }

        case .numberedPin:
            let pin = CanvasAnnotation(
                tool: .numberedPin,
                startPoint: imgPt,
                endPoint: imgPt,
                number: state.nextPinNumber,
                color: state.activeInk.nsColor
            )
            state.addAnnotation(pin)

        case .text:
            showInlineTextEditor(atViewPoint: viewLoc, imagePoint: imgPt, initialText: "")

        case .pencil:
            dragStartImagePoint = imgPt
            var ann = CanvasAnnotation(tool: .pencil, startPoint: imgPt, endPoint: imgPt, color: state.activeInk.nsColor)
            ann.pathPoints = [imgPt]
            liveAnnotation = ann

        case .distance:
            // Snap startPoint to nearby contrast edge (within 9pt) unless holding Command
            var startPt = imgPt
            activeSnapGuides = ([], [])
            if !event.modifierFlags.contains(.command), let buf = pixelBuffer {
                if let snapX = buf.snapCoordinate(near: imgPt, horizontal: true) {
                    startPt.x = snapX
                    activeSnapGuides.verticalX.append(snapX)
                }
                if let snapY = buf.snapCoordinate(near: imgPt, horizontal: false) {
                    startPt.y = snapY
                    activeSnapGuides.horizontalY.append(snapY)
                }
            }
            dragStartImagePoint = startPt
            liveAnnotation = CanvasAnnotation(tool: .distance, startPoint: startPt, endPoint: startPt, color: state.activeInk.nsColor)

        default:
            dragStartImagePoint = imgPt
            liveAnnotation = CanvasAnnotation(tool: state.currentTool, startPoint: imgPt, endPoint: imgPt, color: state.activeInk.nsColor)
        }

        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        let viewLoc = convert(event.locationInWindow, from: nil)

        if isPanningCanvas, let last = lastPanViewPoint {
            state.panOffset.x += (viewLoc.x - last.x)
            state.panOffset.y += (viewLoc.y - last.y)
            lastPanViewPoint = viewLoc
            needsDisplay = true
            return
        }

        guard let currentImgPt = viewPointToClampedImagePoint(viewLoc) else { return }

        if state.currentTool == .pointer, let idx = state.selectedAnnotationIndex, let start = dragStartImagePoint {
            if !hasPushedMoveUndo {
                state.pushUndoSnapshot()
                hasPushedMoveUndo = true
            }
            let dx = currentImgPt.x - start.x
            let dy = currentImgPt.y - start.y
            state.annotations[idx].startPoint.x += dx
            state.annotations[idx].startPoint.y += dy
            state.annotations[idx].endPoint.x += dx
            state.annotations[idx].endPoint.y += dy
            for i in 0..<state.annotations[idx].pathPoints.count {
                state.annotations[idx].pathPoints[i].x += dx
                state.annotations[idx].pathPoints[i].y += dy
            }
            dragStartImagePoint = currentImgPt
        } else if var live = liveAnnotation, let start = dragStartImagePoint {
            var end = currentImgPt
            activeSnapGuides = ([], [])

            if live.tool == .distance {
                // STRICT HORIZONTAL OR VERTICAL ONLY — NEVER DIAGONAL!
                let dx = abs(end.x - start.x)
                let dy = abs(end.y - start.y)
                let isHorizontal = dx >= dy

                if isHorizontal {
                    end.y = start.y
                    if !event.modifierFlags.contains(.command), let buf = pixelBuffer {
                        if let snappedEndX = buf.snapCoordinate(near: CGPoint(x: end.x, y: start.y), horizontal: true) {
                            end.x = snappedEndX
                            activeSnapGuides.verticalX.append(start.x)
                            activeSnapGuides.verticalX.append(snappedEndX)
                        }
                    }
                } else {
                    end.x = start.x
                    if !event.modifierFlags.contains(.command), let buf = pixelBuffer {
                        if let snappedEndY = buf.snapCoordinate(near: CGPoint(x: start.x, y: end.y), horizontal: false) {
                            end.y = snappedEndY
                            activeSnapGuides.horizontalY.append(start.y)
                            activeSnapGuides.horizontalY.append(snappedEndY)
                        }
                    }
                }
            } else if live.tool == .pencil {
                live.pathPoints.append(end)
            }

            live.endPoint = end
            liveAnnotation = live
        }

        needsDisplay = true
    }

    override public func mouseUp(with event: NSEvent) {
        if isPanningCanvas {
            isPanningCanvas = false
            lastPanViewPoint = nil
            window?.invalidateCursorRects(for: self)
            return
        }

        activeSnapGuides = ([], [])
        hasPushedMoveUndo = false

        if var live = liveAnnotation {
            let dx = abs(live.endPoint.x - live.startPoint.x)
            let dy = abs(live.endPoint.y - live.startPoint.y)

            if dx > 3 || dy > 3 || (live.tool == .pencil && live.pathPoints.count > 2) {
                state.addAnnotation(live)
            } else if live.tool == .distance, let span = pixelBuffer?.raycastSpan(at: live.startPoint) {
                // Single click with D tool: automatically drop tighter snapped vertical or horizontal span!
                let hDist = span.horizontalDistance
                let vDist = span.verticalDistance
                let imgW = state.imageSize.width
                let imgH = state.imageSize.height

                let useVertical: Bool
                if event.modifierFlags.contains(.shift) {
                    useVertical = !(vDist <= hDist)
                } else if vDist <= 420 && hDist > 420 {
                    useVertical = true
                } else if hDist <= 420 && vDist > 420 {
                    useVertical = false
                } else {
                    useVertical = vDist <= hDist
                }

                if useVertical && vDist >= 4 && CGFloat(vDist) < imgH * 0.92 {
                    live.startPoint = CGPoint(x: live.startPoint.x, y: span.topY)
                    live.endPoint = CGPoint(x: live.startPoint.x, y: span.bottomY)
                    state.addAnnotation(live)
                } else if !useVertical && hDist >= 4 && CGFloat(hDist) < imgW * 0.92 {
                    live.startPoint = CGPoint(x: span.leftX, y: live.startPoint.y)
                    live.endPoint = CGPoint(x: span.rightX, y: live.startPoint.y)
                    state.addAnnotation(live)
                }
            }
            liveAnnotation = nil
        }

        dragStartImagePoint = nil
        needsDisplay = true
    }

    private func cancelActiveInteractions() {
        if inlineTextField != nil {
            dismissInlineTextField()
        } else if liveAnnotation != nil {
            liveAnnotation = nil
            dragStartImagePoint = nil
            activeSnapGuides = ([], [])
        } else {
            state.selectedAnnotationIndex = nil
        }
        needsDisplay = true
    }

    // MARK: - Inline Text Editor
    private func beginEditingTextAnnotation(at index: Int) {
        guard index >= 0 && index < state.annotations.count else { return }
        let ann = state.annotations[index]
        editingAnnotationIndex = index
        let viewPt = imagePointToViewPoint(ann.startPoint)
        showInlineTextEditor(atViewPoint: viewPt, imagePoint: ann.startPoint, initialText: ann.text)
    }

    private func showInlineTextEditor(atViewPoint viewPoint: NSPoint, imagePoint: CGPoint, initialText: String) {
        dismissInlineTextField()
        let field = NSTextField(frame: NSRect(x: max(12, min(viewPoint.x - 10, bounds.width - 210)), y: max(12, min(viewPoint.y - 14, bounds.height - 40)), width: 200, height: 28))
        field.focusRingType = .exterior
        field.bezelStyle = .roundedBezel
        field.backgroundColor = NSColor.black.withAlphaComponent(0.90)
        field.textColor = .white
        field.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        field.stringValue = initialText
        field.placeholderString = "Note (Return to apply)"
        field.target = self
        field.action = #selector(textEntered(_:))

        addSubview(field)
        window?.makeFirstResponder(field)
        self.inlineTextField = field
        self.dragStartImagePoint = imagePoint
    }

    @objc private func textEntered(_ sender: NSTextField) {
        commitInlineTextIfNeeded()
        window?.makeFirstResponder(self)
    }

    private func commitInlineTextIfNeeded() {
        guard let tf = inlineTextField else { return }
        let text = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editIdx = editingAnnotationIndex, editIdx < state.annotations.count {
            if !text.isEmpty && text != state.annotations[editIdx].text {
                state.pushUndoSnapshot()
                state.annotations[editIdx].text = text
            }
        } else if !text.isEmpty, let imgPt = dragStartImagePoint {
            var ann = CanvasAnnotation(tool: .text, startPoint: imgPt, endPoint: imgPt, color: state.activeInk.nsColor)
            ann.text = text
            state.addAnnotation(ann)
        }

        editingAnnotationIndex = nil
        dismissInlineTextField()
        needsDisplay = true
    }

    private func dismissInlineTextField() {
        editingAnnotationIndex = nil
        inlineTextField?.removeFromSuperview()
        inlineTextField = nil
    }

    // MARK: - Hit Testing
    private func topAnnotationIndex(at pt: CGPoint) -> Int? {
        for (index, ann) in state.annotations.enumerated().reversed() {
            if isPoint(pt, near: ann) { return index }
        }
        return nil
    }

    private func isPoint(_ pt: CGPoint, near ann: CanvasAnnotation) -> Bool {
        let threshold: CGFloat = 14.0 / max(0.5, effectiveScale())
        switch ann.tool {
        case .numberedPin:
            return hypot(pt.x - ann.startPoint.x, pt.y - ann.startPoint.y) <= threshold + 10
        case .text:
            let cardW = max(50, CGFloat(ann.text.count) * 7.5 + 16)
            let rect = CGRect(x: ann.startPoint.x - 6, y: ann.startPoint.y - 26, width: cardW + 12, height: 34)
            return rect.contains(pt)
        case .distance, .arrow:
            let p1 = ann.startPoint, p2 = ann.endPoint
            let l2 = pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2)
            if l2 == 0 { return hypot(pt.x - p1.x, pt.y - p1.y) <= threshold }
            let t = max(0, min(1, ((pt.x - p1.x) * (p2.x - p1.x) + (pt.y - p1.y) * (p2.y - p1.y)) / l2))
            let proj = CGPoint(x: p1.x + t * (p2.x - p1.x), y: p1.y + t * (p2.y - p1.y))
            return hypot(pt.x - proj.x, pt.y - proj.y) <= threshold
        case .rectangle, .roundedRect, .blur:
            let r = CGRect(
                x: min(ann.startPoint.x, ann.endPoint.x),
                y: min(ann.startPoint.y, ann.endPoint.y),
                width: max(1, abs(ann.endPoint.x - ann.startPoint.x)),
                height: max(1, abs(ann.endPoint.y - ann.startPoint.y))
            ).insetBy(dx: -threshold, dy: -threshold)
            return r.contains(pt)
        case .pencil:
            return ann.pathPoints.contains { hypot(pt.x - $0.x, pt.y - $0.y) <= threshold }
        default:
            return false
        }
    }

    // MARK: - Core Drawing Routine
    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Background Checkerboard
        drawCheckerboard(in: bounds, ctx: ctx)

        guard let img = state.image else { return }
        let imgRect = imageDisplayRect()
        let effScale = effectiveScale()

        // 2. Base Image (crisp pixel grid interpolation when zoomed >= 300%)
        ctx.saveGState()
        if !state.hasEmbeddedShadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.22).cgColor)
        }
        ctx.interpolationQuality = effScale >= 3.0 ? .none : .high
        img.draw(in: imgRect)
        ctx.restoreGState()

        // Subtle Pixel Grid at >= 300% Zoom for surgical pixel inspection
        if effScale >= 3.0 {
            drawPixelGrid(in: imgRect, scale: effScale, ctx: ctx)
        }

        // 3. Committed Vector Annotations
        for (index, ann) in state.annotations.enumerated() {
            drawAnnotation(ann, isSelected: index == state.selectedAnnotationIndex, in: ctx, blurredSource: cachedBlurredNSImage, imageDisplayRect: imgRect)
        }

        // 4. Smart Hover Preview (when hovering with Dimension tool or holding Option)
        if let span = hoverSmartSpan, liveAnnotation == nil {
            drawSmartHoverGuides(span: span, in: ctx)
        }

        // 5. Live Magnetic Snap Extension Guides while dragging
        drawActiveSnapExtensionGuides(in: ctx, imgRect: imgRect)

        // 6. Active Live Drag Annotation
        if let live = liveAnnotation {
            drawAnnotation(live, isSelected: false, in: ctx, blurredSource: cachedBlurredNSImage, imageDisplayRect: imgRect)
        }
    }

    private func drawPixelGrid(in imgRect: NSRect, scale: CGFloat, ctx: CGContext) {
        let clamped = imgRect.intersection(bounds)
        guard !clamped.isNull else { return }
        ctx.saveGState()
        ctx.clip(to: imgRect)
        ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.07).cgColor)
        ctx.setLineWidth(0.5)

        let step = scale
        var x = imgRect.minX + ceil((clamped.minX - imgRect.minX) / step) * step
        while x <= clamped.maxX {
            ctx.move(to: CGPoint(x: x, y: clamped.minY))
            ctx.addLine(to: CGPoint(x: x, y: clamped.maxY))
            x += step
        }
        var y = imgRect.minY + ceil((clamped.minY - imgRect.minY) / step) * step
        while y <= clamped.maxY {
            ctx.move(to: CGPoint(x: clamped.minX, y: y))
            ctx.addLine(to: CGPoint(x: clamped.maxX, y: y))
            y += step
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawSmartHoverGuides(span: PixelInspectBuffer.SmartSpan, in ctx: CGContext) {
        let auditUnit = SettingsManager.shared.gridAuditUnit
        let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.90)
        let amber = NSColor(red: 255/255, green: 159/255, blue: 10/255, alpha: 0.95)

        let vOrigin = imagePointToViewPoint(span.originPt)
        let vLeft = imagePointToViewPoint(CGPoint(x: span.leftX, y: span.originPt.y))
        let vRight = imagePointToViewPoint(CGPoint(x: span.rightX, y: span.originPt.y))
        let vTop = imagePointToViewPoint(CGPoint(x: span.originPt.x, y: span.topY))
        let vBottom = imagePointToViewPoint(CGPoint(x: span.originPt.x, y: span.bottomY))

        let hDist = span.horizontalDistance
        let vDist = span.verticalDistance

        ctx.saveGState()
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.setLineWidth(1.2)

        // Horizontal ray guide
        if hDist >= 4 && CGFloat(hDist) < state.imageSize.width * 0.92 {
            let hOffGrid = auditUnit > 1 && (hDist % auditUnit != 0)
            let hColor = hOffGrid ? amber : accent
            ctx.setStrokeColor(hColor.cgColor)
            ctx.strokeLineSegments(between: [vLeft, vRight])

            // Edge perpendicular ticks
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokeLineSegments(between: [
                CGPoint(x: vLeft.x, y: vOrigin.y - 6), CGPoint(x: vLeft.x, y: vOrigin.y + 6),
                CGPoint(x: vRight.x, y: vOrigin.y - 6), CGPoint(x: vRight.x, y: vOrigin.y + 6)
            ])

            let label = hOffGrid ? "↔ \(hDist)px" : "↔ \(hDist)px"
            drawPillBadge(text: label, at: CGPoint(x: (vLeft.x + vRight.x)/2, y: vOrigin.y - 16), fill: hColor)
        }

        // Vertical ray guide
        if vDist >= 4 && CGFloat(vDist) < state.imageSize.height * 0.92 {
            let vOffGrid = auditUnit > 1 && (vDist % auditUnit != 0)
            let vColor = vOffGrid ? amber : accent
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            ctx.setStrokeColor(vColor.cgColor)
            ctx.strokeLineSegments(between: [vTop, vBottom])

            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokeLineSegments(between: [
                CGPoint(x: vOrigin.x - 6, y: vTop.y), CGPoint(x: vOrigin.x + 6, y: vTop.y),
                CGPoint(x: vOrigin.x - 6, y: vBottom.y), CGPoint(x: vOrigin.x + 6, y: vBottom.y)
            ])

            let label = "↕ \(vDist)px"
            drawPillBadge(text: label, at: CGPoint(x: vOrigin.x + 28, y: (vTop.y + vBottom.y)/2), fill: vColor)
        }
        ctx.restoreGState()
    }

    private func drawActiveSnapExtensionGuides(in ctx: CGContext, imgRect: NSRect) {
        guard !activeSnapGuides.verticalX.isEmpty || !activeSnapGuides.horizontalY.isEmpty else { return }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.45).cgColor)
        ctx.setLineDash(phase: 0, lengths: [3, 3])
        ctx.setLineWidth(1.0)

        for imgX in activeSnapGuides.verticalX {
            let vx = imagePointToViewPoint(CGPoint(x: imgX, y: 0)).x
            ctx.strokeLineSegments(between: [CGPoint(x: vx, y: imgRect.minY), CGPoint(x: vx, y: imgRect.maxY)])
        }
        for imgY in activeSnapGuides.horizontalY {
            let vy = imagePointToViewPoint(CGPoint(x: 0, y: imgY)).y
            ctx.strokeLineSegments(between: [CGPoint(x: imgRect.minX, y: vy), CGPoint(x: imgRect.maxX, y: vy)])
        }
        ctx.restoreGState()
    }

    private func drawPillBadge(text: String, at center: CGPoint, fill: NSColor) {
        let str = text as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let s = str.size(withAttributes: attrs)
        let r = NSRect(x: center.x - (s.width + 12)/2, y: center.y - 9, width: s.width + 12, height: 18)
        fill.setFill()
        NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()
        str.draw(at: NSPoint(x: r.origin.x + 6, y: r.origin.y + 2.5), withAttributes: attrs)
    }

    private func drawAnnotation(_ ann: CanvasAnnotation, isSelected: Bool, in ctx: CGContext, blurredSource: NSImage?, imageDisplayRect imgRect: NSRect) {
        let ink = ann.color
        let vStart = imagePointToViewPoint(ann.startPoint)
        let vEnd = imagePointToViewPoint(ann.endPoint)
        let auditUnit = SettingsManager.shared.gridAuditUnit

        switch ann.tool {
        case .distance:
            // Strictly vertical or horizontal pixel measurement
            let dx = abs(ann.endPoint.x - ann.startPoint.x)
            let dy = abs(ann.endPoint.y - ann.startPoint.y)
            let dist = Int(round(max(dx, dy)))
            let isOffGrid = (auditUnit > 1) && (dist > 0) && (dist % auditUnit != 0)
            let badgeColor = isOffGrid ? DesignerInk.amber.nsColor : ink

            ctx.setStrokeColor(badgeColor.cgColor)
            ctx.setLineWidth(1.6)
            ctx.strokeLineSegments(between: [vStart, vEnd])

            let tickLen: CGFloat = 7
            let angle = atan2(vEnd.y - vStart.y, vEnd.x - vStart.x)
            let perp = angle + .pi / 2

            ctx.strokeLineSegments(between: [
                CGPoint(x: vStart.x + cos(perp) * tickLen, y: vStart.y + sin(perp) * tickLen),
                CGPoint(x: vStart.x - cos(perp) * tickLen, y: vStart.y - sin(perp) * tickLen),
                CGPoint(x: vEnd.x + cos(perp) * tickLen, y: vEnd.y + sin(perp) * tickLen),
                CGPoint(x: vEnd.x - cos(perp) * tickLen, y: vEnd.y - sin(perp) * tickLen)
            ])

            let mid = CGPoint(x: (vStart.x + vEnd.x) / 2, y: (vStart.y + vEnd.y) / 2)
            let label = isOffGrid ? "\(dist)px!" : "\(dist)px"
            drawPillBadge(text: label, at: mid, fill: badgeColor)

        case .arrow:
            ctx.setStrokeColor(ink.cgColor)
            ctx.setLineWidth(2.2)
            ctx.strokeLineSegments(between: [vStart, vEnd])

            let angle = atan2(vEnd.y - vStart.y, vEnd.x - vStart.x)
            let headLen: CGFloat = 11.0
            let p1 = CGPoint(x: vEnd.x - headLen * cos(angle - .pi / 6), y: vEnd.y - headLen * sin(angle - .pi / 6))
            let p2 = CGPoint(x: vEnd.x - headLen * cos(angle + .pi / 6), y: vEnd.y - headLen * sin(angle + .pi / 6))

            ctx.setFillColor(ink.cgColor)
            ctx.beginPath()
            ctx.move(to: vEnd)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.closePath()
            ctx.fillPath()

        case .rectangle:
            let r = normalizedRect(from: vStart, to: vEnd)
            ctx.setStrokeColor(ink.cgColor)
            ctx.setLineWidth(1.8)
            ctx.stroke(r)

            let imgW = Int(round(abs(ann.endPoint.x - ann.startPoint.x)))
            let imgH = Int(round(abs(ann.endPoint.y - ann.startPoint.y)))
            let tagText = "\(imgW) × \(imgH) px" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = tagText.size(withAttributes: attrs)
            let tagRect = NSRect(x: r.minX, y: r.maxY >= 20 ? r.maxY - 18 : r.minY, width: size.width + 10, height: 16)
            NSColor.black.withAlphaComponent(0.86).setFill()
            NSBezierPath(roundedRect: tagRect, xRadius: 3, yRadius: 3).fill()
            tagText.draw(at: NSPoint(x: tagRect.origin.x + 5, y: tagRect.origin.y + 2), withAttributes: attrs)

        case .roundedRect:
            let r = normalizedRect(from: vStart, to: vEnd)
            let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            ink.setStroke()
            path.lineWidth = 1.8
            path.stroke()

            let tagText = "r: 8px" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = tagText.size(withAttributes: attrs)
            let tagRect = NSRect(x: r.minX, y: r.maxY >= 20 ? r.maxY - 18 : r.minY, width: size.width + 10, height: 16)
            NSColor.black.withAlphaComponent(0.86).setFill()
            NSBezierPath(roundedRect: tagRect, xRadius: 3, yRadius: 3).fill()
            tagText.draw(at: NSPoint(x: tagRect.origin.x + 5, y: tagRect.origin.y + 2), withAttributes: attrs)

        case .numberedPin:
            let center = vStart
            let circleRect = NSRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)
            ink.setFill()
            let circlePath = NSBezierPath(ovalIn: circleRect)
            circlePath.fill()

            NSColor.white.setStroke()
            circlePath.lineWidth = 1.6
            circlePath.stroke()

            let numText = "\(ann.number)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = numText.size(withAttributes: attrs)
            numText.draw(at: NSPoint(x: center.x - size.width / 2, y: center.y - size.height / 2), withAttributes: attrs)

        case .text:
            let cardText = (ann.text.isEmpty ? "Note" : ann.text) as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let size = cardText.size(withAttributes: attrs)
            let cardRect = NSRect(x: vStart.x, y: vStart.y, width: size.width + 16, height: size.height + 8)

            NSColor.black.withAlphaComponent(0.86).setFill()
            let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 6, yRadius: 6)
            cardPath.fill()
            ink.setStroke()
            cardPath.lineWidth = 1.0
            cardPath.stroke()
            cardText.draw(at: NSPoint(x: cardRect.origin.x + 8, y: cardRect.origin.y + 4), withAttributes: attrs)

        case .pencil:
            if !ann.pathPoints.isEmpty {
                let path = NSBezierPath()
                let pts = ann.pathPoints.map { imagePointToViewPoint($0) }
                path.move(to: pts[0])
                for pt in pts.dropFirst() { path.line(to: pt) }
                path.lineWidth = 6.0 * max(0.7, effectiveScale())
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                ink.withAlphaComponent(0.35).setStroke()
                path.stroke()
            }

        case .blur:
            let r = normalizedRect(from: vStart, to: vEnd)
            let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            if let mosaic = blurredSource {
                ctx.saveGState()
                path.addClip()
                ctx.interpolationQuality = .none
                mosaic.draw(in: imgRect)
                NSColor.labelColor.withAlphaComponent(0.05).setFill()
                path.fill()
                ctx.restoreGState()
                NSColor.labelColor.withAlphaComponent(0.14).setStroke()
                path.lineWidth = 0.8
                path.stroke()
            } else {
                NSColor.black.withAlphaComponent(0.70).setFill()
                path.fill()
            }

        default:
            break
        }

        if isSelected {
            let b = boundingBox(for: ann)
            let vMin = imagePointToViewPoint(b.origin)
            let vMax = imagePointToViewPoint(CGPoint(x: b.maxX, y: b.maxY))
            let selR = normalizedRect(from: vMin, to: vMax).insetBy(dx: -6, dy: -6)

            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.setStrokeColor(ink.cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(selR)
            ctx.restoreGState()
        }
    }

    private func boundingBox(for ann: CanvasAnnotation) -> CGRect {
        var minX = min(ann.startPoint.x, ann.endPoint.x)
        var minY = min(ann.startPoint.y, ann.endPoint.y)
        var maxX = max(ann.startPoint.x, ann.endPoint.x)
        var maxY = max(ann.startPoint.y, ann.endPoint.y)
        for p in ann.pathPoints {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        if ann.tool == .text {
            let w = max(50, CGFloat(ann.text.count) * 7.5 + 16)
            return CGRect(x: minX, y: minY - 22, width: w, height: 24)
        }
        return CGRect(x: minX, y: minY, width: max(20, maxX - minX), height: max(20, maxY - minY))
    }

    private func drawCheckerboard(in rect: NSRect, ctx: CGContext) {
        ctx.setFillColor(NSColor.underPageBackgroundColor.cgColor)
        ctx.fill(rect)

        let tileSize: CGFloat = 8
        let cols = Int(ceil(rect.width / tileSize))
        let rows = Int(ceil(rect.height / tileSize))

        ctx.setFillColor(NSColor.labelColor.withAlphaComponent(0.04).cgColor)
        for row in 0..<rows {
            for col in 0..<cols {
                if (row + col) % 2 == 0 {
                    ctx.fill(CGRect(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize, width: tileSize, height: tileSize))
                }
            }
        }
    }

    private func normalizedRect(from p1: NSPoint, to p2: NSPoint) -> NSRect {
        let x = min(p1.x, p2.x)
        let y = min(p1.y, p2.y)
        let w = abs(p1.x - p2.x)
        let h = abs(p1.y - p2.y)
        return NSRect(x: x, y: y, width: max(1, w), height: max(1, h))
    }

    // MARK: - CoreImage Mosaic Redaction Builder
    private static func buildPixellatedImage(from image: NSImage) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIPixellate") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        let blockScale = max(8.0, min(14.0, CGFloat(cg.width) / 110.0))
        filter.setValue(blockScale, forKey: kCIInputScaleKey)
        guard let out = filter.outputImage?.cropped(to: ciImage.extent),
              let resultCG = ciContext.createCGImage(out, from: ciImage.extent) else { return nil }
        return NSImage(cgImage: resultCG, size: image.size)
    }

    // MARK: - Flattened Image Generation for Copy / Save
    public static func renderFlattenedImage(state: ScreenshotEditorState) -> NSImage? {
        guard let baseImage = state.image else { return nil }
        let size = baseImage.size
        let pixelW = max(1, Int(state.pixelSize.width > 0 ? state.pixelSize.width : size.width * 2))
        let pixelH = max(1, Int(state.pixelSize.height > 0 ? state.pixelSize.height : size.height * 2))
        let scaleX = CGFloat(pixelW) / max(1, size.width)
        let scaleY = CGFloat(pixelH) / max(1, size.height)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelW,
            height: pixelH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return baseImage }

        let mosaicImage = buildPixellatedImage(from: baseImage)
        let gCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gCtx

        // Draw base image at full native pixels
        baseImage.draw(in: NSRect(origin: .zero, size: NSSize(width: pixelW, height: pixelH)))

        // Scale context to draw vector annotations in logical point space
        ctx.scaleBy(x: scaleX, y: scaleY)

        let auditUnit = SettingsManager.shared.gridAuditUnit

        for ann in state.annotations {
            let ink = ann.color
            let p1 = CGPoint(x: ann.startPoint.x, y: size.height - ann.startPoint.y)
            let p2 = CGPoint(x: ann.endPoint.x, y: size.height - ann.endPoint.y)

            switch ann.tool {
            case .distance:
                let dx = abs(ann.endPoint.x - ann.startPoint.x)
                let dy = abs(ann.endPoint.y - ann.startPoint.y)
                let dist = Int(round(max(dx, dy)))
                let isOffGrid = (auditUnit > 1) && (dist > 0) && (dist % auditUnit != 0)
                let badgeColor = isOffGrid ? DesignerInk.amber.nsColor : ink

                ctx.setStrokeColor(badgeColor.cgColor)
                ctx.setLineWidth(1.6)
                ctx.strokeLineSegments(between: [p1, p2])

                let tickLen: CGFloat = 7
                let angle = atan2(p2.y - p1.y, p2.x - p1.x)
                let perp = angle + .pi / 2
                ctx.strokeLineSegments(between: [
                    CGPoint(x: p1.x + cos(perp) * tickLen, y: p1.y + sin(perp) * tickLen),
                    CGPoint(x: p1.x - cos(perp) * tickLen, y: p1.y - sin(perp) * tickLen),
                    CGPoint(x: p2.x + cos(perp) * tickLen, y: p2.y + sin(perp) * tickLen),
                    CGPoint(x: p2.x - cos(perp) * tickLen, y: p2.y - sin(perp) * tickLen)
                ])

                let mid = CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2)
                let text = (isOffGrid ? "\(dist)px!" : "\(dist)px") as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let s = text.size(withAttributes: attrs)
                let badgeRect = NSRect(x: mid.x - (s.width + 12)/2, y: mid.y - 9, width: s.width + 12, height: 18)
                badgeColor.setFill()
                NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
                text.draw(at: NSPoint(x: badgeRect.origin.x + 6, y: badgeRect.origin.y + 2.5), withAttributes: attrs)

            case .arrow:
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(2.2)
                ctx.strokeLineSegments(between: [p1, p2])

                let angle = atan2(p2.y - p1.y, p2.x - p1.x)
                let headLen: CGFloat = 11.0
                let a1 = CGPoint(x: p2.x - headLen * cos(angle - .pi / 6), y: p2.y - headLen * sin(angle - .pi / 6))
                let a2 = CGPoint(x: p2.x - headLen * cos(angle + .pi / 6), y: p2.y - headLen * sin(angle + .pi / 6))

                ctx.setFillColor(ink.cgColor)
                ctx.beginPath()
                ctx.move(to: p2)
                ctx.addLine(to: a1)
                ctx.addLine(to: a2)
                ctx.closePath()
                ctx.fillPath()

            case .rectangle:
                let r = NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
                ctx.setStrokeColor(ink.cgColor)
                ctx.setLineWidth(1.8)
                ctx.stroke(r)

                let imgW = Int(round(abs(ann.endPoint.x - ann.startPoint.x)))
                let imgH = Int(round(abs(ann.endPoint.y - ann.startPoint.y)))
                let tag = "\(imgW) × \(imgH) px" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let s = tag.size(withAttributes: attrs)
                let tr = NSRect(x: r.minX, y: r.maxY >= 20 ? r.maxY - 18 : r.minY, width: s.width + 10, height: 16)
                NSColor.black.withAlphaComponent(0.86).setFill()
                NSBezierPath(roundedRect: tr, xRadius: 3, yRadius: 3).fill()
                tag.draw(at: NSPoint(x: tr.origin.x + 5, y: tr.origin.y + 2), withAttributes: attrs)

            case .roundedRect:
                let r = NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
                ink.setStroke()
                let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
                path.lineWidth = 1.8
                path.stroke()

            case .numberedPin:
                let r = NSRect(x: p1.x - 11, y: p1.y - 11, width: 22, height: 22)
                ink.setFill()
                let circle = NSBezierPath(ovalIn: r)
                circle.fill()
                NSColor.white.setStroke()
                circle.lineWidth = 1.6
                circle.stroke()

                let text = "\(ann.number)" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let s = text.size(withAttributes: attrs)
                text.draw(at: NSPoint(x: p1.x - s.width / 2, y: p1.y - s.height / 2), withAttributes: attrs)

            case .text:
                let text = (ann.text.isEmpty ? "Note" : ann.text) as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                    .foregroundColor: NSColor.white
                ]
                let s = text.size(withAttributes: attrs)
                let r = NSRect(x: p1.x, y: p1.y, width: s.width + 16, height: s.height + 8)
                NSColor.black.withAlphaComponent(0.86).setFill()
                let card = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
                card.fill()
                ink.setStroke()
                card.lineWidth = 1.0
                card.stroke()
                text.draw(at: NSPoint(x: r.origin.x + 8, y: r.origin.y + 4), withAttributes: attrs)

            case .pencil:
                if !ann.pathPoints.isEmpty {
                    let path = NSBezierPath()
                    let pts = ann.pathPoints.map { CGPoint(x: $0.x, y: size.height - $0.y) }
                    path.move(to: pts[0])
                    for pt in pts.dropFirst() { path.line(to: pt) }
                    path.lineWidth = 6.0
                    path.lineCapStyle = .round
                    path.lineJoinStyle = .round
                    ink.withAlphaComponent(0.35).setStroke()
                    path.stroke()
                }

            case .blur:
                let r = NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
                let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
                if let mosaic = mosaicImage {
                    ctx.saveGState()
                    path.addClip()
                    mosaic.draw(in: NSRect(origin: .zero, size: size))
                    ctx.restoreGState()
                } else {
                    NSColor.black.withAlphaComponent(0.75).setFill()
                    path.fill()
                }

            default:
                break
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let finalCG = ctx.makeImage() else { return baseImage }
        return NSImage(cgImage: finalCG, size: size)
    }
}
