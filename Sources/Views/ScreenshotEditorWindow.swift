import AppKit
import SwiftUI
import CoreImage
import UniformTypeIdentifiers
import Vision

// MARK: - Editor Observable State
@MainActor
public final class ScreenshotEditorState: ObservableObject {
    public struct EditorSnapshot {
        public var annotations: [CanvasAnnotation]
        public var image: NSImage?
        public var cutoutImage: NSImage?
        public var pixelSize: CGSize
        public var removeBG: Bool
    }

    @Published public var currentTool: AnnotationTool = .pointer
    @Published public var annotations: [CanvasAnnotation] = []
    @Published public var canUndo: Bool = false
    @Published public var canRedo: Bool = false
    @Published public var isPinned: Bool = false

    // Backdrop, Frame & Subject Cutout
    @Published public var backdropConfig: BackdropConfig = BackdropConfig()
    @Published public var cutoutImage: NSImage? = nil
    @Published public var isRemovingBackground: Bool = false
    @Published public var isBackdropPopoverOpen: Bool = false
    @Published public var isBackdropColorPopoverOpen: Bool = false
    @Published public var pendingCropRect: CGRect? = nil
    @Published public var pendingOCRRect: CGRect? = nil
    @Published public var gifFrames: [ImageBackdropCompositor.AnimatedGIFFrame] = []
    @Published public var currentGifFrameIndex: Int = 0

    // Per-tool Persistent Style Defaults
    @Published public var arrowColor: NSColor = .white
    @Published public var arrowWidth: CGFloat = 4.5
    @Published public var arrowStyle: ArrowStyle = .tapered

    @Published public var textColor: NSColor = .white
    @Published public var textSize: CGFloat = 16.0
    @Published public var textStyle: TextStyle = .quoteBubble

    @Published public var rectColor: NSColor = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)
    @Published public var rectWidth: CGFloat = 2.5
    @Published public var rectFillMode: RectFillMode = .stroke
    @Published public var rectCornerRadius: CGFloat = 0.0
    @Published public var rectShowSizeTag: Bool = false

    @Published public var spotlightColor: NSColor = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)
    @Published public var rulerColor: NSColor = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)
    @Published public var pinColor: NSColor = NSColor(red: 255/255, green: 69/255, blue: 58/255, alpha: 1.0)
    @Published public var highlighterColor: NSColor = NSColor(red: 255/255, green: 159/255, blue: 10/255, alpha: 1.0)
    @Published public var highlighterWidth: CGFloat = 14.0

    // Telemetry & Viewport
    @Published public var hoveredHexColor: String = "#0A84FF"
    @Published public var pinnedBgHexColor: String? = nil
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var effectiveDisplayScale: CGFloat = 1.0
    @Published public var panOffset: CGPoint = .zero
    @Published public var isSpacePanning: Bool = false

    @Published public var nextPinNumber: Int = 1
    @Published public var selectedAnnotationIndex: Int? = nil
    @Published public var isColorPopoverOpen: Bool = false
    @Published public var isEditingInlineText: Bool = false
    public let annotationColorPickerState = ColorPickerPopoverUIState()
    public let backdropColorPickerState = ColorPickerPopoverUIState()

    public var image: NSImage?
    public var imageSize: CGSize = .zero      // Logical points (CSS px)
    public var pixelSize: CGSize = .zero      // Physical bitmap pixels
    public var hasEmbeddedShadow: Bool = false

    public var activeSubjectImage: NSImage? {
        if backdropConfig.removeSubjectBackground, let cut = cutoutImage {
            return cut
        }
        return image
    }

    private var undoHistory: [EditorSnapshot] = []
    private var redoHistory: [EditorSnapshot] = []
    private var propertyEditUndoToken: Date? = nil

    // Action hooks wired to Canvas & Window
    public var onRequestCopy: (() -> Void)?
    public var onRequestSave: (() -> Void)?
    public var onRequestSaveGIF: (() -> Void)?
    public var onRequestTogglePin: (() -> Void)?
    public var onRequestZoomBy: ((CGFloat) -> Void)?
    public var onRequestZoomFit: (() -> Void)?
    public var onRequestZoomActual: (() -> Void)?
    public var onCancelTextOrSelection: (() -> Void)?
    public var onCommitInlineText: (() -> Void)?
    public var onLivePropertyChanged: (() -> Void)?
    public var onOpenTextEditorAtIndex: ((Int) -> Void)?
    public var onCanvasMutated: (() -> Void)?
    public var onBackdropChanged: (() -> Void)?
    public var onRequestApplyCrop: (() -> Void)?
    public var onRequestCancelCrop: (() -> Void)?
    public var onRequestToggleBackgroundRemoval: (() -> Void)?
    public var onRequestChooseBackdropPhoto: (() -> Void)?
    public var onRequestChooseBackdropGIF: (() -> Void)?
    public var onRequestGrabOCRText: (() -> Void)?
    public var onRequestGrabOCRRegion: ((CGRect) -> Void)?

    public func selectTool(_ tool: AnnotationTool) {
        onCommitInlineText?()
        if tool != .crop {
            pendingCropRect = nil
        }
        if tool != .grabText {
            pendingOCRRect = nil
        }
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool != tool {
            selectedAnnotationIndex = nil
        }
        currentTool = tool
        onCanvasMutated?()
    }

    public func resetHistory() {
        undoHistory.removeAll()
        redoHistory.removeAll()
        canUndo = false
        canRedo = false
        nextPinNumber = 1
        selectedAnnotationIndex = nil
        pinnedBgHexColor = nil
        pendingCropRect = nil
        pendingOCRRect = nil
        cutoutImage = nil
        isRemovingBackground = false
        backdropConfig = BackdropConfig()
        gifFrames = []
        currentGifFrameIndex = 0
        panOffset = .zero
        zoomScale = 1.0
    }

    public func pushUndoSnapshot() {
        undoHistory.append(EditorSnapshot(
            annotations: annotations,
            image: image,
            cutoutImage: cutoutImage,
            pixelSize: pixelSize,
            removeBG: backdropConfig.removeSubjectBackground
        ))
        redoHistory.removeAll()
        canUndo = !undoHistory.isEmpty
        canRedo = false
    }

    public func beginPropertyEditUndoIfNeeded() {
        guard selectedAnnotationIndex != nil else { return }
        let now = Date()
        if let last = propertyEditUndoToken, now.timeIntervalSince(last) < 0.35 {
            propertyEditUndoToken = now
            return
        }
        propertyEditUndoToken = now
        pushUndoSnapshot()
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

    public func nudgeSelected(dx: CGFloat, dy: CGFloat) {
        guard let idx = selectedAnnotationIndex, idx >= 0 && idx < annotations.count else { return }
        beginPropertyEditUndoIfNeeded()
        annotations[idx].startPoint.x += dx
        annotations[idx].startPoint.y += dy
        annotations[idx].endPoint.x += dx
        annotations[idx].endPoint.y += dy
        if let cp = annotations[idx].controlPoint {
            annotations[idx].controlPoint = CGPoint(x: cp.x + dx, y: cp.y + dy)
        }
        for i in 0..<annotations[idx].pathPoints.count {
            annotations[idx].pathPoints[i].x += dx
            annotations[idx].pathPoints[i].y += dy
        }
        onCanvasMutated?()
    }

    public func undo() {
        guard let prev = undoHistory.popLast() else { return }
        redoHistory.append(EditorSnapshot(
            annotations: annotations,
            image: image,
            cutoutImage: cutoutImage,
            pixelSize: pixelSize,
            removeBG: backdropConfig.removeSubjectBackground
        ))
        annotations = prev.annotations
        if let img = prev.image {
            image = img
            imageSize = img.size
        }
        cutoutImage = prev.cutoutImage
        pixelSize = prev.pixelSize
        backdropConfig.removeSubjectBackground = prev.removeBG
        pendingCropRect = nil
        selectedAnnotationIndex = nil
        canUndo = !undoHistory.isEmpty
        canRedo = !redoHistory.isEmpty
        recomputeNextPin()
        onBackdropChanged?()
        onCanvasMutated?()
    }

    public func redo() {
        guard let next = redoHistory.popLast() else { return }
        let prevCount = annotations.count
        undoHistory.append(EditorSnapshot(
            annotations: annotations,
            image: image,
            cutoutImage: cutoutImage,
            pixelSize: pixelSize,
            removeBG: backdropConfig.removeSubjectBackground
        ))
        annotations = next.annotations
        if let img = next.image {
            image = img
            imageSize = img.size
        }
        cutoutImage = next.cutoutImage
        pixelSize = next.pixelSize
        backdropConfig.removeSubjectBackground = next.removeBG
        pendingCropRect = nil
        selectedAnnotationIndex = next.annotations.count > prevCount ? next.annotations.count - 1 : nil
        canUndo = !undoHistory.isEmpty
        canRedo = !redoHistory.isEmpty
        recomputeNextPin()
        onBackdropChanged?()
        onCanvasMutated?()
    }

    public func recomputeNextPin() {
        let maxPin = annotations.filter { $0.tool == .numberedPin }.map(\.number).max() ?? 0
        nextPinNumber = maxPin + 1
    }

    // MARK: - Inspector Live Bindings & Mutators
    public var currentArrowStyle: ArrowStyle {
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .arrow {
            return annotations[idx].arrowStyle
        }
        return arrowStyle
    }

    public var currentTextStyle: TextStyle {
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .text {
            return annotations[idx].textStyle
        }
        return textStyle
    }

    public var currentRectFillMode: RectFillMode {
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .rectangle {
            return annotations[idx].rectFillMode
        }
        return rectFillMode
    }

    public var currentRectCornerRadius: CGFloat {
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .rectangle {
            return annotations[idx].cornerRadius
        }
        return rectCornerRadius
    }

    public var currentRectShowSizeTag: Bool {
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .rectangle {
            return annotations[idx].showSizeTag
        }
        return rectShowSizeTag
    }

    public func activeInspectorColorBinding(for tool: AnnotationTool) -> Binding<NSColor> {
        Binding(
            get: { [weak self] in
                guard let self else { return .white }
                if let idx = self.selectedAnnotationIndex, idx < self.annotations.count {
                    return self.annotations[idx].color
                }
                return self.defaultColor(for: tool)
            },
            set: { [weak self] newColor in
                self?.applyColor(newColor, for: tool)
            }
        )
    }

    public func activeWidthBinding(for tool: AnnotationTool) -> Binding<CGFloat> {
        Binding(
            get: { [weak self] in
                guard let self else { return 4.0 }
                if let idx = self.selectedAnnotationIndex, idx < self.annotations.count {
                    return self.annotations[idx].strokeWidth
                }
                return self.defaultWidth(for: tool)
            },
            set: { [weak self] newWidth in
                self?.applyStrokeWidth(newWidth, for: tool)
            }
        )
    }

    public func defaultColor(for tool: AnnotationTool) -> NSColor {
        switch tool {
        case .arrow: return arrowColor
        case .text: return textColor
        case .rectangle: return rectColor
        case .distance: return rulerColor
        case .numberedPin: return pinColor
        case .pencil: return highlighterColor
        case .spotlight: return spotlightColor
        default: return rectColor
        }
    }

    public func defaultWidth(for tool: AnnotationTool) -> CGFloat {
        switch tool {
        case .arrow: return arrowWidth
        case .text: return textSize
        case .rectangle: return rectWidth
        case .pencil: return highlighterWidth
        default: return 3.0
        }
    }

    public func applyColor(_ color: NSColor, for tool: AnnotationTool) {
        switch tool {
        case .arrow: arrowColor = color
        case .text: textColor = color
        case .rectangle: rectColor = color
        case .distance: rulerColor = color
        case .numberedPin: pinColor = color
        case .pencil: highlighterColor = color
        case .spotlight: spotlightColor = color
        default: break
        }
        if let idx = selectedAnnotationIndex, idx < annotations.count {
            annotations[idx].color = color
            onCanvasMutated?()
        }
        onLivePropertyChanged?()
    }

    public func applyStrokeWidth(_ w: CGFloat, for tool: AnnotationTool) {
        switch tool {
        case .arrow: arrowWidth = w
        case .text: textSize = w
        case .rectangle: rectWidth = w
        case .pencil: highlighterWidth = w
        default: break
        }
        if let idx = selectedAnnotationIndex, idx < annotations.count {
            annotations[idx].strokeWidth = w
            onCanvasMutated?()
        }
        onLivePropertyChanged?()
    }

    public func applyArrowStyle(_ style: ArrowStyle) {
        arrowStyle = style
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .arrow {
            annotations[idx].arrowStyle = style
            onCanvasMutated?()
        }
        onLivePropertyChanged?()
    }

    public func flipSelectedArrowDirection() {
        guard let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .arrow else { return }
        pushUndoSnapshot()
        let s = annotations[idx].startPoint
        annotations[idx].startPoint = annotations[idx].endPoint
        annotations[idx].endPoint = s
        onCanvasMutated?()
    }

    public func applyTextStyle(_ style: TextStyle) {
        textStyle = style
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .text {
            annotations[idx].textStyle = style
            onCanvasMutated?()
        }
        onLivePropertyChanged?()
    }

    public func applyRectFillMode(_ mode: RectFillMode) {
        rectFillMode = mode
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .rectangle {
            annotations[idx].rectFillMode = mode
            onCanvasMutated?()
        }
    }

    public func applyCornerRadius(_ radius: CGFloat) {
        rectCornerRadius = radius
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .rectangle {
            annotations[idx].cornerRadius = radius
            onCanvasMutated?()
        }
    }

    public func toggleRectSizeTag() {
        let next = !currentRectShowSizeTag
        rectShowSizeTag = next
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .rectangle {
            annotations[idx].showSizeTag = next
            onCanvasMutated?()
        }
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

        // Close any previous editor window/live text editor cleanly so duplicate views never overlap
        state.onCancelTextOrSelection?()
        removeKeyboardMonitors()
        if let prev = self.window {
            prev.delegate = nil
            prev.orderOut(nil)
            self.window = nil
        }

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
        let minH: CGFloat = 560

        let maxW = targetScreen.visibleFrame.width * 0.90
        let maxH = targetScreen.visibleFrame.height * 0.90

        let desiredW = min(max(image.size.width + 64, minW), maxW)
        let desiredH = min(max(image.size.height + toolbarH + 104, minH), maxH)

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
        win.title = "Studio"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.titlebarSeparatorStyle = .none
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.backgroundColor = NSColor.windowBackgroundColor

        state.onRequestTogglePin = { [weak self] in
            self?.state.isPinned.toggle()
            self?.window?.level = self?.state.isPinned == true ? .floating : .normal
        }

        wireBackdropAndCropActions()

        let rootView = ScreenshotEditorRootView(state: state, onClose: { [weak self] in
            self?.close()
        })
        let hosting = NSHostingView(rootView: rootView)
        if #available(macOS 26.0, *) {
            hosting.safeAreaRegions = []
        }
        win.contentView = hosting

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyboardMonitors()
    }

    private func wireBackdropAndCropActions() {
        state.onRequestToggleBackgroundRemoval = { [weak self] in
            guard let self else { return }
            if self.state.backdropConfig.removeSubjectBackground {
                self.state.backdropConfig.removeSubjectBackground = false
                self.state.onBackdropChanged?()
                self.state.onCanvasMutated?()
                return
            }
            if self.state.cutoutImage != nil {
                self.state.backdropConfig.removeSubjectBackground = true
                self.state.onBackdropChanged?()
                self.state.onCanvasMutated?()
                return
            }
            guard let sourceImg = self.state.image else { return }
            self.state.isRemovingBackground = true
            Task { @MainActor [weak self] in
                let cut = await ImageBackdropCompositor.removeBackground(from: sourceImg)
                guard let self else { return }
                self.state.isRemovingBackground = false
                if let cut {
                    self.state.pushUndoSnapshot()
                    self.state.cutoutImage = cut
                    self.state.backdropConfig.removeSubjectBackground = true
                    if self.state.backdropConfig.backdropType == .none {
                        if let def = MacWallpaperStore.shared.defaultWallpaperImageAndId() {
                            self.state.backdropConfig.wallpaperId = def.id
                            self.state.backdropConfig.customPhoto = def.image
                            self.state.backdropConfig.backdropType = .photo
                        } else {
                            self.state.backdropConfig.backdropType = .gradient
                        }
                    }
                    self.state.onBackdropChanged?()
                    self.state.onCanvasMutated?()
                } else {
                    ToastHUDController.shared.showSimpleToast(message: "Could not isolate foreground subject", icon: "exclamationmark.triangle")
                }
            }
        }

        state.onRequestChooseBackdropPhoto = { [weak self] in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.prompt = "Use Background"
            if panel.runModal() == .OK, let url = panel.url, let loaded = NSImage(contentsOf: url) {
                self.state.backdropConfig.wallpaperId = nil
                self.state.backdropConfig.customPhoto = loaded
                self.state.backdropConfig.backdropType = .photo
                self.state.onBackdropChanged?()
                self.state.onCanvasMutated?()
            }
        }

        state.onRequestChooseBackdropGIF = { [weak self] in
            guard let self else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.gif]
            panel.allowsMultipleSelection = false
            panel.prompt = "Use Animated GIF"
            if panel.runModal() == .OK, let url = panel.url {
                let frames = ImageBackdropCompositor.loadGIFFrames(url: url)
                if !frames.isEmpty {
                    self.state.backdropConfig.customGifURL = url
                    self.state.backdropConfig.backdropType = .gif
                    self.state.gifFrames = frames
                    self.state.currentGifFrameIndex = 0
                    self.state.onBackdropChanged?()
                    self.state.onCanvasMutated?()
                } else {
                    ToastHUDController.shared.showSimpleToast(message: "Unable to decode GIF frames", icon: "exclamationmark.triangle")
                }
            }
        }

        state.onRequestCancelCrop = { [weak self] in
            guard let self else { return }
            self.state.pendingCropRect = nil
            self.state.selectTool(.pointer)
        }

        state.onRequestApplyCrop = { [weak self] in
            self?.applyPendingCrop()
        }

        state.onRequestGrabOCRText = { [weak self] in
            guard let self, let sourceImg = self.state.activeSubjectImage ?? self.state.image,
                  let cg = sourceImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            Self.runOCRAndToast(on: cg, emptyMessage: "No text found in image", on: self.window?.screen)
        }

        state.onRequestGrabOCRRegion = { [weak self] regionRect in
            guard let self, let sourceImg = self.state.activeSubjectImage ?? self.state.image else { return }
            let cropped = Self.sliceImage(sourceImg, to: regionRect)
            guard let cg = cropped.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
            Self.runOCRAndToast(on: cg, emptyMessage: "No text found in selected area", on: self.window?.screen)
        }
    }

    private static func runOCRAndToast(on cgImage: CGImage, emptyMessage: String, on screen: NSScreen?) {
        TextRecognitionService.shared.recognizeAndCopyText(from: cgImage) { result in
            if let result = result {
                NSSound.beep()
                ToastHUDController.shared.showOCRToast(text: result.text, on: screen)
            } else {
                ToastHUDController.shared.showSimpleToast(message: emptyMessage, icon: "text.magnifyingglass", on: screen)
            }
        }
    }

    private static func sliceImage(_ src: NSImage, to cropRect: CGRect) -> NSImage {
        let pixW = max(1, Int(src.representations.first?.pixelsWide ?? Int(src.size.width * 2)))
        let pixH = max(1, Int(src.representations.first?.pixelsHigh ?? Int(src.size.height * 2)))
        let sx = CGFloat(pixW) / max(1, src.size.width)
        let sy = CGFloat(pixH) / max(1, src.size.height)

        let outPixW = max(2, Int(round(cropRect.width * sx)))
        let outPixH = max(2, Int(round(cropRect.height * sy)))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let ctx = CGContext(
            data: nil,
            width: outPixW,
            height: outPixH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return src }

        let gCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gCtx

        let destRect = NSRect(x: 0, y: 0, width: outPixW, height: outPixH)
        let srcRect = NSRect(
            x: cropRect.origin.x,
            y: src.size.height - cropRect.maxY,
            width: cropRect.width,
            height: cropRect.height
        )
        src.draw(in: destRect, from: srcRect, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        guard let outCG = ctx.makeImage() else { return src }
        return NSImage(cgImage: outCG, size: NSSize(width: cropRect.width, height: cropRect.height))
    }

    private func applyPendingCrop() {
        guard let cropRect = state.pendingCropRect,
              cropRect.width >= 8, cropRect.height >= 8,
              let baseImg = state.image else {
            state.pendingCropRect = nil
            return
        }

        state.pushUndoSnapshot()

        let newBase = Self.sliceImage(baseImg, to: cropRect)
        let newCutout = state.cutoutImage.map { Self.sliceImage($0, to: cropRect) }

        let dx = -cropRect.origin.x
        let dy = -cropRect.origin.y
        state.annotations = state.annotations.map { ann in
            var shifted = ann
            shifted.startPoint = CGPoint(x: ann.startPoint.x + dx, y: ann.startPoint.y + dy)
            shifted.endPoint = CGPoint(x: ann.endPoint.x + dx, y: ann.endPoint.y + dy)
            if let cp = ann.controlPoint {
                shifted.controlPoint = CGPoint(x: cp.x + dx, y: cp.y + dy)
            }
            shifted.pathPoints = ann.pathPoints.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            return shifted
        }

        state.image = newBase
        state.imageSize = newBase.size
        state.cutoutImage = newCutout
        if let cg = newBase.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            state.pixelSize = CGSize(width: cg.width, height: cg.height)
        } else {
            state.pixelSize = newBase.size
        }
        state.pendingCropRect = nil
        state.zoomScale = 1.0
        state.panOffset = .zero
        state.selectTool(.pointer)
        state.onBackdropChanged?()
        state.onCanvasMutated?()
    }

    public func addSampleAnnotationsForTesting(selectedIndex: Int = 3) {
        let azure = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)
        let coral = NSColor(red: 255/255, green: 69/255, blue: 58/255, alpha: 1.0)
        let amber = NSColor(red: 255/255, green: 159/255, blue: 10/255, alpha: 1.0)

        state.annotations = [
            CanvasAnnotation(tool: .distance, startPoint: CGPoint(x: 80, y: 125), endPoint: CGPoint(x: 360, y: 125), color: azure),
            CanvasAnnotation(tool: .rectangle, startPoint: CGPoint(x: 80, y: 170), endPoint: CGPoint(x: 360, y: 245), color: azure, strokeWidth: 2.5, rectFillMode: .stroke, cornerRadius: 0, showSizeTag: true),
            CanvasAnnotation(tool: .rectangle, startPoint: CGPoint(x: 80, y: 280), endPoint: CGPoint(x: 360, y: 360), color: amber, strokeWidth: 2.5, rectFillMode: .tinted, cornerRadius: 8, showSizeTag: false),
            CanvasAnnotation(tool: .arrow, startPoint: CGPoint(x: 540, y: 255), endPoint: CGPoint(x: 390, y: 185), color: coral, strokeWidth: 5.5, arrowStyle: .tapered),
            CanvasAnnotation(tool: .arrow, startPoint: CGPoint(x: 410, y: 390), endPoint: CGPoint(x: 540, y: 390), color: azure, strokeWidth: 3.0, arrowStyle: .doubleEnded),
            CanvasAnnotation(tool: .text, startPoint: CGPoint(x: 558, y: 242), endPoint: CGPoint(x: 558, y: 242), text: "Fix spacing & contrast", color: .white, strokeWidth: 15, textStyle: .quoteBubble),
            CanvasAnnotation(tool: .numberedPin, startPoint: CGPoint(x: 375, y: 170), endPoint: CGPoint(x: 375, y: 170), number: 1, color: coral),
            CanvasAnnotation(tool: .blur, startPoint: CGPoint(x: 520, y: 428), endPoint: CGPoint(x: 775, y: 468))
        ]
        state.selectedAnnotationIndex = max(0, min(selectedIndex, state.annotations.count - 1))
        state.recomputeNextPin()
        state.onCanvasMutated?()
    }

    public func openInlineTextForTesting(index: Int = 5) {
        state.onOpenTextEditorAtIndex?(index)
    }

    public func configureTestingVisuals(
        frameStyle: WindowFrameStyle = .none,
        backdropType: BackdropType = .none,
        gradientId: String = "dusk",
        windowTitle: String = "",
        openBackdropPopover: Bool = false,
        openColorPopover: Bool = false,
        expandCustomColor: Bool = false,
        selectSpotlight: Bool = false,
        toolOverride: AnnotationTool? = nil,
        ocrMarquee: CGRect? = nil,
        testZoomScale: CGFloat? = nil
    ) {
        state.backdropConfig.frameStyle = frameStyle
        state.backdropConfig.backdropType = backdropType
        state.backdropConfig.gradientId = gradientId
        state.backdropConfig.windowTitle = windowTitle
        state.annotationColorPickerState.showCustomSpectrum = expandCustomColor
        if backdropType == .photo && state.backdropConfig.customPhoto == nil {
            if let def = MacWallpaperStore.shared.defaultWallpaperImageAndId() {
                state.backdropConfig.wallpaperId = def.id
                state.backdropConfig.customPhoto = def.image
            }
        }
        if backdropType == .gif {
            state.gifFrames = ImageBackdropCompositor.generateBuiltInGIFFrames(presetId: state.backdropConfig.gifPresetId)
            state.currentGifFrameIndex = 0
        }
        MacWallpaperStore.shared.preloadThumbnailsIfNeeded()
        if selectSpotlight {
            let spot = CanvasAnnotation(
                tool: .spotlight,
                startPoint: CGPoint(x: 345, y: 155),
                endPoint: CGPoint(x: 615, y: 310),
                color: state.spotlightColor,
                strokeWidth: 2.0,
                cornerRadius: 12.0
            )
            state.annotations.append(spot)
            state.selectedAnnotationIndex = state.annotations.count - 1
            state.currentTool = .spotlight
        }
        if let t = toolOverride {
            state.selectedAnnotationIndex = nil
            state.currentTool = t
        }
        if let ocrRect = ocrMarquee {
            state.pendingOCRRect = ocrRect
        }
        state.onBackdropChanged?()
        state.onCanvasMutated?()
        if let z = testZoomScale {
            state.zoomScale = z
            state.panOffset = CGPoint(x: 40, y: -20)
            state.onRequestZoomBy?(1.0)
        } else {
            state.onRequestZoomFit?()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.state.isBackdropPopoverOpen = openBackdropPopover
            self?.state.isColorPopoverOpen = openColorPopover
        }
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
            if win.firstResponder is NSTextView || win.firstResponder is NSTextField || self.state.isEditingInlineText {
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

            // 1. Command shortcuts
            if isCmd && !hasOtherMods {
                switch event.keyCode {
                case 6: // Z -> Undo / Redo
                    if isShift { self.state.redo() } else { self.state.undo() }
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
                case 51, 117: // Delete / Backspace
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
                    if !self.state.isSpacePanning { self.state.isSpacePanning = true }
                    return nil
                case 123, 124, 125, 126: // Arrow Key Precision Nudge (1px, or grid step with Shift)
                    if self.state.selectedAnnotationIndex != nil {
                        let step: CGFloat = isShift ? CGFloat(max(8, SettingsManager.shared.gridAuditUnit)) : 1.0
                        switch event.keyCode {
                        case 123: self.state.nudgeSelected(dx: -step, dy: 0)
                        case 124: self.state.nudgeSelected(dx: step, dy: 0)
                        case 125: self.state.nudgeSelected(dx: 0, dy: step)
                        case 126: self.state.nudgeSelected(dx: 0, dy: -step)
                        default: break
                        }
                        return nil
                    }
                case 36, 76: // Return -> apply pending crop cleanly
                    if self.state.currentTool == .crop && self.state.pendingCropRect != nil {
                        self.state.onRequestApplyCrop?()
                        return nil
                    }
                default:
                    break
                }
            }

            // 3. Single-letter Tool Switching (works reliably regardless of SwiftUI focus)
            if !isCmd && !hasOtherMods && !isShift {
                switch event.keyCode {
                case 9:  self.state.selectTool(.pointer); return nil      // V
                case 4:  self.state.selectTool(.pan); return nil          // H
                case 40: self.state.selectTool(.crop); return nil         // K
                case 2:  self.state.selectTool(.distance); return nil     // D
                case 0:  self.state.selectTool(.arrow); return nil        // A
                case 17: self.state.selectTool(.text); return nil         // T
                case 45: self.state.selectTool(.numberedPin); return nil  // N
                case 15: // R -> Rectangle (sharp border)
                    self.state.rectCornerRadius = 0.0
                    self.state.selectTool(.rectangle)
                    return nil
                case 8:  // C -> Rounded Card preset on Rectangle
                    self.state.rectCornerRadius = 8.0
                    self.state.selectTool(.rectangle)
                    return nil
                case 35: self.state.selectTool(.pencil); return nil       // P
                case 11: self.state.selectTool(.blur); return nil         // B
                case 1:  self.state.selectTool(.spotlight); return nil    // S
                case 5:  self.state.selectTool(.grabText); return nil     // G
                default: break
                }
            }

            return event
        }

        localKeyUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyUp) { [weak self] event in
            if event.keyCode == 49 {
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

// MARK: - Root View with Unified Compact Toolbar & Bottom Pill Inspector
public struct ScreenshotEditorRootView: View {
    @ObservedObject var state: ScreenshotEditorState
    let onClose: () -> Void

    private var isBackdropCustomized: Bool {
        state.backdropConfig.backdropType != .none ||
        state.backdropConfig.frameStyle != .none ||
        state.backdropConfig.removeSubjectBackground
    }

    private var isGIFFrameExport: Bool {
        state.backdropConfig.backdropType == .gif && !state.gifFrames.isEmpty
    }

    public var body: some View {
        VStack(spacing: 0) {
            toolbarHeader
                .frame(height: 50)
                .background(
                    Rectangle()
                        .fill(.regularMaterial)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(Color.primary.opacity(0.08))
                                .frame(height: 0.5)
                        }
                )

            ZStack(alignment: .bottom) {
                ScreenshotEditorCanvasRepresentable(state: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                // Contextual Floating Inspector Capsule along bottom edge
                DesignerInspectorBar(state: state)
                    .padding(.bottom, 16)
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            state.onRequestCopy = { copyFlattenedImage() }
            state.onRequestSave = {
                if state.backdropConfig.backdropType == .gif && !state.gifFrames.isEmpty {
                    saveGIFToDownloads()
                } else {
                    savePNGToDownloads()
                }
            }
            state.onRequestSaveGIF = { saveGIFToDownloads() }
        }
    }

    // MARK: - Toolbar Header
    private var toolbarHeader: some View {
        HStack(spacing: 12) {
            Spacer().frame(width: 72)

            // Left Cluster: Export, Pin & Undo/Redo
            HStack(spacing: 4) {
                toolbarIconButton(icon: "doc.on.doc", tooltip: "Copy image (⌘C)") {
                    copyFlattenedImage()
                }
                toolbarIconButton(
                    icon: isGIFFrameExport ? "arrow.down.circle" : "square.and.arrow.down",
                    tooltip: isGIFFrameExport ? "Save Animated GIF to Downloads (⌘S)" : "Save PNG to Downloads (⌘S)"
                ) {
                    if isGIFFrameExport {
                        saveGIFToDownloads()
                    } else {
                        savePNGToDownloads()
                    }
                }
                toolbarIconButton(
                    icon: state.isPinned ? "pin.fill" : "pin",
                    tooltip: state.isPinned ? "Unpin window (⌘P)" : "Pin above all windows (⌘P)",
                    isActive: state.isPinned
                ) {
                    state.onRequestTogglePin?()
                }

                Divider().frame(height: 16).padding(.horizontal, 4)

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

            // Center Cluster: Clean Everyday Editing Dock
            HStack(spacing: 2) {
                ForEach(AnnotationTool.primaryToolbarTools) { tool in
                    let isSelected = state.currentTool == tool
                    Button(action: {
                        state.selectTool(tool)
                    }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 13.5, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.82))
                            .frame(width: 29, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                                    .shadow(color: isSelected ? Color.black.opacity(0.08) : .clear, radius: 1.5, y: 0.5)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(isSelected ? Color.primary.opacity(0.10) : Color.clear, lineWidth: 0.5)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(tool.tooltip)
                }

                Divider().frame(height: 14).padding(.horizontal, 2)

                Menu {
                    Button {
                        state.selectTool(.grabText)
                    } label: {
                        Label("Grab Text Area (G)", systemImage: state.currentTool == .grabText ? "checkmark" : "text.viewfinder")
                    }
                    Button {
                        state.selectTool(.distance)
                    } label: {
                        Label("Measure Spacing (D)", systemImage: state.currentTool == .distance ? "checkmark" : "ruler")
                    }
                    if isGIFFrameExport {
                        Divider()
                        Button {
                            savePNGToDownloads()
                        } label: {
                            Label("Save Still Frame PNG", systemImage: "photo")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(
                            (state.currentTool == .distance || state.currentTool == .grabText)
                                ? Color(red: 10/255, green: 132/255, blue: 255/255)
                                : .primary.opacity(0.72)
                        )
                        .frame(width: 26, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill((state.currentTool == .distance || state.currentTool == .grabText) ? Color(nsColor: .controlBackgroundColor) : Color.clear)
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More tools")
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 0.5)
            )

            Spacer()

            // Right Cluster: Compact Backdrop Popover Trigger & Zoom Pill
            HStack(spacing: 8) {
                Button(action: {
                    state.isBackdropPopoverOpen.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Backdrop")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(
                        (isBackdropCustomized || state.isBackdropPopoverOpen)
                            ? Color(red: 10/255, green: 132/255, blue: 255/255)
                            : .primary.opacity(0.84)
                    )
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                (isBackdropCustomized || state.isBackdropPopoverOpen)
                                    ? Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.11)
                                    : Color.primary.opacity(0.05)
                            )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                (isBackdropCustomized || state.isBackdropPopoverOpen)
                                    ? Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.28)
                                    : Color.primary.opacity(0.08),
                                lineWidth: 0.5
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Add background gradient, photo, animated GIF, or window frame")
                .popover(isPresented: $state.isBackdropPopoverOpen, arrowEdge: .bottom) {
                    BackdropStudioPopover(state: state)
                }

                HStack(spacing: 4) {
                    if abs(state.zoomScale - 1.0) > 0.04 || hypot(state.panOffset.x, state.panOffset.y) > 8 {
                        Button(action: { state.onRequestZoomFit?() }) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundColor(.secondary)
                                .frame(width: 24, height: 28)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.primary.opacity(0.05))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Reset zoom & recenter canvas (⌘0)")
                    }

                    Menu {
                        Button("Zoom to Fit (⌘0)") { state.onRequestZoomFit?() }
                        Button("Actual Size 100% (⌘1)") { state.onRequestZoomActual?() }
                        Divider()
                        Button("Zoom In 25% (⌘+)") { state.onRequestZoomBy?(1.25) }
                        Button("Zoom Out 25% (⌘-)") { state.onRequestZoomBy?(0.80) }
                        Divider()
                        Button("Hand / Pan Tool (H)") { state.selectTool(.pan) }
                    } label: {
                        Text(verbatim: "\(Int(round(state.effectiveDisplayScale * 100)))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundColor(.primary)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .help("Two-finger swipe to pan • Pinch or ⌘+Scroll to zoom")
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.trailing, 14)
        }
    }

    private func toolbarIconButton(icon: String, tooltip: String, isActive: Bool = false, isDisabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13.5, weight: .medium))
                .foregroundColor(
                    isActive
                        ? Color(red: 10/255, green: 132/255, blue: 255/255)
                        : .primary.opacity(isDisabled ? 0.28 : 0.84)
                )
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isActive ? Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.12) : Color.clear)
                )
                .contentShape(Rectangle())
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
            ToastHUDController.shared.showSimpleToast(message: "Image copied to clipboard", icon: "doc.on.doc")
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
            ToastHUDController.shared.showSimpleToast(message: "Saved PNG to Downloads", icon: "arrow.down.doc")
        } catch {
            print("Failed to save image: \(error)")
        }
    }

    private func saveGIFToDownloads() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let dateStr = formatter.string(from: Date())
        let filename = "Canvas \(dateStr).gif"

        let downloadsUrl = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let fileUrl = downloadsUrl.appendingPathComponent(filename)

        if ScreenshotEditorCanvasNSView.exportAnimatedGIF(state: state, to: fileUrl) {
            NSSound.beep()
            ToastHUDController.shared.showSimpleToast(message: "Saved Animated GIF to Downloads", icon: "sparkles")
        } else {
            savePNGToDownloads()
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

// MARK: - Interactive Handle Kinds for Live Resize / Re-aim / Curve Bend
private enum DragHandleMode {
    case none
    case moveBody
    case startEndpoint
    case endEndpoint
    case curveControlPoint
    case rectTopLeft
    case rectTopRight
    case rectBottomLeft
    case rectBottomRight
}

// MARK: - Custom Multi-line AppKit TextView with Full Shortcut Support
private final class AnnotationTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) {
            if event.keyCode == 36 || event.keyCode == 76 {
                onCommit?()
                return true
            }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": selectAll(nil); return true
            case "c": copy(nil); return true
            case "v": paste(nil); return true
            case "x": cut(nil); return true
            case "z":
                if flags.contains(.shift) { undoManager?.redo() } else { undoManager?.undo() }
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

// MARK: - WYSIWYG Live Inline Text Callout Editor Container (with Built-in Live Drag Handle)
private final class InlineTextCalloutContainer: NSView, NSTextViewDelegate {
    var imageOrigin: CGPoint
    var scale: CGFloat
    var textStyle: TextStyle
    var inkColor: NSColor
    var fontSize: CGFloat

    let textView: AnnotationTextView
    private let placeholderLabel: NSTextField
    private var parentBoundsProvider: () -> NSRect
    private var viewOriginProvider: (CGPoint) -> NSPoint

    private let topGripReserve: CGFloat = 22
    private var cardHeightCached: CGFloat = 24
    private var tailReserveCached: CGFloat = 10
    private var gripTrackingArea: NSTrackingArea?
    private var isHoveringGrip: Bool = false
    private var isDraggingGrip: Bool = false
    private var dragLastWindowPt: NSPoint?

    var onCommit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    init(
        imageOrigin: CGPoint,
        initialText: String,
        scale: CGFloat,
        style: TextStyle,
        color: NSColor,
        fontSize: CGFloat,
        parentBoundsProvider: @escaping () -> NSRect,
        viewOriginProvider: @escaping (CGPoint) -> NSPoint
    ) {
        self.imageOrigin = imageOrigin
        self.scale = scale
        self.textStyle = style
        self.inkColor = color
        self.fontSize = fontSize
        self.parentBoundsProvider = parentBoundsProvider
        self.viewOriginProvider = viewOriginProvider

        self.textView = AnnotationTextView(frame: .zero)
        self.placeholderLabel = NSTextField(labelWithString: "Type text...")

        super.init(frame: .zero)
        self.wantsLayer = true

        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isFieldEditor = false
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        textView.string = initialText
        textView.onCommit = { [weak self] in
            guard let self else { return }
            self.onCommit?(self.textView.string)
        }
        textView.onCancel = { [weak self] in
            self?.onCancel?()
        }

        placeholderLabel.isBordered = false
        placeholderLabel.isBezeled = false
        placeholderLabel.drawsBackground = false
        placeholderLabel.isEditable = false
        placeholderLabel.isSelectable = false

        addSubview(placeholderLabel)
        addSubview(textView)

        relayout()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var gripHitRect: NSRect {
        let cy = tailReserveCached + cardHeightCached + 10
        return NSRect(x: max(0, bounds.midX - 18), y: cy - 10, width: 36, height: 20)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = gripTrackingArea { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(t)
        gripTrackingArea = t
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(gripHitRect, cursor: .openHand)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let hit = gripHitRect.contains(loc)
        if hit != isHoveringGrip {
            isHoveringGrip = hit
            needsDisplay = true
        }
        if hit { NSCursor.openHand.set() }
    }

    override func mouseExited(with event: NSEvent) {
        if isHoveringGrip && !isDraggingGrip {
            isHoveringGrip = false
            needsDisplay = true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        if gripHitRect.contains(loc) {
            isDraggingGrip = true
            dragLastWindowPt = event.locationInWindow
            NSCursor.closedHand.set()
            needsDisplay = true
            return
        }
        window?.makeFirstResponder(textView)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingGrip, let lastPt = dragLastWindowPt else { return }
        let curPt = event.locationInWindow
        let dxView = curPt.x - lastPt.x
        let dyView = curPt.y - lastPt.y
        dragLastWindowPt = curPt

        let invScale = 1.0 / max(0.1, scale)
        imageOrigin = CGPoint(x: imageOrigin.x + dxView * invScale, y: imageOrigin.y - dyView * invScale)
        relayout()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingGrip {
            isDraggingGrip = false
            dragLastWindowPt = nil
            window?.makeFirstResponder(textView)
            NSCursor.openHand.set()
            needsDisplay = true
            return
        }
        super.mouseUp(with: event)
    }

    func updateStyle(style: TextStyle, color: NSColor, fontSize: CGFloat, scale: CGFloat) {
        self.textStyle = style
        self.inkColor = color
        self.fontSize = fontSize
        self.scale = scale
        relayout()
        needsDisplay = true
    }

    func relayout() {
        let rawText = textView.string
        let sampleText = rawText.isEmpty ? "Type text..." : rawText
        let metrics = AnnotationRenderer.textMetrics(text: sampleText, fontSize: fontSize, style: textStyle, origin: imageOrigin)

        let scaledFontSize = metrics.fontSize * scale
        let font = NSFont.systemFont(ofSize: scaledFontSize, weight: textStyle == .plain ? .semibold : .medium)
        let para = NSMutableParagraphStyle()
        para.lineSpacing = max(2, round(metrics.fontSize * 0.14)) * scale

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: inkColor,
            .paragraphStyle: para
        ]
        textView.font = font
        textView.textColor = inkColor
        textView.insertionPointColor = inkColor
        textView.typingAttributes = attrs
        if let storage = textView.textStorage, storage.length > 0 {
            storage.setAttributes(attrs, range: NSRange(location: 0, length: storage.length))
        }

        let extraCaretSpace: CGFloat = 20 * scale
        let minCardW: CGFloat = 110 * scale
        let cardW = max(minCardW, metrics.bounds.width * scale + extraCaretSpace)
        let cardH = max(24 * scale, metrics.bounds.height * scale)
        let tailReserve: CGFloat = textStyle == .quoteBubble ? 10 * scale : 2

        self.cardHeightCached = cardH
        self.tailReserveCached = tailReserve

        let viewOrigin = viewOriginProvider(imageOrigin)
        let parentBounds = parentBoundsProvider()
        let x = max(12, min(viewOrigin.x, max(12, parentBounds.width - cardW - 14)))
        let y = max(12, min(viewOrigin.y - cardH - tailReserve, max(12, parentBounds.height - cardH - tailReserve - topGripReserve - 8)))

        self.frame = NSRect(x: x, y: y, width: cardW, height: cardH + tailReserve + topGripReserve)

        let padX = metrics.padX * scale
        let padY = metrics.padY * scale
        let textRect = NSRect(
            x: padX,
            y: tailReserve + padY,
            width: max(20, cardW - padX * 2),
            height: max(14, cardH - padY * 2)
        )
        textView.frame = textRect
        textView.textContainer?.containerSize = NSSize(width: textRect.width, height: 800)

        placeholderLabel.isHidden = !rawText.isEmpty
        placeholderLabel.font = font
        placeholderLabel.textColor = inkColor.withAlphaComponent(0.45)
        placeholderLabel.frame = textRect.insetBy(dx: 0, dy: -1)
        window?.invalidateCursorRects(for: self)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let tailReserve = tailReserveCached
        let cardRect = NSRect(x: 1, y: tailReserve, width: bounds.width - 2, height: cardHeightCached - 1)
        let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.90)

        ctx.saveGState()
        switch textStyle {
        case .plain:
            let bg = inkColor.relativeLuminance > 0.45
                ? NSColor.black.withAlphaComponent(0.28)
                : NSColor.white.withAlphaComponent(0.42)
            let p = NSBezierPath(roundedRect: cardRect, xRadius: 6 * scale, yRadius: 6 * scale)
            bg.setFill()
            p.fill()
            accent.setStroke()
            p.lineWidth = 1.2
            p.stroke()

        case .card:
            let bg = inkColor.relativeLuminance > 0.45
                ? NSColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 0.94)
                : NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 0.97)
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: NSColor.black.withAlphaComponent(0.20).cgColor)
            let p = NSBezierPath(roundedRect: cardRect, xRadius: 8 * scale, yRadius: 8 * scale)
            bg.setFill()
            p.fill()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            accent.setStroke()
            p.lineWidth = 1.25
            p.stroke()

        case .quoteBubble:
            let bg = inkColor.relativeLuminance > 0.45
                ? NSColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 0.94)
                : NSColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 0.97)
            let bubblePath = AnnotationRenderer.speechBubblePath(rect: cardRect, cornerRadius: 9 * scale, tailWidth: 12 * scale, tailHeight: 8.5 * scale)
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 10, color: NSColor.black.withAlphaComponent(0.22).cgColor)
            bg.setFill()
            bubblePath.fill()
            ctx.setShadow(offset: .zero, blur: 0, color: nil)
            accent.setStroke()
            bubblePath.lineWidth = 1.25
            bubblePath.stroke()
        }
        ctx.restoreGState()

        // Live Drag Grip Pill attached cleanly above active text editor
        let gripCenter = CGPoint(x: bounds.midX, y: tailReserve + cardHeightCached + 10)
        AnnotationRenderer.drawDragGripPill(center: gripCenter, isHighlighted: isHoveringGrip || isDraggingGrip, in: ctx)
    }

    func textDidChange(_ notification: Notification) {
        relayout()
        needsDisplay = true
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                return false
            }
            onCommit?(textView.string)
            return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            onCancel?()
            return true
        }
        return false
    }
}

// MARK: - Interactive AppKit Vector Canvas
public class ScreenshotEditorCanvasNSView: NSView {
    private var state: ScreenshotEditorState
    private var pixelBuffer: PixelInspectBuffer?
    private var cachedImageID: ObjectIdentifier?
    private var trackingAreaRef: NSTrackingArea?

    private var dragStartImagePoint: CGPoint?
    private var activeHandleMode: DragHandleMode = .none
    private var lastPanViewPoint: NSPoint?
    private var isPanningCanvas: Bool = false
    private var hasPushedDragUndo: Bool = false
    private var liveAnnotation: CanvasAnnotation?
    private var hoverSmartSpan: PixelInspectBuffer.SmartSpan?
    private var activeSnapGuides: (horizontalY: [CGFloat], verticalX: [CGFloat]) = ([], [])

    private var inlineTextContainer: InlineTextCalloutContainer?
    private var editingAnnotationIndex: Int?
    private var hoveredAnnotationIndex: Int?
    private var isHoveringDragGrip: Bool = false
    private var pendingTextClickIndex: Int?
    private var pendingPinClickIndex: Int?
    private var pendingClickDownViewPoint: NSPoint?
    private var didExceedDragThreshold: Bool = false

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var cachedBlurredNSImage: NSImage?
    private var cachedBlurredImageID: ObjectIdentifier?
    private var gifTimer: Timer?

    deinit {
        gifTimer?.invalidate()
    }

    public init(state: ScreenshotEditorState) {
        self.state = state
        super.init(frame: .zero)
        self.wantsLayer = true
        self.clipsToBounds = true
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
            self.applyZoom(factor: factor, anchoredAtViewPoint: NSPoint(x: self.bounds.midX, y: self.bounds.midY))
        }
        state.onRequestZoomFit = { [weak self] in self?.resetZoomToFit() }
        state.onRequestZoomActual = { [weak self] in self?.zoomToActual100() }
        state.onCancelTextOrSelection = { [weak self] in self?.cancelActiveInteractions() }
        state.onCommitInlineText = { [weak self] in self?.commitInlineTextIfNeeded() }
        state.onLivePropertyChanged = { [weak self] in self?.syncInlineTextStyleFromState() }
        state.onOpenTextEditorAtIndex = { [weak self] idx in self?.beginEditingTextAnnotation(at: idx) }
        state.onCanvasMutated = { [weak self] in self?.needsDisplay = true }
        state.onBackdropChanged = { [weak self] in
            self?.syncGIFTimer()
            self?.updateEffectiveDisplayScaleTelemetry()
            self?.needsDisplay = true
        }
        syncGIFTimer()
    }

    private func syncGIFTimer() {
        gifTimer?.invalidate()
        gifTimer = nil
        guard state.backdropConfig.backdropType == .gif, !state.gifFrames.isEmpty else { return }
        let idx = state.currentGifFrameIndex % state.gifFrames.count
        let delay = max(0.035, state.gifFrames[idx].duration)
        gifTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.state.backdropConfig.backdropType == .gif, !self.state.gifFrames.isEmpty else { return }
                self.state.currentGifFrameIndex = (self.state.currentGifFrameIndex + 1) % self.state.gifFrames.count
                self.needsDisplay = true
                self.syncGIFTimer()
            }
        }
    }

    private func updateCaches() {
        guard let img = state.activeSubjectImage ?? state.image else {
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
            self.cachedBlurredNSImage = Self.buildPixellatedImage(from: img)
            self.cachedBlurredImageID = imgID
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
        applyActiveCursor()
    }

    private func applyActiveCursor() {
        if isPanningCanvas || activeHandleMode == .moveBody || didExceedDragThreshold {
            NSCursor.closedHand.set()
            return
        }
        if state.isSpacePanning || state.currentTool == .pan || isHoveringDragGrip {
            NSCursor.openHand.set()
            return
        }
        switch state.currentTool {
        case .pointer:     NSCursor.arrow.set()
        case .pan:         NSCursor.openHand.set()
        case .text:        NSCursor.iBeam.set()
        case .numberedPin: NSCursor.pointingHand.set()
        default:           NSCursor.crosshair.set()
        }
    }

    // MARK: - Coordinate Mapping & Zoom Math (Aware of Frame, Cutout & Backdrop Padding)
    private func compositeLayout() -> ImageBackdropCompositor.CompositeLayout {
        let subSize = state.activeSubjectImage?.size ?? state.imageSize
        return ImageBackdropCompositor.layout(forSubjectSize: subSize, config: state.backdropConfig, hasEmbeddedShadow: state.hasEmbeddedShadow)
    }

    private func baseFitScale() -> CGFloat {
        let layout = compositeLayout()
        guard layout.canvasSize.width > 0 && layout.canvasSize.height > 0 else { return 1.0 }
        guard bounds.width > 80 && bounds.height > 80 else { return 1.0 }
        let availW = bounds.width - 48
        let availH = bounds.height - 84 // Clear breathing room above bottom contextual bar
        return min(min(availW / layout.canvasSize.width, availH / layout.canvasSize.height), 1.0)
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

    private func canvasDisplayRect() -> NSRect {
        let layout = compositeLayout()
        let scale = effectiveScale()
        let w = layout.canvasSize.width * scale
        let h = layout.canvasSize.height * scale
        let cx = bounds.midX + state.panOffset.x
        let cy = bounds.midY + state.panOffset.y + 12 // Lifted gently clear of bottom bar
        return NSRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }

    private func imageDisplayRect() -> NSRect {
        let layout = compositeLayout()
        let canvasR = canvasDisplayRect()
        let scale = effectiveScale()
        return NSRect(
            x: canvasR.origin.x + layout.subjectRect.origin.x * scale,
            y: canvasR.origin.y + layout.subjectRect.origin.y * scale,
            width: layout.subjectRect.width * scale,
            height: layout.subjectRect.height * scale
        )
    }

    private func viewPointToImagePointUnclamped(_ viewPt: NSPoint) -> CGPoint? {
        let r = imageDisplayRect()
        guard r.width > 0 && r.height > 0, let img = state.activeSubjectImage ?? state.image else { return nil }
        let relX = (viewPt.x - r.origin.x) / r.width
        let relY = (viewPt.y - r.origin.y) / r.height
        return CGPoint(x: relX * img.size.width, y: (1.0 - relY) * img.size.height)
    }

    private func viewPointToImagePoint(_ viewPt: NSPoint) -> CGPoint? {
        guard let pt = viewPointToImagePointUnclamped(viewPt), let img = state.activeSubjectImage ?? state.image else { return nil }
        guard pt.x >= 0 && pt.x <= img.size.width && pt.y >= 0 && pt.y <= img.size.height else { return nil }
        return pt
    }

    private func viewPointToClampedImagePoint(_ viewPt: NSPoint) -> CGPoint? {
        guard let pt = viewPointToImagePointUnclamped(viewPt), let img = state.activeSubjectImage ?? state.image else { return nil }
        return CGPoint(x: max(0, min(img.size.width, pt.x)), y: max(0, min(img.size.height, pt.y)))
    }

    private func imagePointToViewPoint(_ imgPt: CGPoint) -> NSPoint {
        let r = imageDisplayRect()
        guard let img = state.activeSubjectImage ?? state.image, img.size.width > 0 && img.size.height > 0 else { return .zero }
        let relX = imgPt.x / img.size.width
        let relY = 1.0 - (imgPt.y / img.size.height)
        return NSPoint(x: r.origin.x + relX * r.width, y: r.origin.y + relY * r.height)
    }

    // MARK: - Zoom & Pan Gestures (Cursor-Anchored)
    private func applyZoom(factor: CGFloat, anchoredAtViewPoint anchor: NSPoint) {
        let oldEff = effectiveScale()
        guard oldEff > 0 else { return }

        let oldCenterX = bounds.midX + state.panOffset.x
        let oldCenterY = bounds.midY + state.panOffset.y + 12
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
            state.panOffset = .zero
            if abs(newZoomScale - 1.0) < 0.05 { state.zoomScale = 1.0 }
        } else {
            state.panOffset = CGPoint(x: newCenterX - bounds.midX, y: newCenterY - (bounds.midY + 12))
        }
        state.effectiveDisplayScale = effectiveScale()
        syncInlineEditorScaleAndPosition()
        needsDisplay = true
    }

    private func resetZoomToFit() {
        state.zoomScale = 1.0
        state.panOffset = .zero
        state.effectiveDisplayScale = effectiveScale()
        syncInlineEditorScaleAndPosition()
        needsDisplay = true
    }

    private func zoomToActual100() {
        let fit = baseFitScale()
        state.zoomScale = fit > 0 ? (1.0 / fit) : 1.0
        state.panOffset = .zero
        state.effectiveDisplayScale = effectiveScale()
        syncInlineEditorScaleAndPosition()
        needsDisplay = true
    }

    private func clampPanOffset() {
        let layout = compositeLayout()
        let scale = effectiveScale()
        let scaledW = layout.canvasSize.width * scale
        let scaledH = layout.canvasSize.height * scale
        let maxX = max(140, scaledW * 0.60 + bounds.width * 0.25)
        let maxY = max(120, scaledH * 0.60 + bounds.height * 0.25)
        state.panOffset.x = max(-maxX, min(maxX, state.panOffset.x))
        state.panOffset.y = max(-maxY, min(maxY, state.panOffset.y))
    }

    override public func scrollWheel(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Figma-standard navigation: ⌘+Scroll or ⌃+Scroll zooms toward cursor; two-finger swipe pans freely in 2D!
        if mods.contains(.command) || mods.contains(.control) {
            if abs(event.scrollingDeltaY) > 0.05 {
                let sensitivity: CGFloat = event.hasPreciseScrollingDeltas ? 0.010 : 0.08
                let factor = exp(event.scrollingDeltaY * sensitivity)
                applyZoom(factor: factor, anchoredAtViewPoint: loc)
            }
            return
        }

        let mul: CGFloat = event.hasPreciseScrollingDeltas ? 1.0 : 12.0
        let dx = event.scrollingDeltaX * mul
        let dy = event.scrollingDeltaY * mul
        if abs(dx) > 0.05 || abs(dy) > 0.05 {
            state.panOffset.x += dx
            state.panOffset.y -= dy
            clampPanOffset()
            syncInlineEditorScaleAndPosition()
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

    // MARK: - Mouse Hover, Handle Detection, Drawing, Dragging
    override public func mouseMoved(with event: NSEvent) {
        refreshHoverTelemetry(atViewPoint: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override public func mouseExited(with event: NSEvent) {
        hoverSmartSpan = nil
        hoveredAnnotationIndex = nil
        isHoveringDragGrip = false
        needsDisplay = true
    }

    private func refreshHoverTelemetry(atViewPoint viewLoc: NSPoint, modifiers: NSEvent.ModifierFlags) {
        let gripHit = hitTestDragGrip(atViewPoint: viewLoc)
        isHoveringDragGrip = (gripHit != nil)

        guard let imgPt = viewPointToImagePoint(viewLoc) else {
            hoverSmartSpan = nil
            hoveredAnnotationIndex = gripHit
            applyActiveCursor()
            needsDisplay = true
            return
        }

        hoveredAnnotationIndex = gripHit ?? topAnnotationIndex(at: imgPt)

        if let sample = pixelBuffer?.sampleColor(at: imgPt) {
            state.hoveredHexColor = sample.hex
        }

        let isOptionHeld = modifiers.contains(.option)
        let showSmart = (state.currentTool == .distance) || (SettingsManager.shared.enableSmartDistance && isOptionHeld)
        if showSmart && liveAnnotation == nil && !isHoveringDragGrip {
            hoverSmartSpan = pixelBuffer?.raycastSpan(at: imgPt)
        } else {
            hoverSmartSpan = nil
        }
        applyActiveCursor()
        needsDisplay = true
    }

    override public func otherMouseDown(with event: NSEvent) {
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
        let viewLoc = convert(event.locationInWindow, from: nil)

        // If clicking outside an open inline text callout, commit text cleanly first without opening another empty box!
        if let activeEditor = inlineTextContainer {
            if !activeEditor.frame.contains(viewLoc) {
                window?.makeFirstResponder(self)
                commitInlineTextIfNeeded()
                needsDisplay = true
                return
            }
            return
        }

        window?.makeFirstResponder(self)
        pendingTextClickIndex = nil
        pendingPinClickIndex = nil
        pendingClickDownViewPoint = nil
        didExceedDragThreshold = false

        if state.isSpacePanning || state.currentTool == .pan {
            isPanningCanvas = true
            lastPanViewPoint = viewLoc
            NSCursor.closedHand.set()
            return
        }

        // Universal Floating Drag Grip Handle works on ANY hovered/selected layer across ALL tools!
        if let gripIdx = hitTestDragGrip(atViewPoint: viewLoc),
           let rawPt = viewPointToImagePointUnclamped(viewLoc) {
            state.selectedAnnotationIndex = gripIdx
            hoveredAnnotationIndex = gripIdx
            activeHandleMode = .moveBody
            dragStartImagePoint = rawPt
            hasPushedDragUndo = false
            NSCursor.closedHand.set()
            needsDisplay = true
            return
        }

        guard let imgPt = viewPointToClampedImagePoint(viewLoc) else {
            if state.currentTool == .pointer {
                isPanningCanvas = true
                lastPanViewPoint = viewLoc
                state.selectedAnnotationIndex = nil
            }
            return
        }

        // Check handle hits on currently selected annotation first (even when another draw tool is active!)
        if let selIdx = state.selectedAnnotationIndex, selIdx < state.annotations.count {
            let handleHit = hitTestHandle(atViewPoint: viewLoc, annotation: state.annotations[selIdx])
            if handleHit != .none {
                // Double-clicking curve midpoint resets curve straight cleanly
                if case .curveControlPoint = handleHit, event.clickCount == 2 {
                    state.pushUndoSnapshot()
                    state.annotations[selIdx].controlPoint = nil
                    needsDisplay = true
                    return
                }
                activeHandleMode = handleHit
                dragStartImagePoint = imgPt
                hasPushedDragUndo = false
                needsDisplay = true
                return
            }
        }

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
                activeHandleMode = .moveBody
                dragStartImagePoint = viewPointToImagePointUnclamped(viewLoc) ?? imgPt
                hasPushedDragUndo = false
                NSCursor.closedHand.set()
            } else {
                state.selectedAnnotationIndex = nil
                activeHandleMode = .none
                if state.zoomScale > 1.05 {
                    isPanningCanvas = true
                    lastPanViewPoint = viewLoc
                }
            }

        case .numberedPin:
            if let hitIdx = topAnnotationIndex(at: imgPt), state.annotations[hitIdx].tool == .numberedPin {
                state.selectedAnnotationIndex = hitIdx
                pendingPinClickIndex = hitIdx
                pendingClickDownViewPoint = viewLoc
                dragStartImagePoint = viewPointToImagePointUnclamped(viewLoc) ?? imgPt
                hasPushedDragUndo = false
            } else {
                let pin = CanvasAnnotation(
                    tool: .numberedPin,
                    startPoint: imgPt,
                    endPoint: imgPt,
                    number: state.nextPinNumber,
                    color: state.pinColor
                )
                state.addAnnotation(pin)
            }

        case .text:
            // Click-to-edit OR drag-to-move existing text directly without switching to Pointer!
            if let hitIdx = topAnnotationIndex(at: imgPt), state.annotations[hitIdx].tool == .text {
                state.selectedAnnotationIndex = hitIdx
                pendingTextClickIndex = hitIdx
                pendingClickDownViewPoint = viewLoc
                dragStartImagePoint = viewPointToImagePointUnclamped(viewLoc) ?? imgPt
                hasPushedDragUndo = false
            } else {
                showInlineTextEditor(atViewPoint: viewLoc, imagePoint: imgPt, initialText: "")
            }

        case .pencil:
            dragStartImagePoint = imgPt
            var ann = CanvasAnnotation(
                tool: .pencil,
                startPoint: imgPt,
                endPoint: imgPt,
                color: state.highlighterColor,
                strokeWidth: state.highlighterWidth
            )
            ann.pathPoints = [imgPt]
            liveAnnotation = ann

        case .distance:
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
            liveAnnotation = CanvasAnnotation(tool: .distance, startPoint: startPt, endPoint: startPt, color: state.rulerColor)

        case .arrow:
            dragStartImagePoint = imgPt
            liveAnnotation = CanvasAnnotation(
                tool: .arrow,
                startPoint: imgPt,
                endPoint: imgPt,
                color: state.arrowColor,
                strokeWidth: state.arrowWidth,
                arrowStyle: state.arrowStyle
            )

        case .rectangle:
            dragStartImagePoint = imgPt
            liveAnnotation = CanvasAnnotation(
                tool: .rectangle,
                startPoint: imgPt,
                endPoint: imgPt,
                color: state.rectColor,
                strokeWidth: state.rectWidth,
                rectFillMode: state.rectFillMode,
                cornerRadius: state.rectCornerRadius,
                showSizeTag: state.rectShowSizeTag
            )

        case .blur:
            dragStartImagePoint = imgPt
            liveAnnotation = CanvasAnnotation(tool: .blur, startPoint: imgPt, endPoint: imgPt)

        case .spotlight:
            dragStartImagePoint = imgPt
            liveAnnotation = CanvasAnnotation(
                tool: .spotlight,
                startPoint: imgPt,
                endPoint: imgPt,
                color: state.spotlightColor,
                strokeWidth: 2.0,
                cornerRadius: 12.0
            )

        case .crop:
            dragStartImagePoint = imgPt
            state.pendingCropRect = CGRect(origin: imgPt, size: .zero)

        case .grabText:
            dragStartImagePoint = imgPt
            state.pendingOCRRect = CGRect(origin: imgPt, size: .zero)

        case .pan:
            isPanningCanvas = true
            lastPanViewPoint = viewLoc
            NSCursor.closedHand.set()
        }

        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        let viewLoc = convert(event.locationInWindow, from: nil)

        if isPanningCanvas, let last = lastPanViewPoint {
            state.panOffset.x += (viewLoc.x - last.x)
            state.panOffset.y += (viewLoc.y - last.y)
            clampPanOffset()
            lastPanViewPoint = viewLoc
            syncInlineEditorScaleAndPosition()
            needsDisplay = true
            return
        }

        // Convert pending text or pin body click into smooth moveBody drag once movement exceeds 3.5pt
        if let downPt = pendingClickDownViewPoint,
           let targetIdx = pendingTextClickIndex ?? pendingPinClickIndex,
           targetIdx < state.annotations.count,
           !didExceedDragThreshold {
            if hypot(viewLoc.x - downPt.x, viewLoc.y - downPt.y) > 3.5 {
                didExceedDragThreshold = true
                activeHandleMode = .moveBody
                NSCursor.closedHand.set()
            } else {
                return
            }
        }

        guard let clampedImgPt = viewPointToClampedImagePoint(viewLoc) else { return }
        let moveImgPt = viewPointToImagePointUnclamped(viewLoc) ?? clampedImgPt

        // Handle Manipulation of Selected Annotation
        if let idx = state.selectedAnnotationIndex, idx < state.annotations.count, activeHandleMode != .none, let start = dragStartImagePoint {
            if !hasPushedDragUndo {
                state.pushUndoSnapshot()
                hasPushedDragUndo = true
            }
            let targetPt = (activeHandleMode == .moveBody) ? moveImgPt : clampedImgPt
            applyHandleDrag(mode: activeHandleMode, index: idx, from: start, to: targetPt, modifiers: event.modifierFlags)
            dragStartImagePoint = targetPt
            needsDisplay = true
            return
        }

        let currentImgPt = clampedImgPt

        if state.currentTool == .crop, let start = dragStartImagePoint {
            state.pendingCropRect = CGRect(
                x: min(start.x, currentImgPt.x),
                y: min(start.y, currentImgPt.y),
                width: abs(currentImgPt.x - start.x),
                height: abs(currentImgPt.y - start.y)
            )
            needsDisplay = true
            return
        }

        if state.currentTool == .grabText, let start = dragStartImagePoint {
            state.pendingOCRRect = CGRect(
                x: min(start.x, currentImgPt.x),
                y: min(start.y, currentImgPt.y),
                width: abs(currentImgPt.x - start.x),
                height: abs(currentImgPt.y - start.y)
            )
            needsDisplay = true
            return
        }

        // Drawing New Annotation Live Preview
        if var live = liveAnnotation, let start = dragStartImagePoint {
            var end = currentImgPt
            activeSnapGuides = ([], [])

            if live.tool == .distance {
                // Strictly Horizontal OR Vertical — NEVER diagonal
                let dx = abs(end.x - start.x)
                let dy = abs(end.y - start.y)
                if dx >= dy {
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
            } else if (live.tool == .rectangle || live.tool == .spotlight) && event.modifierFlags.contains(.shift) {
                // Shift locks aspect ratio 1:1 square cleanly like Figma
                let dx = end.x - start.x
                let dy = end.y - start.y
                let side = max(abs(dx), abs(dy))
                end.x = start.x + (dx >= 0 ? side : -side)
                end.y = start.y + (dy >= 0 ? side : -side)
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

        if state.currentTool == .crop {
            if let r = state.pendingCropRect, (r.width < 10 || r.height < 10) {
                state.pendingCropRect = nil
            }
            dragStartImagePoint = nil
            needsDisplay = true
            return
        }

        if state.currentTool == .grabText {
            let chosen = state.pendingOCRRect
            state.pendingOCRRect = nil
            dragStartImagePoint = nil
            needsDisplay = true
            if let r = chosen, r.width >= 10, r.height >= 10 {
                state.onRequestGrabOCRRegion?(r)
            }
            return
        }

        if let tapTextIdx = pendingTextClickIndex, !didExceedDragThreshold, tapTextIdx < state.annotations.count {
            pendingTextClickIndex = nil
            pendingPinClickIndex = nil
            pendingClickDownViewPoint = nil
            didExceedDragThreshold = false
            activeHandleMode = .none
            hasPushedDragUndo = false
            dragStartImagePoint = nil
            beginEditingTextAnnotation(at: tapTextIdx)
            return
        }

        pendingTextClickIndex = nil
        pendingPinClickIndex = nil
        pendingClickDownViewPoint = nil
        didExceedDragThreshold = false

        activeSnapGuides = ([], [])
        hasPushedDragUndo = false
        activeHandleMode = .none

        if var live = liveAnnotation {
            let dx = abs(live.endPoint.x - live.startPoint.x)
            let dy = abs(live.endPoint.y - live.startPoint.y)

            if dx > 4 || dy > 4 || (live.tool == .pencil && live.pathPoints.count > 2) {
                state.addAnnotation(live)
            } else if live.tool == .distance, let span = pixelBuffer?.raycastSpan(at: live.startPoint) {
                // One-click measure only when tightly bounded by UI element edges (8px..360px)
                let hDist = span.horizontalDistance
                let vDist = span.verticalDistance
                let imgW = state.imageSize.width
                let imgH = state.imageSize.height

                let useVertical = event.modifierFlags.contains(.shift)
                    ? (vDist > hDist)
                    : (vDist >= 8 && vDist <= 360 && (hDist > 360 || vDist <= hDist))

                if useVertical && vDist >= 8 && vDist <= 360 && CGFloat(vDist) < imgH * 0.85 {
                    live.startPoint = CGPoint(x: live.startPoint.x, y: span.topY)
                    live.endPoint = CGPoint(x: live.startPoint.x, y: span.bottomY)
                    state.addAnnotation(live)
                } else if hDist >= 8 && hDist <= 360 && CGFloat(hDist) < imgW * 0.85 {
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

    private func applyHandleDrag(mode: DragHandleMode, index idx: Int, from prev: CGPoint, to cur: CGPoint, modifiers: NSEvent.ModifierFlags) {
        activeSnapGuides = ([], [])
        switch mode {
        case .none:
            break

        case .moveBody:
            let dx = cur.x - prev.x
            let dy = cur.y - prev.y
            state.annotations[idx].startPoint.x += dx
            state.annotations[idx].startPoint.y += dy
            state.annotations[idx].endPoint.x += dx
            state.annotations[idx].endPoint.y += dy
            if let cp = state.annotations[idx].controlPoint {
                state.annotations[idx].controlPoint = CGPoint(x: cp.x + dx, y: cp.y + dy)
            }
            for i in 0..<state.annotations[idx].pathPoints.count {
                state.annotations[idx].pathPoints[i].x += dx
                state.annotations[idx].pathPoints[i].y += dy
            }

        case .startEndpoint:
            if state.annotations[idx].tool == .distance {
                let isHoriz = abs(state.annotations[idx].endPoint.x - state.annotations[idx].startPoint.x) >= abs(state.annotations[idx].endPoint.y - state.annotations[idx].startPoint.y)
                if isHoriz {
                    var nx = cur.x
                    if !modifiers.contains(.command), let sX = pixelBuffer?.snapCoordinate(near: CGPoint(x: nx, y: state.annotations[idx].startPoint.y), horizontal: true) {
                        nx = sX
                        activeSnapGuides.verticalX.append(nx)
                    }
                    state.annotations[idx].startPoint.x = nx
                } else {
                    var ny = cur.y
                    if !modifiers.contains(.command), let sY = pixelBuffer?.snapCoordinate(near: CGPoint(x: state.annotations[idx].startPoint.x, y: ny), horizontal: false) {
                        ny = sY
                        activeSnapGuides.horizontalY.append(ny)
                    }
                    state.annotations[idx].startPoint.y = ny
                }
            } else {
                state.annotations[idx].startPoint = cur
            }

        case .endEndpoint:
            if state.annotations[idx].tool == .distance {
                let isHoriz = abs(state.annotations[idx].endPoint.x - state.annotations[idx].startPoint.x) >= abs(state.annotations[idx].endPoint.y - state.annotations[idx].startPoint.y)
                if isHoriz {
                    var nx = cur.x
                    if !modifiers.contains(.command), let sX = pixelBuffer?.snapCoordinate(near: CGPoint(x: nx, y: state.annotations[idx].endPoint.y), horizontal: true) {
                        nx = sX
                        activeSnapGuides.verticalX.append(nx)
                    }
                    state.annotations[idx].endPoint.x = nx
                } else {
                    var ny = cur.y
                    if !modifiers.contains(.command), let sY = pixelBuffer?.snapCoordinate(near: CGPoint(x: state.annotations[idx].endPoint.x, y: ny), horizontal: false) {
                        ny = sY
                        activeSnapGuides.horizontalY.append(ny)
                    }
                    state.annotations[idx].endPoint.y = ny
                }
            } else {
                state.annotations[idx].endPoint = cur
            }

        case .curveControlPoint:
            // Adjust quadratic bezier curve handle so arrow bends naturally through dragged cursor
            let mid = CGPoint(
                x: (state.annotations[idx].startPoint.x + state.annotations[idx].endPoint.x) * 0.5,
                y: (state.annotations[idx].startPoint.y + state.annotations[idx].endPoint.y) * 0.5
            )
            // Control point sits 2x offset from chord midpoint so curve peak passes smoothly through `cur`
            state.annotations[idx].controlPoint = CGPoint(x: 2 * cur.x - mid.x, y: 2 * cur.y - mid.y)

        case .rectTopLeft, .rectTopRight, .rectBottomLeft, .rectBottomRight:
            var minX = min(state.annotations[idx].startPoint.x, state.annotations[idx].endPoint.x)
            var maxX = max(state.annotations[idx].startPoint.x, state.annotations[idx].endPoint.x)
            var minY = min(state.annotations[idx].startPoint.y, state.annotations[idx].endPoint.y)
            var maxY = max(state.annotations[idx].startPoint.y, state.annotations[idx].endPoint.y)

            switch mode {
            case .rectTopLeft:     minX = min(cur.x, maxX - 8); minY = min(cur.y, maxY - 8)
            case .rectTopRight:    maxX = max(cur.x, minX + 8); minY = min(cur.y, maxY - 8)
            case .rectBottomLeft:  minX = min(cur.x, maxX - 8); maxY = max(cur.y, minY + 8)
            case .rectBottomRight: maxX = max(cur.x, minX + 8); maxY = max(cur.y, minY + 8)
            default: break
            }
            state.annotations[idx].startPoint = CGPoint(x: minX, y: minY)
            state.annotations[idx].endPoint = CGPoint(x: maxX, y: maxY)
        }
    }

    private func cancelActiveInteractions() {
        if inlineTextContainer != nil {
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

    // MARK: - Live WYSIWYG Inline Text Input (Multi-line + Real-Time Inspector Sync)
    private func beginEditingTextAnnotation(at index: Int) {
        guard index >= 0 && index < state.annotations.count else { return }
        let ann = state.annotations[index]
        state.selectedAnnotationIndex = index
        showInlineTextEditor(
            imagePoint: ann.startPoint,
            initialText: ann.text,
            fontColor: ann.color,
            fontSize: ann.strokeWidth > 8 ? ann.strokeWidth : state.textSize,
            textStyle: ann.textStyle,
            editingIndex: index
        )
        needsDisplay = true
    }

    private func showInlineTextEditor(
        atViewPoint viewPoint: NSPoint? = nil,
        imagePoint: CGPoint,
        initialText: String,
        fontColor: NSColor? = nil,
        fontSize: CGFloat? = nil,
        textStyle: TextStyle? = nil,
        editingIndex: Int? = nil
    ) {
        dismissInlineTextField()
        self.editingAnnotationIndex = editingIndex
        let activeColor = fontColor ?? state.textColor
        let activeSize = fontSize ?? state.textSize
        let activeStyle = textStyle ?? state.textStyle

        let container = InlineTextCalloutContainer(
            imageOrigin: imagePoint,
            initialText: initialText,
            scale: effectiveScale(),
            style: activeStyle,
            color: activeColor,
            fontSize: activeSize,
            parentBoundsProvider: { [unowned self] in self.bounds },
            viewOriginProvider: { [unowned self] pt in self.imagePointToViewPoint(pt) }
        )
        container.onCommit = { [weak self] _ in
            self?.commitInlineTextIfNeeded()
            if let self {
                self.window?.makeFirstResponder(self)
            }
        }
        container.onCancel = { [weak self] in
            self?.dismissInlineTextField()
            if let self {
                self.window?.makeFirstResponder(self)
                self.needsDisplay = true
            }
        }

        addSubview(container)
        self.inlineTextContainer = container
        self.dragStartImagePoint = imagePoint
        state.isEditingInlineText = true

        window?.makeFirstResponder(container.textView)
        if !initialText.isEmpty {
            container.textView.setSelectedRange(NSRange(location: initialText.count, length: 0))
        }
    }

    private func syncInlineEditorScaleAndPosition() {
        guard let container = inlineTextContainer else { return }
        container.scale = effectiveScale()
        container.relayout()
        container.needsDisplay = true
    }

    private func syncInlineTextStyleFromState() {
        guard let container = inlineTextContainer else { return }
        let targetColor: NSColor
        let targetSize: CGFloat
        let targetStyle: TextStyle

        if let editIdx = editingAnnotationIndex, editIdx < state.annotations.count {
            targetColor = state.annotations[editIdx].color
            targetSize = state.annotations[editIdx].strokeWidth
            targetStyle = state.annotations[editIdx].textStyle
        } else {
            targetColor = state.textColor
            targetSize = state.textSize
            targetStyle = state.textStyle
        }

        container.updateStyle(style: targetStyle, color: targetColor, fontSize: targetSize, scale: effectiveScale())

        if let win = self.window, win.isKeyWindow, !state.isColorPopoverOpen {
            DispatchQueue.main.async { [weak self] in
                guard let self, let tv = self.inlineTextContainer?.textView else { return }
                if !self.state.isColorPopoverOpen && win.firstResponder !== tv {
                    win.makeFirstResponder(tv)
                }
            }
        }
    }

    private func commitInlineTextIfNeeded() {
        guard let container = inlineTextContainer else { return }
        let text = container.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)

        if let editIdx = editingAnnotationIndex, editIdx < state.annotations.count {
            let movedOrigin = container.imageOrigin != state.annotations[editIdx].startPoint
            if text.isEmpty {
                state.pushUndoSnapshot()
                state.annotations.remove(at: editIdx)
                state.selectedAnnotationIndex = nil
            } else if text != state.annotations[editIdx].text || movedOrigin {
                state.pushUndoSnapshot()
                state.annotations[editIdx].text = text
                state.annotations[editIdx].startPoint = container.imageOrigin
                state.annotations[editIdx].endPoint = container.imageOrigin
                state.selectedAnnotationIndex = editIdx
            } else {
                state.selectedAnnotationIndex = editIdx
            }
        } else if !text.isEmpty {
            var ann = CanvasAnnotation(
                tool: .text,
                startPoint: container.imageOrigin,
                endPoint: container.imageOrigin,
                color: container.inkColor,
                strokeWidth: container.fontSize,
                textStyle: container.textStyle
            )
            ann.text = text
            state.addAnnotation(ann)
        }

        dismissInlineTextField()
        needsDisplay = true
    }

    private func dismissInlineTextField() {
        editingAnnotationIndex = nil
        inlineTextContainer?.removeFromSuperview()
        inlineTextContainer = nil
        state.isEditingInlineText = false
    }

    // MARK: - Handle & Body Hit Testing
    private func hitTestHandle(atViewPoint viewPt: NSPoint, annotation ann: CanvasAnnotation) -> DragHandleMode {
        let hitRadius: CGFloat = 9.0
        switch ann.tool {
        case .arrow:
            let vEnd = imagePointToViewPoint(ann.endPoint)
            let vStart = imagePointToViewPoint(ann.startPoint)
            let vMid = arrowMidpointView(ann)
            if hypot(viewPt.x - vEnd.x, viewPt.y - vEnd.y) <= hitRadius { return .endEndpoint }
            if hypot(viewPt.x - vStart.x, viewPt.y - vStart.y) <= hitRadius { return .startEndpoint }
            if hypot(viewPt.x - vMid.x, viewPt.y - vMid.y) <= hitRadius { return .curveControlPoint }

        case .distance:
            let vEnd = imagePointToViewPoint(ann.endPoint)
            let vStart = imagePointToViewPoint(ann.startPoint)
            if hypot(viewPt.x - vEnd.x, viewPt.y - vEnd.y) <= hitRadius { return .endEndpoint }
            if hypot(viewPt.x - vStart.x, viewPt.y - vStart.y) <= hitRadius { return .startEndpoint }

        case .rectangle, .blur, .spotlight:
            let minX = min(ann.startPoint.x, ann.endPoint.x)
            let maxX = max(ann.startPoint.x, ann.endPoint.x)
            let minY = min(ann.startPoint.y, ann.endPoint.y)
            let maxY = max(ann.startPoint.y, ann.endPoint.y)

            let tl = imagePointToViewPoint(CGPoint(x: minX, y: minY))
            let tr = imagePointToViewPoint(CGPoint(x: maxX, y: minY))
            let bl = imagePointToViewPoint(CGPoint(x: minX, y: maxY))
            let br = imagePointToViewPoint(CGPoint(x: maxX, y: maxY))

            if hypot(viewPt.x - tl.x, viewPt.y - tl.y) <= hitRadius { return .rectTopLeft }
            if hypot(viewPt.x - tr.x, viewPt.y - tr.y) <= hitRadius { return .rectTopRight }
            if hypot(viewPt.x - bl.x, viewPt.y - bl.y) <= hitRadius { return .rectBottomLeft }
            if hypot(viewPt.x - br.x, viewPt.y - br.y) <= hitRadius { return .rectBottomRight }

        default:
            break
        }
        return .none
    }

    private func arrowMidpointView(_ ann: CanvasAnnotation) -> NSPoint {
        if let cp = ann.controlPoint {
            let peak = CGPoint(
                x: 0.25 * ann.startPoint.x + 0.5 * cp.x + 0.25 * ann.endPoint.x,
                y: 0.25 * ann.startPoint.y + 0.5 * cp.y + 0.25 * ann.endPoint.y
            )
            return imagePointToViewPoint(peak)
        }
        return imagePointToViewPoint(CGPoint(x: (ann.startPoint.x + ann.endPoint.x) * 0.5, y: (ann.startPoint.y + ann.endPoint.y) * 0.5))
    }

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
            return hypot(pt.x - ann.startPoint.x, pt.y - ann.startPoint.y) <= threshold + 12
        case .text:
            return AnnotationRenderer.textImageBounds(for: ann).insetBy(dx: -8, dy: -8).contains(pt)
        case .distance:
            return distanceFromPoint(pt, toSegmentStart: ann.startPoint, end: ann.endPoint) <= threshold
        case .arrow:
            if let cp = ann.controlPoint {
                let d1 = distanceFromPoint(pt, toSegmentStart: ann.startPoint, end: cp)
                let d2 = distanceFromPoint(pt, toSegmentStart: cp, end: ann.endPoint)
                return min(d1, d2) <= threshold + 6
            }
            return distanceFromPoint(pt, toSegmentStart: ann.startPoint, end: ann.endPoint) <= threshold + 4
        case .rectangle, .blur, .spotlight:
            let r = CGRect(
                x: min(ann.startPoint.x, ann.endPoint.x),
                y: min(ann.startPoint.y, ann.endPoint.y),
                width: max(1, abs(ann.endPoint.x - ann.startPoint.x)),
                height: max(1, abs(ann.endPoint.y - ann.startPoint.y))
            ).insetBy(dx: -threshold, dy: -threshold)
            return r.contains(pt)
        case .pencil:
            return ann.pathPoints.contains { hypot(pt.x - $0.x, pt.y - $0.y) <= threshold }
        case .pointer, .pan, .crop, .grabText:
            return false
        }
    }

    private func distanceFromPoint(_ pt: CGPoint, toSegmentStart p1: CGPoint, end p2: CGPoint) -> CGFloat {
        let l2 = pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2)
        if l2 == 0 { return hypot(pt.x - p1.x, pt.y - p1.y) }
        let t = max(0, min(1, ((pt.x - p1.x) * (p2.x - p1.x) + (pt.y - p1.y) * (p2.y - p1.y)) / l2))
        let proj = CGPoint(x: p1.x + t * (p2.x - p1.x), y: p1.y + t * (p2.y - p1.y))
        return hypot(pt.x - proj.x, pt.y - proj.y)
    }

    // MARK: - Core Drawing Routine
    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.clip(to: bounds)
        defer { ctx.restoreGState() }

        guard let img = state.activeSubjectImage ?? state.image else {
            drawStudioStageBackdrop(in: bounds, imageRect: nil, hasEmbeddedShadow: false, ctx: ctx)
            return
        }

        let canvasRect = canvasDisplayRect()
        let imgRect = imageDisplayRect()
        let effScale = effectiveScale()
        let layout = compositeLayout()
        let hasBackdropOrFrame = state.backdropConfig.backdropType != .none || state.backdropConfig.frameStyle != .none

        drawStudioStageBackdrop(
            in: bounds,
            imageRect: (state.backdropConfig.backdropType == .none && state.backdropConfig.frameStyle == .none && !state.hasEmbeddedShadow) ? imgRect : nil,
            hasEmbeddedShadow: state.hasEmbeddedShadow,
            ctx: ctx
        )

        if !hasBackdropOrFrame && !state.hasEmbeddedShadow && !state.backdropConfig.removeSubjectBackground {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: NSColor.black.withAlphaComponent(0.16).cgColor)
            ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
            ctx.fill(imgRect)
            ctx.restoreGState()
        }

        var visibleAnnotations: [CanvasAnnotation] = state.annotations.enumerated().compactMap { index, ann in
            if index == editingAnnotationIndex && inlineTextContainer != nil { return nil }
            return ann
        }
        if let live = liveAnnotation {
            visibleAnnotations.append(live)
        }

        let gifFrameCG: CGImage? = (state.backdropConfig.backdropType == .gif && !state.gifFrames.isEmpty)
            ? state.gifFrames[state.currentGifFrameIndex % state.gifFrames.count].cgImage
            : nil
        let auditUnit = SettingsManager.shared.gridAuditUnit

        ImageBackdropCompositor.renderCompositeContent(
            layout: layout,
            subjectImage: img,
            config: state.backdropConfig,
            annotations: visibleAnnotations,
            blurredSubjectImage: cachedBlurredNSImage,
            gifFrameImage: gifFrameCG,
            auditUnit: auditUnit,
            hasEmbeddedShadow: state.hasEmbeddedShadow,
            scaleToView: effScale,
            canvasOriginInView: canvasRect.origin,
            in: ctx
        )

        if !hasBackdropOrFrame && !state.hasEmbeddedShadow && !state.backdropConfig.removeSubjectBackground {
            ctx.saveGState()
            ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.08).cgColor)
            ctx.setLineWidth(0.75)
            ctx.stroke(imgRect.insetBy(dx: 0.35, dy: 0.35))
            ctx.restoreGState()
        }

        if effScale >= 3.0 {
            drawPixelGrid(in: imgRect, scale: effScale, ctx: ctx)
        }

        let mapper = AnnotationRenderer.Mapper(
            toCanvasPoint: { [unowned self] in self.imagePointToViewPoint($0) },
            scale: effScale,
            imageCanvasRect: imgRect
        )

        for (index, ann) in state.annotations.enumerated() {
            if index == editingAnnotationIndex && inlineTextContainer != nil {
                continue
            }

            let isSelected = (index == state.selectedAnnotationIndex)
            let isHovered = (index == hoveredAnnotationIndex)
            if isSelected {
                drawSelectionHandles(for: ann, mapper: mapper, in: ctx)
            } else if isHovered {
                drawHoverOutline(for: ann, mapper: mapper, in: ctx)
            }
            if isSelected || isHovered {
                let gripPt = dragGripCenter(for: ann, mapper: mapper)
                let highlight = (isHoveringDragGrip || activeHandleMode == .moveBody || didExceedDragThreshold) &&
                    ((isHovered && isHoveringDragGrip) || (isSelected && (activeHandleMode == .moveBody || didExceedDragThreshold)))
                AnnotationRenderer.drawDragGripPill(center: gripPt, isHighlighted: highlight, in: ctx)
            }
        }

        if let span = hoverSmartSpan, liveAnnotation == nil {
            drawSmartHoverGuides(span: span, in: ctx)
        }

        drawActiveSnapExtensionGuides(in: ctx, imgRect: imgRect)

        if state.currentTool == .crop, let crop = state.pendingCropRect, crop.width >= 4, crop.height >= 4 {
            drawCropOverlay(cropImgRect: crop, imgRect: imgRect, in: ctx)
        } else if state.currentTool == .grabText, let ocr = state.pendingOCRRect, ocr.width >= 4, ocr.height >= 4 {
            drawGrabTextOverlay(ocrImgRect: ocr, imgRect: imgRect, in: ctx)
        }
    }

    private func drawGrabTextOverlay(ocrImgRect: CGRect, imgRect: NSRect, in ctx: CGContext) {
        let vTL = imagePointToViewPoint(ocrImgRect.origin)
        let vBR = imagePointToViewPoint(CGPoint(x: ocrImgRect.maxX, y: ocrImgRect.maxY))
        let ocrR = AnnotationRenderer.normalizedRect(from: vTL, to: vBR)
        let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)

        ctx.saveGState()
        ctx.clip(to: imgRect)

        let dimPath = CGMutablePath()
        dimPath.addRect(imgRect)
        dimPath.addRect(ocrR)
        ctx.addPath(dimPath)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.30).cgColor)
        ctx.fillPath(using: .evenOdd)

        accent.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: ocrR, xRadius: 4, yRadius: 4).fill()

        accent.withAlphaComponent(0.95).setStroke()
        let border = NSBezierPath(roundedRect: ocrR, xRadius: 4, yRadius: 4)
        border.lineWidth = 1.5
        border.stroke()
        ctx.restoreGState()
    }

    private func drawCropOverlay(cropImgRect: CGRect, imgRect: NSRect, in ctx: CGContext) {
        let vTL = imagePointToViewPoint(cropImgRect.origin)
        let vBR = imagePointToViewPoint(CGPoint(x: cropImgRect.maxX, y: cropImgRect.maxY))
        let cropR = AnnotationRenderer.normalizedRect(from: vTL, to: vBR)

        ctx.saveGState()
        ctx.clip(to: imgRect)

        let dimPath = CGMutablePath()
        dimPath.addRect(imgRect)
        dimPath.addRect(cropR)
        ctx.addPath(dimPath)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.46).cgColor)
        ctx.fillPath(using: .evenOdd)

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.24).cgColor)
        ctx.setLineWidth(0.75)
        for i in 1...2 {
            let frac = CGFloat(i) / 3.0
            let gx = cropR.minX + cropR.width * frac
            let gy = cropR.minY + cropR.height * frac
            ctx.strokeLineSegments(between: [
                CGPoint(x: gx, y: cropR.minY), CGPoint(x: gx, y: cropR.maxY),
                CGPoint(x: cropR.minX, y: gy), CGPoint(x: cropR.maxX, y: gy)
            ])
        }

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.setLineWidth(1.5)
        ctx.stroke(cropR)

        let arm: CGFloat = min(14, min(cropR.width, cropR.height) * 0.35)
        ctx.setLineWidth(3.0)
        ctx.setLineCap(.round)
        let corners: [(CGPoint, CGPoint, CGPoint)] = [
            (CGPoint(x: cropR.minX, y: cropR.minY + arm), CGPoint(x: cropR.minX, y: cropR.minY), CGPoint(x: cropR.minX + arm, y: cropR.minY)),
            (CGPoint(x: cropR.maxX - arm, y: cropR.minY), CGPoint(x: cropR.maxX, y: cropR.minY), CGPoint(x: cropR.maxX, y: cropR.minY + arm)),
            (CGPoint(x: cropR.minX, y: cropR.maxY - arm), CGPoint(x: cropR.minX, y: cropR.maxY), CGPoint(x: cropR.minX + arm, y: cropR.maxY)),
            (CGPoint(x: cropR.maxX - arm, y: cropR.maxY), CGPoint(x: cropR.maxX, y: cropR.maxY), CGPoint(x: cropR.maxX, y: cropR.maxY - arm))
        ]
        for (a, b, c) in corners {
            ctx.move(to: a); ctx.addLine(to: b); ctx.addLine(to: c)
        }
        ctx.strokePath()
        ctx.restoreGState()

        if cropR.width >= 48 {
            let dimText = "\(Int(round(cropImgRect.width))) × \(Int(round(cropImgRect.height)))"
            AnnotationRenderer.drawMeasurementPill(
                text: dimText,
                at: CGPoint(x: cropR.midX, y: max(18, cropR.minY - 14)),
                fill: NSColor(red: 28/255, green: 28/255, blue: 32/255, alpha: 0.90),
                showOffGridDot: false
            )
        }
    }

    private func drawSelectionHandles(for ann: CanvasAnnotation, mapper: AnnotationRenderer.Mapper, in ctx: CGContext) {
        let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)

        func drawSquareHandle(at pt: NSPoint) {
            let r = NSRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            let p = NSBezierPath(roundedRect: r, xRadius: 2, yRadius: 2)
            p.fill()
            accent.setStroke()
            p.lineWidth = 1.5
            p.stroke()
        }

        func drawCircleHandle(at pt: NSPoint) {
            let r = NSRect(x: pt.x - 4, y: pt.y - 4, width: 8, height: 8)
            NSColor.white.setFill()
            let p = NSBezierPath(ovalIn: r)
            p.fill()
            accent.setStroke()
            p.lineWidth = 1.5
            p.stroke()
        }

        switch ann.tool {
        case .arrow:
            drawSquareHandle(at: mapper.toCanvasPoint(ann.startPoint))
            drawSquareHandle(at: mapper.toCanvasPoint(ann.endPoint))
            drawCircleHandle(at: arrowMidpointView(ann))

        case .distance:
            drawSquareHandle(at: mapper.toCanvasPoint(ann.startPoint))
            drawSquareHandle(at: mapper.toCanvasPoint(ann.endPoint))

        case .rectangle, .blur, .spotlight:
            let minX = min(ann.startPoint.x, ann.endPoint.x)
            let maxX = max(ann.startPoint.x, ann.endPoint.x)
            let minY = min(ann.startPoint.y, ann.endPoint.y)
            let maxY = max(ann.startPoint.y, ann.endPoint.y)
            drawSquareHandle(at: mapper.toCanvasPoint(CGPoint(x: minX, y: minY)))
            drawSquareHandle(at: mapper.toCanvasPoint(CGPoint(x: maxX, y: minY)))
            drawSquareHandle(at: mapper.toCanvasPoint(CGPoint(x: minX, y: maxY)))
            drawSquareHandle(at: mapper.toCanvasPoint(CGPoint(x: maxX, y: maxY)))

        case .text:
            let imgBox = AnnotationRenderer.textImageBounds(for: ann)
            let tl = mapper.toCanvasPoint(imgBox.origin)
            let br = mapper.toCanvasPoint(CGPoint(x: imgBox.maxX, y: imgBox.maxY))
            let selR = AnnotationRenderer.normalizedRect(from: tl, to: br).insetBy(dx: -4, dy: -4)
            ctx.saveGState()
            let ring = NSBezierPath(roundedRect: selR, xRadius: 9, yRadius: 9)
            accent.withAlphaComponent(0.75).setStroke()
            ring.lineWidth = 1.0
            ring.stroke()
            ctx.restoreGState()

        default:
            let b = CGRect(
                x: min(ann.startPoint.x, ann.endPoint.x),
                y: min(ann.startPoint.y, ann.endPoint.y),
                width: max(20, abs(ann.endPoint.x - ann.startPoint.x)),
                height: max(20, abs(ann.endPoint.y - ann.startPoint.y))
            )
            let vMin = mapper.toCanvasPoint(b.origin)
            let vMax = mapper.toCanvasPoint(CGPoint(x: b.maxX, y: b.maxY))
            let selR = AnnotationRenderer.normalizedRect(from: vMin, to: vMax).insetBy(dx: -6, dy: -6)
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(selR)
            ctx.restoreGState()
        }
    }

    // MARK: - Hover Outline & Universal Floating Drag Grip Placement
    private func drawHoverOutline(for ann: CanvasAnnotation, mapper: AnnotationRenderer.Mapper, in ctx: CGContext) {
        let hoverInk = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.48)
        ctx.saveGState()
        switch ann.tool {
        case .text:
            let imgBox = AnnotationRenderer.textImageBounds(for: ann)
            let tl = mapper.toCanvasPoint(imgBox.origin)
            let br = mapper.toCanvasPoint(CGPoint(x: imgBox.maxX, y: imgBox.maxY))
            let hoverR = AnnotationRenderer.normalizedRect(from: tl, to: br).insetBy(dx: -3, dy: -3)
            let path = NSBezierPath(roundedRect: hoverR, xRadius: 8, yRadius: 8)
            hoverInk.setStroke()
            path.lineWidth = 1.0
            path.stroke()

        case .rectangle, .blur, .spotlight:
            let tl = mapper.toCanvasPoint(ann.startPoint)
            let br = mapper.toCanvasPoint(ann.endPoint)
            let hoverR = AnnotationRenderer.normalizedRect(from: tl, to: br).insetBy(dx: -3, dy: -3)
            let path = NSBezierPath(roundedRect: hoverR, xRadius: max(3, ann.cornerRadius * mapper.scale), yRadius: max(3, ann.cornerRadius * mapper.scale))
            hoverInk.setStroke()
            path.lineWidth = 1.0
            path.stroke()

        case .numberedPin:
            let c = mapper.toCanvasPoint(ann.startPoint)
            let d = max(18, ann.strokeWidth * 4.5 * mapper.scale) + 6
            let path = NSBezierPath(ovalIn: NSRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d))
            hoverInk.setStroke()
            path.lineWidth = 1.2
            path.stroke()

        default:
            break
        }
        ctx.restoreGState()
    }

    private func dragGripCenter(for ann: CanvasAnnotation, mapper: AnnotationRenderer.Mapper) -> NSPoint {
        let s = mapper.scale
        let rawPt: NSPoint
        switch ann.tool {
        case .text:
            let imgBox = AnnotationRenderer.textImageBounds(for: ann)
            let tl = mapper.toCanvasPoint(imgBox.origin)
            let br = mapper.toCanvasPoint(CGPoint(x: imgBox.maxX, y: imgBox.maxY))
            let r = AnnotationRenderer.normalizedRect(from: tl, to: br)
            rawPt = NSPoint(x: r.midX, y: r.maxY + 13)

        case .rectangle, .blur, .spotlight:
            let tl = mapper.toCanvasPoint(ann.startPoint)
            let br = mapper.toCanvasPoint(ann.endPoint)
            let r = AnnotationRenderer.normalizedRect(from: tl, to: br)
            if ann.showSizeTag && r.width < 185 {
                rawPt = NSPoint(x: r.midX, y: r.minY - 13)
            } else {
                rawPt = NSPoint(x: r.midX, y: r.maxY + 13)
            }

        case .arrow:
            let vS = mapper.toCanvasPoint(ann.startPoint)
            let vE = mapper.toCanvasPoint(ann.endPoint)
            rawPt = NSPoint(x: (vS.x + vE.x) * 0.5, y: max(vS.y, vE.y) + 15)

        case .distance:
            let vS = mapper.toCanvasPoint(ann.startPoint)
            let vE = mapper.toCanvasPoint(ann.endPoint)
            let isHoriz = abs(ann.endPoint.x - ann.startPoint.x) >= abs(ann.endPoint.y - ann.startPoint.y)
            let mid = NSPoint(x: (vS.x + vE.x) * 0.5, y: (vS.y + vE.y) * 0.5)
            rawPt = isHoriz ? NSPoint(x: mid.x, y: mid.y + 20) : NSPoint(x: mid.x + 42, y: mid.y)

        case .numberedPin:
            let c = mapper.toCanvasPoint(ann.startPoint)
            let d = max(18, ann.strokeWidth * 4.5 * s)
            rawPt = NSPoint(x: c.x, y: c.y + d * 0.5 + 13)

        case .pencil:
            let pts = ann.pathPoints.map { mapper.toCanvasPoint($0) }
            let minX = pts.map(\.x).min() ?? 0
            let maxX = pts.map(\.x).max() ?? 0
            let maxY = pts.map(\.y).max() ?? 0
            rawPt = NSPoint(x: (minX + maxX) * 0.5, y: maxY + 13)

        case .pointer, .pan, .crop, .grabText:
            rawPt = .zero
        }

        guard bounds.width > 40 && bounds.height > 40 else { return rawPt }
        return NSPoint(
            x: max(18, min(bounds.width - 18, rawPt.x)),
            y: max(14, min(bounds.height - 16, rawPt.y))
        )
    }

    private func hitTestDragGrip(atViewPoint viewPt: NSPoint) -> Int? {
        guard let img = state.image else { return nil }
        let mapper = AnnotationRenderer.Mapper(
            toCanvasPoint: { [unowned self] in self.imagePointToViewPoint($0) },
            scale: effectiveScale(),
            imageCanvasRect: imageDisplayRect()
        )
        _ = img

        var candidates: [Int] = []
        if let h = hoveredAnnotationIndex, h >= 0 && h < state.annotations.count { candidates.append(h) }
        if let s = state.selectedAnnotationIndex, s >= 0 && s < state.annotations.count, s != hoveredAnnotationIndex { candidates.append(s) }

        for idx in candidates {
            if idx == editingAnnotationIndex && inlineTextContainer != nil { continue }
            let g = dragGripCenter(for: state.annotations[idx], mapper: mapper)
            if abs(viewPt.x - g.x) <= 16 && abs(viewPt.y - g.y) <= 12 {
                return idx
            }
        }
        return nil
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
        let accent = state.rulerColor

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

        if hDist >= 6 && hDist <= 420 && CGFloat(hDist) < state.imageSize.width * 0.85 {
            let hOffGrid = auditUnit > 1 && hDist <= 96 && (hDist % auditUnit != 0)
            ctx.setStrokeColor(accent.cgColor)
            ctx.strokeLineSegments(between: [vLeft, vRight])
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokeLineSegments(between: [
                CGPoint(x: vLeft.x, y: vOrigin.y - 6), CGPoint(x: vLeft.x, y: vOrigin.y + 6),
                CGPoint(x: vRight.x, y: vOrigin.y - 6), CGPoint(x: vRight.x, y: vOrigin.y + 6)
            ])
            AnnotationRenderer.drawMeasurementPill(text: "↔ \(hDist)px", at: CGPoint(x: (vLeft.x + vRight.x)/2, y: vOrigin.y - 16), fill: accent, showOffGridDot: hOffGrid)
        }

        if vDist >= 6 && vDist <= 420 && CGFloat(vDist) < state.imageSize.height * 0.85 {
            let vOffGrid = auditUnit > 1 && vDist <= 96 && (vDist % auditUnit != 0)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            ctx.setStrokeColor(accent.cgColor)
            ctx.strokeLineSegments(between: [vTop, vBottom])
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.strokeLineSegments(between: [
                CGPoint(x: vOrigin.x - 6, y: vTop.y), CGPoint(x: vOrigin.x + 6, y: vTop.y),
                CGPoint(x: vOrigin.x - 6, y: vBottom.y), CGPoint(x: vOrigin.x + 6, y: vBottom.y)
            ])
            AnnotationRenderer.drawMeasurementPill(text: "↕ \(vDist)px", at: CGPoint(x: vOrigin.x + 30, y: (vTop.y + vBottom.y)/2), fill: accent, showOffGridDot: vOffGrid)
        }
        ctx.restoreGState()
    }

    private func drawActiveSnapExtensionGuides(in ctx: CGContext, imgRect: NSRect) {
        guard !activeSnapGuides.verticalX.isEmpty || !activeSnapGuides.horizontalY.isEmpty else { return }
        ctx.saveGState()
        ctx.setStrokeColor(state.rulerColor.withAlphaComponent(0.45).cgColor)
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

    private func drawStudioStageBackdrop(in rect: NSRect, imageRect: NSRect?, hasEmbeddedShadow: Bool, ctx: CGContext) {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let stageBG = isDark
            ? NSColor(red: 24/255, green: 24/255, blue: 27/255, alpha: 1.0)
            : NSColor(red: 238/255, green: 239/255, blue: 243/255, alpha: 1.0)
        ctx.setFillColor(stageBG.cgColor)
        ctx.fill(rect)

        // Show subtle transparency checker grid strictly inside translucent screenshot area (never across chrome)
        guard let imgR = imageRect else { return }
        ctx.saveGState()
        ctx.clip(to: imgR)

        let tileSize: CGFloat = 10
        let startCol = max(0, Int(floor((imgR.minX) / tileSize)))
        let endCol = Int(ceil(imgR.maxX / tileSize))
        let startRow = max(0, Int(floor((imgR.minY) / tileSize)))
        let endRow = Int(ceil(imgR.maxY / tileSize))

        ctx.setFillColor((isDark ? NSColor.white : NSColor.black).withAlphaComponent(0.03).cgColor)
        for row in startRow...endRow {
            for col in startCol...endCol {
                if (row + col) % 2 == 0 {
                    ctx.fill(CGRect(x: CGFloat(col) * tileSize, y: CGFloat(row) * tileSize, width: tileSize, height: tileSize))
                }
            }
        }
        ctx.restoreGState()
    }

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

    // MARK: - Unified Export Renderers
    public static func renderFlattenedImage(state: ScreenshotEditorState) -> NSImage? {
        guard let baseImage = state.activeSubjectImage ?? state.image else { return nil }
        let mosaicImage = buildPixellatedImage(from: baseImage)
        let gifFrame: CGImage? = (state.backdropConfig.backdropType == .gif && !state.gifFrames.isEmpty)
            ? state.gifFrames[state.currentGifFrameIndex % state.gifFrames.count].cgImage
            : nil
        return ImageBackdropCompositor.renderFlattenedPNGImage(
            subjectImage: baseImage,
            pixelSize: state.pixelSize,
            config: state.backdropConfig,
            annotations: state.annotations,
            blurredSubjectImage: mosaicImage,
            gifFrameImage: gifFrame,
            auditUnit: SettingsManager.shared.gridAuditUnit,
            hasEmbeddedShadow: state.hasEmbeddedShadow
        )
    }

    public static func exportAnimatedGIF(state: ScreenshotEditorState, to url: URL) -> Bool {
        guard let baseImage = state.activeSubjectImage ?? state.image,
              !state.gifFrames.isEmpty else { return false }
        let mosaicImage = buildPixellatedImage(from: baseImage)
        return ImageBackdropCompositor.exportAnimatedGIF(
            subjectImage: baseImage,
            config: state.backdropConfig,
            annotations: state.annotations,
            blurredSubjectImage: mosaicImage,
            frames: state.gifFrames,
            auditUnit: SettingsManager.shared.gridAuditUnit,
            hasEmbeddedShadow: state.hasEmbeddedShadow,
            to: url
        )
    }
}
