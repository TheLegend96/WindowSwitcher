import AppKit
import SwiftUI
import CoreImage

// MARK: - Editor Observable State
@MainActor
public final class ScreenshotEditorState: ObservableObject {
    @Published public var currentTool: AnnotationTool = .distance
    @Published public var annotations: [CanvasAnnotation] = []
    @Published public var canUndo: Bool = false
    @Published public var canRedo: Bool = false
    @Published public var isPinned: Bool = false

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

    public var image: NSImage?
    public var imageSize: CGSize = .zero      // Logical points (CSS px)
    public var pixelSize: CGSize = .zero      // Physical bitmap pixels
    public var hasEmbeddedShadow: Bool = false

    private var undoHistory: [[CanvasAnnotation]] = []
    private var redoHistory: [[CanvasAnnotation]] = []
    private var propertyEditUndoToken: Date? = nil

    // Action hooks wired to Canvas & Window
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
        default: break
        }
        if let idx = selectedAnnotationIndex, idx < annotations.count {
            annotations[idx].color = color
            onCanvasMutated?()
        }
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
    }

    public func applyArrowStyle(_ style: ArrowStyle) {
        arrowStyle = style
        if let idx = selectedAnnotationIndex, idx < annotations.count, annotations[idx].tool == .arrow {
            annotations[idx].arrowStyle = style
            onCanvasMutated?()
        }
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
        let azure = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)
        let coral = NSColor(red: 255/255, green: 69/255, blue: 58/255, alpha: 1.0)
        let amber = NSColor(red: 255/255, green: 159/255, blue: 10/255, alpha: 1.0)

        state.annotations = [
            CanvasAnnotation(tool: .distance, startPoint: CGPoint(x: 80, y: 125), endPoint: CGPoint(x: 360, y: 125), color: azure),
            CanvasAnnotation(tool: .rectangle, startPoint: CGPoint(x: 80, y: 170), endPoint: CGPoint(x: 360, y: 245), color: azure, strokeWidth: 2.5, rectFillMode: .stroke, cornerRadius: 0, showSizeTag: true),
            CanvasAnnotation(tool: .rectangle, startPoint: CGPoint(x: 80, y: 280), endPoint: CGPoint(x: 360, y: 360), color: amber, strokeWidth: 2.5, rectFillMode: .tinted, cornerRadius: 8, showSizeTag: false),
            CanvasAnnotation(tool: .arrow, startPoint: CGPoint(x: 540, y: 255), endPoint: CGPoint(x: 390, y: 185), color: coral, strokeWidth: 5.5, arrowStyle: .tapered),
            CanvasAnnotation(tool: .arrow, startPoint: CGPoint(x: 410, y: 390), endPoint: CGPoint(x: 540, y: 390), color: azure, strokeWidth: 3.0, arrowStyle: .doubleEnded),
            CanvasAnnotation(tool: .text, startPoint: CGPoint(x: 545, y: 245), endPoint: CGPoint(x: 545, y: 245), text: "Fix spacing & contrast", color: .white, strokeWidth: 15, textStyle: .quoteBubble),
            CanvasAnnotation(tool: .numberedPin, startPoint: CGPoint(x: 375, y: 170), endPoint: CGPoint(x: 375, y: 170), number: 1, color: coral),
            CanvasAnnotation(tool: .blur, startPoint: CGPoint(x: 520, y: 428), endPoint: CGPoint(x: 775, y: 468))
        ]
        state.selectedAnnotationIndex = 3
        state.recomputeNextPin()
        state.onCanvasMutated?()
    }

    public func close() {
        removeKeyboardMonitors()
        DesignerColorPanelController.shared.clearHandler()
        NSColorPanel.shared.orderOut(nil)
        window?.orderOut(nil)
        window = nil
    }

    public func windowWillClose(_ notification: Notification) {
        removeKeyboardMonitors()
        DesignerColorPanelController.shared.clearHandler()
        NSColorPanel.shared.orderOut(nil)
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
                default:
                    break
                }
            }

            // 3. Single-letter Tool Switching (works reliably regardless of SwiftUI focus)
            if !isCmd && !hasOtherMods && !isShift {
                switch event.keyCode {
                case 9:  self.state.currentTool = .pointer; return nil      // V
                case 2:  self.state.currentTool = .distance; return nil     // D
                case 0:  self.state.currentTool = .arrow; return nil        // A
                case 17: self.state.currentTool = .text; return nil         // T
                case 45: self.state.currentTool = .numberedPin; return nil  // N
                case 15: // R -> Rectangle (sharp border)
                    self.state.rectCornerRadius = 0.0
                    self.state.currentTool = .rectangle
                    return nil
                case 8:  // C -> Rounded Card preset on Rectangle
                    self.state.rectCornerRadius = 8.0
                    self.state.currentTool = .rectangle
                    return nil
                case 35: self.state.currentTool = .pencil; return nil       // P
                case 11: self.state.currentTool = .blur; return nil         // B
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

// MARK: - Root View with Unified Toolbar & Floating Contextual Inspector
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

            ZStack(alignment: .top) {
                ScreenshotEditorCanvasRepresentable(state: state)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Contextual Floating Inspector Bar (Figma / Shottr Style)
                DesignerInspectorBar(state: state)
                    .padding(.top, 10)
            }
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

            // Center Cluster: Clean Tool Bar
            HStack(spacing: 3) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button(action: {
                        state.selectedAnnotationIndex = nil
                        state.currentTool = tool
                    }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 13.5, weight: state.currentTool == tool ? .semibold : .regular))
                            .foregroundColor(state.currentTool == tool ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.85))
                            .frame(width: 30, height: 26)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(state.currentTool == tool ? Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.12) : Color.clear)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(state.currentTool == tool ? Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.35) : Color.clear, lineWidth: 0.8)
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

            Spacer()

            // Right Cluster: Hex Loupe + Contrast, Pixels + Points Size, Interactive Zoom
            HStack(spacing: 10) {
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

// MARK: - Interactive AppKit Vector Canvas
public class ScreenshotEditorCanvasNSView: NSView, NSTextFieldDelegate {
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

    private var inlineTextField: NSTextField?
    private var editingAnnotationIndex: Int?

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
            self.applyZoom(factor: factor, anchoredAtViewPoint: NSPoint(x: self.bounds.midX, y: self.bounds.midY))
        }
        state.onRequestZoomFit = { [weak self] in self?.resetZoomToFit() }
        state.onRequestZoomActual = { [weak self] in self?.zoomToActual100() }
        state.onCancelTextOrSelection = { [weak self] in self?.cancelActiveInteractions() }
        state.onCanvasMutated = { [weak self] in self?.needsDisplay = true }
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
        let availH = bounds.height - 60 // Extra breathing room at top for floating inspector
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
        let cy = bounds.midY + state.panOffset.y - 12 // Slight downward bias beneath floating inspector
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
        return CGPoint(x: max(0, min(img.size.width, pt.x)), y: max(0, min(img.size.height, pt.y)))
    }

    private func imagePointToViewPoint(_ imgPt: CGPoint) -> NSPoint {
        let r = imageDisplayRect()
        guard let img = state.image, img.size.width > 0 && img.size.height > 0 else { return .zero }
        let relX = imgPt.x / img.size.width
        let relY = 1.0 - (imgPt.y / img.size.height)
        return NSPoint(x: r.origin.x + relX * r.width, y: r.origin.y + relY * r.height)
    }

    // MARK: - Zoom & Pan Gestures (Cursor-Anchored)
    private func applyZoom(factor: CGFloat, anchoredAtViewPoint anchor: NSPoint) {
        let oldEff = effectiveScale()
        guard oldEff > 0 else { return }

        let oldCenterX = bounds.midX + state.panOffset.x
        let oldCenterY = bounds.midY + state.panOffset.y - 12
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
            state.panOffset = CGPoint(x: newCenterX - bounds.midX, y: newCenterY - (bounds.midY - 12))
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

    // MARK: - Mouse Hover, Handle Detection, Drawing, Dragging
    override public func mouseMoved(with event: NSEvent) {
        refreshHoverTelemetry(atViewPoint: convert(event.locationInWindow, from: nil), modifiers: event.modifierFlags)
    }

    override public func mouseExited(with event: NSEvent) {
        hoverSmartSpan = nil
        needsDisplay = true
    }

    private func refreshHoverTelemetry(atViewPoint viewLoc: NSPoint, modifiers: NSEvent.ModifierFlags) {
        guard let imgPt = viewPointToImagePoint(viewLoc) else {
            hoverSmartSpan = nil
            needsDisplay = true
            return
        }

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

        if state.isSpacePanning {
            isPanningCanvas = true
            lastPanViewPoint = viewLoc
            NSCursor.closedHand.set()
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
                dragStartImagePoint = imgPt
                hasPushedDragUndo = false
            } else {
                state.selectedAnnotationIndex = nil
                activeHandleMode = .none
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
                color: state.pinColor
            )
            state.addAnnotation(pin)

        case .text:
            // If clicking right onto an existing text callout, edit it directly!
            if let hitIdx = topAnnotationIndex(at: imgPt), state.annotations[hitIdx].tool == .text {
                state.selectedAnnotationIndex = hitIdx
                beginEditingTextAnnotation(at: hitIdx)
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

        // Handle Manipulation of Selected Annotation
        if let idx = state.selectedAnnotationIndex, idx < state.annotations.count, activeHandleMode != .none, let start = dragStartImagePoint {
            if !hasPushedDragUndo {
                state.pushUndoSnapshot()
                hasPushedDragUndo = true
            }
            applyHandleDrag(mode: activeHandleMode, index: idx, from: start, to: currentImgPt, modifiers: event.modifierFlags)
            dragStartImagePoint = currentImgPt
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
            } else if live.tool == .rectangle && event.modifierFlags.contains(.shift) {
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

    // MARK: - Inline Text Input (Click-to-Write + Shift-Return Newline)
    private func beginEditingTextAnnotation(at index: Int) {
        guard index >= 0 && index < state.annotations.count else { return }
        let ann = state.annotations[index]
        editingAnnotationIndex = index
        let viewPt = imagePointToViewPoint(ann.startPoint)
        showInlineTextEditor(atViewPoint: viewPt, imagePoint: ann.startPoint, initialText: ann.text, fontColor: ann.color, fontSize: ann.strokeWidth > 8 ? ann.strokeWidth : state.textSize)
    }

    private func showInlineTextEditor(atViewPoint viewPoint: NSPoint, imagePoint: CGPoint, initialText: String, fontColor: NSColor? = nil, fontSize: CGFloat? = nil) {
        dismissInlineTextField()
        let activeColor = fontColor ?? state.textColor
        let activeSize = fontSize ?? state.textSize
        let field = NSTextField(frame: NSRect(
            x: max(12, min(viewPoint.x - 4, bounds.width - 250)),
            y: max(12, min(viewPoint.y - 28, bounds.height - 60)),
            width: 240,
            height: max(30, activeSize + 14)
        ))
        field.focusRingType = .exterior
        field.bezelStyle = .roundedBezel
        field.backgroundColor = activeColor.relativeLuminance > 0.45
            ? NSColor(red: 22/255, green: 22/255, blue: 26/255, alpha: 0.94)
            : NSColor.white.withAlphaComponent(0.96)
        field.textColor = activeColor
        field.font = NSFont.systemFont(ofSize: min(24, max(12, activeSize)), weight: .medium)
        field.stringValue = initialText
        field.placeholderString = "Write text (Return to finish)"
        field.delegate = self
        field.target = self
        field.action = #selector(textEntered(_:))

        addSubview(field)
        window?.makeFirstResponder(field)
        self.inlineTextField = field
        self.dragStartImagePoint = imagePoint
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                textView.insertNewlineIgnoringFieldEditor(nil)
                return true
            }
            commitInlineTextIfNeeded()
            window?.makeFirstResponder(self)
            return true
        }
        return false
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
                state.selectedAnnotationIndex = editIdx
            }
        } else if !text.isEmpty, let imgPt = dragStartImagePoint {
            var ann = CanvasAnnotation(
                tool: .text,
                startPoint: imgPt,
                endPoint: imgPt,
                color: state.textColor,
                strokeWidth: state.textSize,
                textStyle: state.textStyle
            )
            ann.text = text
            state.addAnnotation(ann)
        }

        editingAnnotationIndex = nil
        tf.removeFromSuperview()
        inlineTextField = nil
        needsDisplay = true
    }

    private func dismissInlineTextField() {
        editingAnnotationIndex = nil
        inlineTextField?.removeFromSuperview()
        inlineTextField = nil
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

        case .rectangle, .blur:
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
        case .rectangle, .blur:
            let r = CGRect(
                x: min(ann.startPoint.x, ann.endPoint.x),
                y: min(ann.startPoint.y, ann.endPoint.y),
                width: max(1, abs(ann.endPoint.x - ann.startPoint.x)),
                height: max(1, abs(ann.endPoint.y - ann.startPoint.y))
            ).insetBy(dx: -threshold, dy: -threshold)
            return r.contains(pt)
        case .pencil:
            return ann.pathPoints.contains { hypot(pt.x - $0.x, pt.y - $0.y) <= threshold }
        case .pointer:
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

        drawCheckerboard(in: bounds, ctx: ctx)

        guard let img = state.image else { return }
        let imgRect = imageDisplayRect()
        let effScale = effectiveScale()

        ctx.saveGState()
        if !state.hasEmbeddedShadow {
            ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.22).cgColor)
        }
        ctx.interpolationQuality = effScale >= 3.0 ? .none : .high
        img.draw(in: imgRect)
        ctx.restoreGState()

        if effScale >= 3.0 {
            drawPixelGrid(in: imgRect, scale: effScale, ctx: ctx)
        }

        let mapper = AnnotationRenderer.Mapper(
            toCanvasPoint: { [unowned self] in self.imagePointToViewPoint($0) },
            scale: effScale,
            imageCanvasRect: imgRect
        )
        let auditUnit = SettingsManager.shared.gridAuditUnit

        for (index, ann) in state.annotations.enumerated() {
            AnnotationRenderer.draw(ann, mapper: mapper, blurredImage: cachedBlurredNSImage, auditUnit: auditUnit, in: ctx)
            if index == state.selectedAnnotationIndex {
                drawSelectionHandles(for: ann, mapper: mapper, in: ctx)
            }
        }

        if let span = hoverSmartSpan, liveAnnotation == nil {
            drawSmartHoverGuides(span: span, in: ctx)
        }

        drawActiveSnapExtensionGuides(in: ctx, imgRect: imgRect)

        if let live = liveAnnotation {
            AnnotationRenderer.draw(live, mapper: mapper, blurredImage: cachedBlurredNSImage, auditUnit: auditUnit, in: ctx)
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

        case .rectangle, .blur:
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
            let selR = AnnotationRenderer.normalizedRect(from: tl, to: br).insetBy(dx: -5, dy: -5)
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.0)
            ctx.stroke(selR)
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

    // MARK: - Unified Export Renderer (Zero Duplicated Drawing Code!)
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

        baseImage.draw(in: NSRect(origin: .zero, size: NSSize(width: pixelW, height: pixelH)))
        ctx.scaleBy(x: scaleX, y: scaleY)

        let exportMapper = AnnotationRenderer.Mapper(
            toCanvasPoint: { pt in CGPoint(x: pt.x, y: size.height - pt.y) },
            scale: 1.0,
            imageCanvasRect: NSRect(origin: .zero, size: size)
        )
        let auditUnit = SettingsManager.shared.gridAuditUnit

        for ann in state.annotations {
            AnnotationRenderer.draw(ann, mapper: exportMapper, blurredImage: mosaicImage, auditUnit: auditUnit, in: ctx)
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let finalCG = ctx.makeImage() else { return baseImage }
        return NSImage(cgImage: finalCG, size: size)
    }
}
