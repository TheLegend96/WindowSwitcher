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

// MARK: - Vector Annotation Primitives
public struct CanvasAnnotation: Identifiable {
    public let id = UUID()
    public var tool: AnnotationTool
    public var startPoint: CGPoint
    public var endPoint: CGPoint
    public var text: String = ""
    public var number: Int = 1
    public var color: Color = Color(red: 10/255, green: 132/255, blue: 255/255) // Cobalt Azure
}

// MARK: - Editor Observable State
public final class ScreenshotEditorState: ObservableObject {
    @Published public var currentTool: AnnotationTool = .distance
    @Published public var annotations: [CanvasAnnotation] = []
    @Published public var isPinned: Bool = false
    @Published public var hoveredHexColor: String = "#0A84FF"
    @Published public var zoomScale: CGFloat = 1.0
    @Published public var nextPinNumber: Int = 1
    @Published public var dragStart: CGPoint? = nil
    @Published public var dragCurrent: CGPoint? = nil

    public var image: NSImage?
    public var imageSize: CGSize = .zero

    public func undo() {
        if !annotations.isEmpty {
            annotations.removeLast()
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

        let toolbarH: CGFloat = 52
        let minW: CGFloat = 720
        let minH: CGFloat = 480

        let maxW = targetScreen.visibleFrame.width * 0.90
        let maxH = targetScreen.visibleFrame.height * 0.90

        let desiredW = min(max(image.size.width + 80, minW), maxW)
        let desiredH = min(max(image.size.height + toolbarH + 80, minH), maxH)

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

    public func close() {
        window?.orderOut(nil)
        window = nil
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

// MARK: - Root View with Shottr-Style Unified Toolbar
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

            // Transparent Checkerboard Canvas
            CheckerboardCanvasView(state: state)
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

            // Left Cluster: Copy, Save, Pin, Crop
            HStack(spacing: 6) {
                // Copy Button
                toolbarIconButton(icon: "doc.on.doc", tooltip: "Copy flattened image (⌘C)") {
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

                // Zoom
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
        guard let img = state.image else { return }
        let pboard = NSPasteboard.general
        pboard.clearContents()
        if let tiff = img.tiffRepresentation {
            pboard.setData(tiff, forType: .tiff)
            NSSound.beep()
            ToastHUDController.shared.showSimpleToast(message: "Image copied to clipboard", icon: "doc.on.doc")
        }
    }

    private func savePNGToDownloads() {
        guard let img = state.image,
              let tiff = img.tiffRepresentation,
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

// MARK: - Interactive Checkerboard Canvas
public struct CheckerboardCanvasView: View {
    @ObservedObject var state: ScreenshotEditorState

    public var body: some View {
        GeometryReader { geo in
            ZStack {
                // Background Checkerboard Grid Pattern
                CheckerboardPattern()
                    .fill(Color.primary.opacity(0.03))
                    .background(Color(NSColor.underPageBackgroundColor))

                if let img = state.image {
                    ZStack {
                        // Base Image
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .shadow(color: Color.black.opacity(0.18), radius: 10, y: 4)

                        // Rendered Vector Annotations Layer
                        Canvas { context, size in
                            for ann in state.annotations {
                                drawAnnotation(ann, in: &context, size: size)
                            }

                            // Live Drag Preview
                            if let s = state.dragStart, let c = state.dragCurrent {
                                let live = CanvasAnnotation(
                                    tool: state.currentTool,
                                    startPoint: s,
                                    endPoint: c,
                                    number: state.nextPinNumber
                                )
                                drawAnnotation(live, in: &context, size: size)
                            }
                        }
                    }
                    .frame(width: min(img.size.width, geo.size.width - 40), height: min(img.size.height, geo.size.height - 40))
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { val in
                                if state.dragStart == nil { state.dragStart = val.startLocation }
                                state.dragCurrent = val.location
                            }
                            .onEnded { val in
                                if let s = state.dragStart {
                                    let ann = CanvasAnnotation(
                                        tool: state.currentTool,
                                        startPoint: s,
                                        endPoint: val.location,
                                        number: state.nextPinNumber
                                    )
                                    if state.currentTool == .numberedPin {
                                        state.nextPinNumber += 1
                                    }
                                    state.annotations.append(ann)
                                }
                                state.dragStart = nil
                                state.dragCurrent = nil
                            }
                    )
                }
            }
        }
    }

    private func drawAnnotation(_ ann: CanvasAnnotation, in context: inout GraphicsContext, size: CGSize) {
        let accent = Color(red: 10/255, green: 132/255, blue: 255/255)

        switch ann.tool {
        case .distance:
            // Dimension Line: |<--- 148px --->|
            let dx = ann.endPoint.x - ann.startPoint.x
            let dy = ann.endPoint.y - ann.startPoint.y
            let dist = Int(sqrt(dx*dx + dy*dy))

            var linePath = Path()
            linePath.move(to: ann.startPoint)
            linePath.addLine(to: ann.endPoint)
            context.stroke(linePath, with: .color(accent), lineWidth: 1.5)

            // Start tick
            var tickStart = Path()
            tickStart.move(to: CGPoint(x: ann.startPoint.x, y: ann.startPoint.y - 5))
            tickStart.addLine(to: CGPoint(x: ann.startPoint.x, y: ann.startPoint.y + 5))
            context.stroke(tickStart, with: .color(accent), lineWidth: 1.5)

            // End tick
            var tickEnd = Path()
            tickEnd.move(to: CGPoint(x: ann.endPoint.x, y: ann.endPoint.y - 5))
            tickEnd.addLine(to: CGPoint(x: ann.endPoint.x, y: ann.endPoint.y + 5))
            context.stroke(tickEnd, with: .color(accent), lineWidth: 1.5)

            // Distance Pill Badge
            let mid = CGPoint(x: (ann.startPoint.x + ann.endPoint.x)/2, y: (ann.startPoint.y + ann.endPoint.y)/2)
            let badgeRect = CGRect(x: mid.x - 22, y: mid.y - 10, width: 44, height: 20)
            context.fill(Path(roundedRect: badgeRect, cornerRadius: 4), with: .color(accent))
            context.draw(
                Text("\(dist)px").font(.system(size: 10, weight: .bold)).foregroundColor(.white),
                at: mid
            )

        case .arrow:
            var path = Path()
            path.move(to: ann.startPoint)
            path.addLine(to: ann.endPoint)
            context.stroke(path, with: .color(accent), lineWidth: 2)

            // Arrow head
            let angle = atan2(ann.endPoint.y - ann.startPoint.y, ann.endPoint.x - ann.startPoint.x)
            let headLen: CGFloat = 10
            var head = Path()
            head.move(to: ann.endPoint)
            head.addLine(to: CGPoint(x: ann.endPoint.x - headLen * cos(angle - .pi/6), y: ann.endPoint.y - headLen * sin(angle - .pi/6)))
            head.addLine(to: CGPoint(x: ann.endPoint.x - headLen * cos(angle + .pi/6), y: ann.endPoint.y - headLen * sin(angle + .pi/6)))
            head.closeSubpath()
            context.fill(head, with: .color(accent))

        case .rectangle:
            let r = CGRect(
                x: min(ann.startPoint.x, ann.endPoint.x),
                y: min(ann.startPoint.y, ann.endPoint.y),
                width: abs(ann.endPoint.x - ann.startPoint.x),
                height: abs(ann.endPoint.y - ann.startPoint.y)
            )
            context.stroke(Path(r), with: .color(accent), lineWidth: 1.8)

            // Dimension label
            let dimText = "\(Int(r.width)) × \(Int(r.height)) pt"
            let tagRect = CGRect(x: r.minX, y: r.minY - 18, width: 80, height: 16)
            context.fill(Path(roundedRect: tagRect, cornerRadius: 3), with: .color(.black.opacity(0.85)))
            context.draw(Text(dimText).font(.system(size: 9, weight: .bold)).foregroundColor(.white), at: CGPoint(x: tagRect.midX, y: tagRect.midY))

        case .numberedPin:
            let center = ann.startPoint
            let circleRect = CGRect(x: center.x - 11, y: center.y - 11, width: 22, height: 22)
            context.fill(Path(ellipseIn: circleRect), with: .color(accent))
            context.stroke(Path(ellipseIn: circleRect), with: .color(.white), lineWidth: 1.5)
            context.draw(
                Text("\(ann.number)").font(.system(size: 11, weight: .bold)).foregroundColor(.white),
                at: center
            )

        case .blur:
            let r = CGRect(
                x: min(ann.startPoint.x, ann.endPoint.x),
                y: min(ann.startPoint.y, ann.endPoint.y),
                width: abs(ann.endPoint.x - ann.startPoint.x),
                height: abs(ann.endPoint.y - ann.startPoint.y)
            )
            context.fill(Path(r), with: .color(.black.opacity(0.65)))

        default:
            break
        }
    }
}

// MARK: - Checkerboard Pattern Shape
private struct CheckerboardPattern: Shape {
    let tileSize: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cols = Int(ceil(rect.width / tileSize))
        let rows = Int(ceil(rect.height / tileSize))

        for row in 0..<rows {
            for col in 0..<cols {
                if (row + col) % 2 == 0 {
                    path.addRect(CGRect(
                        x: CGFloat(col) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    ))
                }
            }
        }
        return path
    }
}
