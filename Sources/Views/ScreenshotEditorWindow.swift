import AppKit
import SwiftUI

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
        case .distance: return "Dimension Line (D)"
        case .arrow: return "Callout Arrow (A)"
        case .text: return "Text Callout (T)"
        case .numberedPin: return "Numbered QA Pin (N)"
        case .rectangle: return "Component Box (R)"
        case .roundedRect: return "Rounded Card (C)"
        case .pencil: return "Highlighter (P)"
        case .blur: return "Redaction Blur (B)"
        }
    }
}

// MARK: - Vector Annotation Primitive
public struct CanvasAnnotation: Identifiable, Equatable {
    public let id = UUID()
    public var tool: AnnotationTool
    public var startPoint: CGPoint  // In image coordinate space
    public var endPoint: CGPoint    // In image coordinate space
    public var pathPoints: [CGPoint] = [] // For freehand pencil
    public var text: String = ""
    public var number: Int = 1
    public var color: NSColor = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0) // Cobalt Azure

    public static func == (lhs: CanvasAnnotation, rhs: CanvasAnnotation) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Editor Observable State
public final class ScreenshotEditorState: ObservableObject {
    @Published public var currentTool: AnnotationTool = .distance
    @Published public var annotations: [CanvasAnnotation] = []
    @Published public var isPinned: Bool = false
    @Published public var hoveredHexColor: String = "#0A84FF"
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var nextPinNumber: Int = 1
    @Published public var selectedAnnotationIndex: Int? = nil

    public var image: NSImage?
    public var imageSize: CGSize = .zero

    public func undo() {
        if !annotations.isEmpty {
            annotations.removeLast()
            selectedAnnotationIndex = nil
            if nextPinNumber > 1 { nextPinNumber -= 1 }
        }
    }
}

// MARK: - Window Controller
@MainActor
public class ScreenshotEditorWindowController: NSObject, NSWindowDelegate {
    public static let shared = ScreenshotEditorWindowController()

    private var window: NSWindow?
    private let state = ScreenshotEditorState()

    private override init() {
        super.init()
    }

    public func show(image: NSImage, sourceRect: NSRect, on screen: NSScreen? = nil) {
        let targetScreen = screen ?? NSScreen.main ?? NSScreen.screens[0]
        state.image = image
        state.imageSize = image.size
        state.annotations.removeAll()
        state.nextPinNumber = 1
        state.selectedAnnotationIndex = nil
        state.zoomScale = 1.0

        let toolbarH: CGFloat = 52
        let minW: CGFloat = 780
        let minH: CGFloat = 520

        let maxW = targetScreen.visibleFrame.width * 0.90
        let maxH = targetScreen.visibleFrame.height * 0.90

        let desiredW = min(max(image.size.width + 60, minW), maxW)
        let desiredH = min(max(image.size.height + toolbarH + 60, minH), maxH)

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
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isReleasedWhenClosed = false
        win.delegate = self
        win.backgroundColor = NSColor.windowBackgroundColor

        let rootView = ScreenshotEditorRootView(state: state, onClose: { [weak self] in
            self?.close()
        })
        win.contentView = NSHostingView(rootView: rootView)

        self.window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func addSampleAnnotationsForTesting() {
        state.annotations = [
            CanvasAnnotation(tool: .distance, startPoint: CGPoint(x: 80, y: 160), endPoint: CGPoint(x: 360, y: 160)),
            CanvasAnnotation(tool: .arrow, startPoint: CGPoint(x: 520, y: 320), endPoint: CGPoint(x: 430, y: 220)),
            CanvasAnnotation(tool: .rectangle, startPoint: CGPoint(x: 80, y: 200), endPoint: CGPoint(x: 380, y: 270)),
            CanvasAnnotation(tool: .roundedRect, startPoint: CGPoint(x: 80, y: 300), endPoint: CGPoint(x: 380, y: 400)),
            CanvasAnnotation(tool: .numberedPin, startPoint: CGPoint(x: 420, y: 220), endPoint: CGPoint(x: 420, y: 220), number: 1),
            CanvasAnnotation(tool: .numberedPin, startPoint: CGPoint(x: 420, y: 320), endPoint: CGPoint(x: 420, y: 320), number: 2),
            CanvasAnnotation(tool: .text, startPoint: CGPoint(x: 460, y: 310), endPoint: CGPoint(x: 460, y: 310), text: "Fix 4px grid margin"),
        ]
        state.nextPinNumber = 3
    }

    public func close() {
        window?.orderOut(nil)
        window = nil
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - Root View with Shottr-Style Unified Titlebar
public struct ScreenshotEditorRootView: View {
    @ObservedObject var state: ScreenshotEditorState
    let onClose: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            // Unified Titlebar Toolbar matching Shottr
            toolbarHeader
                .frame(height: 52)
                .background(
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(
                            Rectangle()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.5)
                        )
                )

            // AppKit Interactive Vector Canvas Representable
            ScreenshotEditorCanvasRepresentable(state: state)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .edgesIgnoringSafeArea(.top)
    }

    // MARK: - Toolbar Header
    private var toolbarHeader: some View {
        HStack(spacing: 12) {
            // Traffic Light Placeholder Spacing
            Spacer()
                .frame(width: 68)

            // Left Cluster: Copy, Save, Pin, Undo
            HStack(spacing: 6) {
                // Copy Button
                toolbarIconButton(icon: "doc.on.doc", tooltip: "Copy flattened image with annotations (⌘C)") {
                    copyFlattenedImage()
                }

                // Save Button
                toolbarIconButton(icon: "square.and.arrow.down", tooltip: "Save PNG to Downloads (⌘S)") {
                    savePNGToDownloads()
                }

                // Pin Button
                toolbarIconButton(
                    icon: state.isPinned ? "pin.fill" : "pin",
                    tooltip: state.isPinned ? "Unpin window" : "Pin above all windows (⌘P)",
                    isActive: state.isPinned
                ) {
                    state.isPinned.toggle()
                    if let win = NSApp.keyWindow {
                        win.level = state.isPinned ? .floating : .normal
                    }
                }

                Divider()
                    .frame(height: 16)
                    .padding(.horizontal, 2)

                // Undo Button
                toolbarIconButton(icon: "arrow.uturn.backward", tooltip: "Undo annotation (⌘Z)") {
                    state.undo()
                }
            }

            Spacer()

            // Center Cluster: Annotation & Designer Tools
            HStack(spacing: 4) {
                ForEach(AnnotationTool.allCases) { tool in
                    Button(action: { state.currentTool = tool }) {
                        Image(systemName: tool.icon)
                            .font(.system(size: 13, weight: state.currentTool == tool ? .semibold : .regular))
                            .foregroundColor(state.currentTool == tool ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.85))
                            .frame(width: 28, height: 26)
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
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
            )

            Spacer()

            // Right Cluster: Telemetry (Hex Loupe, Dimensions, Zoom)
            HStack(spacing: 12) {
                // Color Loupe Swatch
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.hoveredHexColor, forType: .string)
                    ToastHUDController.shared.showSimpleToast(message: "Copied \(state.hoveredHexColor)", icon: "checkmark")
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(hex: state.hoveredHexColor) ?? .blue)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.primary.opacity(0.2), lineWidth: 0.5))

                        VStack(alignment: .leading, spacing: 0) {
                            Text(state.hoveredHexColor)
                                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                            Text("Tab to copy")
                                .font(.system(size: 8.5))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Click or press Tab to copy Hex")

                Divider()
                    .frame(height: 16)

                // Dimensions
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(state.imageSize.width))×\(Int(state.imageSize.height)) pt")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Image size")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }

                Divider()
                    .frame(height: 16)

                // Zoom Level
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(Int(state.zoomScale * 100))%")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("Zoom")
                        .font(.system(size: 8.5))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.trailing, 16)
        }
    }

    private func toolbarIconButton(icon: String, tooltip: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isActive ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.85))
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
        .help(tooltip)
    }

    private func copyFlattenedImage() {
        guard let flattened = ScreenshotEditorCanvasNSView.renderFlattenedImage(state: state) else { return }
        let pboard = NSPasteboard.general
        pboard.clearContents()
        if let tiff = flattened.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) {
            pboard.setData(png, forType: .png)
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
        let view = ScreenshotEditorCanvasNSView(state: state)
        return view
    }

    public func updateNSView(_ nsView: ScreenshotEditorCanvasNSView, context: Context) {
        nsView.syncState(state)
    }
}

// MARK: - AppKit Vector Canvas NSView
public class ScreenshotEditorCanvasNSView: NSView {
    private var state: ScreenshotEditorState
    private var cachedBitmapRep: NSBitmapImageRep?
    private var trackingAreaRef: NSTrackingArea?

    // Drag interaction tracking
    private var dragStartImagePoint: CGPoint?
    private var liveAnnotation: CanvasAnnotation?
    private var inlineTextField: NSTextField?

    public init(state: ScreenshotEditorState) {
        self.state = state
        super.init(frame: .zero)
        self.wantsLayer = true
        updateBitmapCache()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func syncState(_ newState: ScreenshotEditorState) {
        self.state = newState
        updateBitmapCache()
        needsDisplay = true
    }

    private func updateBitmapCache() {
        if let img = state.image, cachedBitmapRep == nil {
            if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                self.cachedBitmapRep = rep
            }
        }
    }

    override public var acceptsFirstResponder: Bool { true }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingAreaRef { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseMoved, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(t)
        trackingAreaRef = t
    }

    override public func cursorUpdate(with event: NSEvent) {
        switch state.currentTool {
        case .pointer:
            NSCursor.arrow.set()
        case .text:
            NSCursor.iBeam.set()
        case .numberedPin:
            NSCursor.pointingHand.set()
        default:
            NSCursor.crosshair.set()
        }
    }

    // MARK: - Coordinate Transformations
    private func imageDisplayRect() -> NSRect {
        guard let img = state.image else { return bounds }
        let imgSize = img.size
        guard imgSize.width > 0 && imgSize.height > 0 else { return bounds }

        let availW = max(10, bounds.width - 40)
        let availH = max(10, bounds.height - 40)

        let scale = min(min(availW / imgSize.width, availH / imgSize.height), 1.0) * state.zoomScale
        let renderW = imgSize.width * scale
        let renderH = imgSize.height * scale

        let renderX = (bounds.width - renderW) / 2
        let renderY = (bounds.height - renderH) / 2

        return NSRect(x: renderX, y: renderY, width: renderW, height: renderH)
    }

    private func viewPointToImagePoint(_ viewPt: NSPoint) -> CGPoint? {
        let r = imageDisplayRect()
        guard r.width > 0 && r.height > 0 else { return nil }
        guard let img = state.image else { return nil }

        let relX = (viewPt.x - r.origin.x) / r.width
        let relY = (viewPt.y - r.origin.y) / r.height

        guard relX >= 0 && relX <= 1 && relY >= 0 && relY <= 1 else { return nil }

        return CGPoint(
            x: relX * img.size.width,
            y: (1.0 - relY) * img.size.height // Flip Y so 0 is top of image
        )
    }

    private func imagePointToViewPoint(_ imgPt: CGPoint) -> NSPoint {
        let r = imageDisplayRect()
        guard let img = state.image, img.size.width > 0 && img.size.height > 0 else { return .zero }

        let relX = imgPt.x / img.size.width
        let relY = 1.0 - (imgPt.y / img.size.height) // Invert Y back to Cocoa view

        return NSPoint(
            x: r.origin.x + relX * r.width,
            y: r.origin.y + relY * r.height
        )
    }

    // MARK: - Mouse Events
    override public func mouseMoved(with event: NSEvent) {
        let viewLoc = convert(event.locationInWindow, from: nil)
        if let imgPt = viewPointToImagePoint(viewLoc), let rep = cachedBitmapRep {
            // Live sample pixel hex color under cursor
            let pixelX = Int((imgPt.x / state.imageSize.width) * CGFloat(rep.pixelsWide))
            let pixelY = Int((imgPt.y / state.imageSize.height) * CGFloat(rep.pixelsHigh))

            if pixelX >= 0 && pixelX < rep.pixelsWide && pixelY >= 0 && pixelY < rep.pixelsHigh {
                if let color = rep.colorAt(x: pixelX, y: pixelY) {
                    let r = Int(round(color.redComponent * 255))
                    let g = Int(round(color.greenComponent * 255))
                    let b = Int(round(color.blueComponent * 255))
                    state.hoveredHexColor = String(format: "#%02X%02X%02X", r, g, b)
                }
            }
        }
        needsDisplay = true
    }

    override public func mouseDown(with event: NSEvent) {
        dismissInlineTextField()

        let viewLoc = convert(event.locationInWindow, from: nil)
        guard let imgPt = viewPointToImagePoint(viewLoc) else { return }

        switch state.currentTool {
        case .pointer:
            // Hit test existing annotations (in reverse order for top-most)
            var hitIndex: Int? = nil
            for (index, ann) in state.annotations.enumerated().reversed() {
                if isPoint(imgPt, near: ann) {
                    hitIndex = index
                    break
                }
            }
            state.selectedAnnotationIndex = hitIndex
            dragStartImagePoint = imgPt

        case .numberedPin:
            // Instant drop of numbered pin
            let pin = CanvasAnnotation(
                tool: .numberedPin,
                startPoint: imgPt,
                endPoint: imgPt,
                number: state.nextPinNumber
            )
            state.nextPinNumber += 1
            state.annotations.append(pin)
            state.selectedAnnotationIndex = state.annotations.count - 1

        case .text:
            // Open inline text field to enter note
            showInlineTextEditor(at: viewLoc, imagePoint: imgPt)

        case .pencil:
            dragStartImagePoint = imgPt
            var ann = CanvasAnnotation(tool: .pencil, startPoint: imgPt, endPoint: imgPt)
            ann.pathPoints = [imgPt]
            liveAnnotation = ann

        default:
            // Vector drag: dimension, arrow, rectangle, roundedRect, blur
            dragStartImagePoint = imgPt
            liveAnnotation = CanvasAnnotation(tool: state.currentTool, startPoint: imgPt, endPoint: imgPt)
        }

        needsDisplay = true
    }

    override public func mouseDragged(with event: NSEvent) {
        let viewLoc = convert(event.locationInWindow, from: nil)
        guard let currentImgPt = viewPointToImagePoint(viewLoc) else { return }

        if state.currentTool == .pointer, let idx = state.selectedAnnotationIndex, let start = dragStartImagePoint {
            // Drag move existing annotation
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

            // Shift snap for Dimension line: Snap to exact horizontal or vertical
            if live.tool == .distance {
                let dx = abs(end.x - start.x)
                let dy = abs(end.y - start.y)
                if event.modifierFlags.contains(.shift) || (dx > 20 && dy < 15) {
                    end.y = start.y // Perfect horizontal
                } else if event.modifierFlags.contains(.shift) || (dy > 20 && dx < 15) {
                    end.x = start.x // Perfect vertical
                }
            }

            if live.tool == .pencil {
                live.pathPoints.append(end)
            }

            live.endPoint = end
            liveAnnotation = live
        }

        needsDisplay = true
    }

    override public func mouseUp(with event: NSEvent) {
        if let live = liveAnnotation {
            let dx = abs(live.endPoint.x - live.startPoint.x)
            let dy = abs(live.endPoint.y - live.startPoint.y)
            if dx > 3 || dy > 3 || live.tool == .pencil {
                state.annotations.append(live)
                state.selectedAnnotationIndex = state.annotations.count - 1
            }
            liveAnnotation = nil
        }
        dragStartImagePoint = nil
        needsDisplay = true
    }

    override public func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 51, 117: // Delete / Backspace
            if let idx = state.selectedAnnotationIndex, idx < state.annotations.count {
                state.annotations.remove(at: idx)
                state.selectedAnnotationIndex = nil
                needsDisplay = true
            }

        case 48: // Tab -> Copy hex color
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(state.hoveredHexColor, forType: .string)
            ToastHUDController.shared.showSimpleToast(message: "Copied \(state.hoveredHexColor)", icon: "checkmark")

        case 9:  // V -> Pointer
            state.currentTool = .pointer
        case 2:  // D -> Dimension
            state.currentTool = .distance
        case 0:  // A -> Arrow
            state.currentTool = .arrow
        case 17: // T -> Text
            state.currentTool = .text
        case 45: // N -> Numbered Pin
            state.currentTool = .numberedPin
        case 15: // R -> Rectangle
            state.currentTool = .rectangle
        case 8:  // C -> Rounded Card
            state.currentTool = .roundedRect
        case 35: // P -> Highlighter
            state.currentTool = .pencil
        case 11: // B -> Blur
            state.currentTool = .blur
        default:
            super.keyDown(with: event)
        }
    }

    // MARK: - Inline Text Editor
    private func showInlineTextEditor(at viewPoint: NSPoint, imagePoint: CGPoint) {
        let field = NSTextField(frame: NSRect(x: viewPoint.x - 10, y: viewPoint.y - 14, width: 180, height: 28))
        field.focusRingType = .none
        field.bezelStyle = .roundedBezel
        field.backgroundColor = NSColor.black.withAlphaComponent(0.85)
        field.textColor = .white
        field.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        field.placeholderString = "Type note & press Return"
        field.target = self
        field.action = #selector(textEntered(_:))

        addSubview(field)
        window?.makeFirstResponder(field)
        self.inlineTextField = field
        self.dragStartImagePoint = imagePoint
    }

    @objc private func textEntered(_ sender: NSTextField) {
        let text = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty, let imgPt = dragStartImagePoint {
            var ann = CanvasAnnotation(tool: .text, startPoint: imgPt, endPoint: imgPt)
            ann.text = text
            state.annotations.append(ann)
            state.selectedAnnotationIndex = state.annotations.count - 1
        }
        dismissInlineTextField()
        needsDisplay = true
    }

    private func dismissInlineTextField() {
        if let tf = inlineTextField {
            tf.removeFromSuperview()
            inlineTextField = nil
        }
    }

    private func isPoint(_ pt: CGPoint, near ann: CanvasAnnotation) -> Bool {
        let threshold: CGFloat = 16.0
        switch ann.tool {
        case .numberedPin, .text:
            let d = hypot(pt.x - ann.startPoint.x, pt.y - ann.startPoint.y)
            return d <= threshold + 10

        case .distance, .arrow:
            let p1 = ann.startPoint
            let p2 = ann.endPoint
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
            for p in ann.pathPoints {
                if hypot(pt.x - p.x, pt.y - p.y) <= threshold { return true }
            }
            return false

        default:
            return false
        }
    }

    // MARK: - Drawing Routines
    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // 1. Draw Checkerboard background
        drawCheckerboard(in: bounds, ctx: ctx)

        // 2. Draw Base Screenshot Image centered
        guard let img = state.image else { return }
        let imgRect = imageDisplayRect()

        // Drop shadow behind base image
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: NSColor.black.withAlphaComponent(0.22).cgColor)
        img.draw(in: imgRect)
        ctx.restoreGState()

        // 3. Render Committed Vector Annotations
        for (index, ann) in state.annotations.enumerated() {
            let isSelected = (index == state.selectedAnnotationIndex)
            drawAnnotation(ann, isSelected: isSelected, in: ctx)
        }

        // 4. Render Active Live Drag Annotation
        if let live = liveAnnotation {
            drawAnnotation(live, isSelected: false, in: ctx)
        }
    }

    private func drawAnnotation(_ ann: CanvasAnnotation, isSelected: Bool, in ctx: CGContext) {
        let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)
        let vStart = imagePointToViewPoint(ann.startPoint)
        let vEnd = imagePointToViewPoint(ann.endPoint)

        switch ann.tool {
        case .distance:
            // Dimension Line: |<--- 148px --->|
            let dx = ann.endPoint.x - ann.startPoint.x
            let dy = ann.endPoint.y - ann.startPoint.y
            let dist = Int(round(hypot(dx, dy)))

            // Main shaft
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.6)
            ctx.strokeLineSegments(between: [vStart, vEnd])

            // End tick bars
            let tickLen: CGFloat = 7
            let angle = atan2(vEnd.y - vStart.y, vEnd.x - vStart.x)
            let perpAngle = angle + .pi / 2

            let t1a = CGPoint(x: vStart.x + cos(perpAngle) * tickLen, y: vStart.y + sin(perpAngle) * tickLen)
            let t1b = CGPoint(x: vStart.x - cos(perpAngle) * tickLen, y: vStart.y - sin(perpAngle) * tickLen)
            let t2a = CGPoint(x: vEnd.x + cos(perpAngle) * tickLen, y: vEnd.y + sin(perpAngle) * tickLen)
            let t2b = CGPoint(x: vEnd.x - cos(perpAngle) * tickLen, y: vEnd.y - sin(perpAngle) * tickLen)

            ctx.strokeLineSegments(between: [t1a, t1b, t2a, t2b])

            // Centered Distance Badge
            let mid = CGPoint(x: (vStart.x + vEnd.x) / 2, y: (vStart.y + vEnd.y) / 2)
            let badgeText = "\(dist)px" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = badgeText.size(withAttributes: attrs)
            let badgeRect = NSRect(x: mid.x - (size.width + 12)/2, y: mid.y - 10, width: size.width + 12, height: 20)

            accent.setFill()
            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4)
            badgePath.fill()
            badgeText.draw(at: NSPoint(x: badgeRect.origin.x + 6, y: badgeRect.origin.y + 3), withAttributes: attrs)

        case .arrow:
            // Callout Arrow with crisp arrowhead
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(2.2)
            ctx.strokeLineSegments(between: [vStart, vEnd])

            let angle = atan2(vEnd.y - vStart.y, vEnd.x - vStart.x)
            let headLen: CGFloat = 11.0
            let p1 = CGPoint(x: vEnd.x - headLen * cos(angle - .pi / 6), y: vEnd.y - headLen * sin(angle - .pi / 6))
            let p2 = CGPoint(x: vEnd.x - headLen * cos(angle + .pi / 6), y: vEnd.y - headLen * sin(angle + .pi / 6))

            ctx.setFillColor(accent.cgColor)
            ctx.beginPath()
            ctx.move(to: vEnd)
            ctx.addLine(to: p1)
            ctx.addLine(to: p2)
            ctx.closePath()
            ctx.fillPath()

        case .rectangle:
            let r = normalizedRect(from: vStart, to: vEnd)
            ctx.setStrokeColor(accent.cgColor)
            ctx.setLineWidth(1.8)
            ctx.stroke(r)

            // Attached dimension tag: W × H pt
            let imgW = Int(abs(ann.endPoint.x - ann.startPoint.x))
            let imgH = Int(abs(ann.endPoint.y - ann.startPoint.y))
            let tagText = "\(imgW) × \(imgH) pt" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = tagText.size(withAttributes: attrs)
            let tagRect = NSRect(x: r.minX, y: r.maxY >= 20 ? r.maxY - 18 : r.minY, width: size.width + 10, height: 16)
            NSColor.black.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: tagRect, xRadius: 3, yRadius: 3).fill()
            tagText.draw(at: NSPoint(x: tagRect.origin.x + 5, y: tagRect.origin.y + 2), withAttributes: attrs)

        case .roundedRect:
            let r = normalizedRect(from: vStart, to: vEnd)
            let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
            accent.setStroke()
            path.lineWidth = 1.8
            path.stroke()

            // Corner radius tag
            let tagText = "r: 8px" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let size = tagText.size(withAttributes: attrs)
            let tagRect = NSRect(x: r.minX, y: r.maxY >= 20 ? r.maxY - 18 : r.minY, width: size.width + 10, height: 16)
            NSColor.black.withAlphaComponent(0.85).setFill()
            NSBezierPath(roundedRect: tagRect, xRadius: 3, yRadius: 3).fill()
            tagText.draw(at: NSPoint(x: tagRect.origin.x + 5, y: tagRect.origin.y + 2), withAttributes: attrs)

        case .numberedPin:
            // QA Feedback Pin ①, ②, ③
            let center = vStart
            let circleRect = NSRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)

            accent.setFill()
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

            NSColor.black.withAlphaComponent(0.82).setFill()
            let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 6, yRadius: 6)
            cardPath.fill()

            accent.setStroke()
            cardPath.lineWidth = 1.0
            cardPath.stroke()

            cardText.draw(at: NSPoint(x: cardRect.origin.x + 8, y: cardRect.origin.y + 4), withAttributes: attrs)

        case .pencil:
            if !ann.pathPoints.isEmpty {
                let path = NSBezierPath()
                let pts = ann.pathPoints.map { imagePointToViewPoint($0) }
                path.move(to: pts[0])
                for pt in pts.dropFirst() {
                    path.line(to: pt)
                }
                path.lineWidth = 6.0
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.35).setStroke()
                path.stroke()
            }

        case .blur:
            let r = normalizedRect(from: vStart, to: vEnd)
            NSColor.black.withAlphaComponent(0.70).setFill()
            let path = NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4)
            path.fill()
            NSColor.white.withAlphaComponent(0.15).setStroke()
            path.lineWidth = 0.8
            path.stroke()

        default:
            break
        }

        // Selection highlight ring
        if isSelected {
            let bounds = boundingBox(for: ann)
            let vMin = imagePointToViewPoint(bounds.origin)
            let vMax = imagePointToViewPoint(CGPoint(x: bounds.maxX, y: bounds.maxY))
            let selR = normalizedRect(from: vMin, to: vMax).insetBy(dx: -6, dy: -6)

            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.setStrokeColor(accent.cgColor)
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
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
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

    // MARK: - Flattened Image Generation for Copy / Save
    public static func renderFlattenedImage(state: ScreenshotEditorState) -> NSImage? {
        guard let baseImage = state.image else { return nil }
        let size = baseImage.size
        let scale: CGFloat = 2.0 // Crisp Retina Scale
        let pixelW = max(1, Int(size.width * scale))
        let pixelH = max(1, Int(size.height * scale))

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

        let gCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gCtx

        // Draw Base Image
        baseImage.draw(in: NSRect(origin: .zero, size: NSSize(width: pixelW, height: pixelH)))

        // Scale context to draw annotations in image point space
        ctx.scaleBy(x: scale, y: scale)

        let accent = NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 1.0)

        // Draw each vector annotation at exact image coordinates
        for ann in state.annotations {
            // Note: in image coordinate space, Y=0 is top. In Cocoa CGContext, Y=0 is bottom.
            let p1 = CGPoint(x: ann.startPoint.x, y: size.height - ann.startPoint.y)
            let p2 = CGPoint(x: ann.endPoint.x, y: size.height - ann.endPoint.y)

            switch ann.tool {
            case .distance:
                let dist = Int(round(hypot(ann.endPoint.x - ann.startPoint.x, ann.endPoint.y - ann.startPoint.y)))
                ctx.setStrokeColor(accent.cgColor)
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
                let text = "\(dist)px" as NSString
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 10.5, weight: .bold),
                    .foregroundColor: NSColor.white
                ]
                let s = text.size(withAttributes: attrs)
                let badgeRect = NSRect(x: mid.x - (s.width + 12)/2, y: mid.y - 10, width: s.width + 12, height: 20)
                accent.setFill()
                NSBezierPath(roundedRect: badgeRect, xRadius: 4, yRadius: 4).fill()
                text.draw(at: NSPoint(x: badgeRect.origin.x + 6, y: badgeRect.origin.y + 3), withAttributes: attrs)

            case .arrow:
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(2.2)
                ctx.strokeLineSegments(between: [p1, p2])

                let angle = atan2(p2.y - p1.y, p2.x - p1.x)
                let headLen: CGFloat = 11.0
                let a1 = CGPoint(x: p2.x - headLen * cos(angle - .pi / 6), y: p2.y - headLen * sin(angle - .pi / 6))
                let a2 = CGPoint(x: p2.x - headLen * cos(angle + .pi / 6), y: p2.y - headLen * sin(angle + .pi / 6))

                ctx.setFillColor(accent.cgColor)
                ctx.beginPath()
                ctx.move(to: p2)
                ctx.addLine(to: a1)
                ctx.addLine(to: a2)
                ctx.closePath()
                ctx.fillPath()

            case .rectangle:
                let r = NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
                ctx.setStrokeColor(accent.cgColor)
                ctx.setLineWidth(1.8)
                ctx.stroke(r)

            case .roundedRect:
                let r = NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
                accent.setStroke()
                let path = NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8)
                path.lineWidth = 1.8
                path.stroke()

            case .numberedPin:
                let r = NSRect(x: p1.x - 11, y: p1.y - 11, width: 22, height: 22)
                accent.setFill()
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
                NSColor.black.withAlphaComponent(0.82).setFill()
                let card = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
                card.fill()
                accent.setStroke()
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
                    NSColor(red: 10/255, green: 132/255, blue: 255/255, alpha: 0.35).setStroke()
                    path.stroke()
                }

            case .blur:
                let r = NSRect(x: min(p1.x, p2.x), y: min(p1.y, p2.y), width: abs(p1.x - p2.x), height: abs(p1.y - p2.y))
                NSColor.black.withAlphaComponent(0.70).setFill()
                NSBezierPath(roundedRect: r, xRadius: 4, yRadius: 4).fill()

            default:
                break
            }
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let finalCG = ctx.makeImage() else { return baseImage }
        return NSImage(cgImage: finalCG, size: size)
    }
}
