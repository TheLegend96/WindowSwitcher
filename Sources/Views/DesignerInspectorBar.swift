import AppKit
import SwiftUI

// MARK: - Live NSColorPanel Bridge (Native macOS Color Picker)
@MainActor
public final class DesignerColorPanelController: NSObject, ObservableObject {
    public static let shared = DesignerColorPanelController()
    private var changeHandler: ((NSColor) -> Void)?
    private var observerToken: Any?

    private override init() {
        super.init()
    }

    public func openPanel(initialColor: NSColor, onChange: @escaping (NSColor) -> Void) {
        self.changeHandler = onChange
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = initialColor

        if observerToken == nil {
            observerToken = NotificationCenter.default.addObserver(
                forName: NSColorPanel.colorDidChangeNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    let picked = NSColorPanel.shared.color.usingColorSpace(.sRGB) ?? NSColorPanel.shared.color
                    self?.changeHandler?(picked)
                }
            }
        }

        panel.orderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func clearHandler() {
        changeHandler = nil
    }
}

private final class SliderDragFlag {
    var active = false
}

// MARK: - Tapered Wedge Thickness Slider (Figma / Shottr Style)
public struct TaperedThicknessSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var onBeginEdit: (() -> Void)? = nil
    var onValueChanged: ((CGFloat) -> Void)? = nil

    private let dragFlag = SliderDragFlag()

    public var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let height = geo.size.height
            let normalized = max(0, min(1, (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)))
            let thumbX = 7 + normalized * max(1, width - 14)

            ZStack(alignment: .leading) {
                // Full tapered wedge background outline
                TaperedWedgeShape()
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        TaperedWedgeShape()
                            .stroke(Color.primary.opacity(0.22), lineWidth: 0.9)
                    )
                    .frame(height: 14)

                // Active filled portion up to thumb
                TaperedWedgeShape()
                    .fill(Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.32))
                    .mask(
                        HStack(spacing: 0) {
                            Rectangle().frame(width: thumbX)
                            Spacer(minLength: 0)
                        }
                    )
                    .frame(height: 14)

                // Draggable circular white thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 15, height: 15)
                    .overlay(Circle().stroke(Color.black.opacity(0.18), lineWidth: 0.8))
                    .shadow(color: Color.black.opacity(0.18), radius: 2, y: 1)
                    .position(x: thumbX, y: height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !dragFlag.active {
                            dragFlag.active = true
                            onBeginEdit?()
                        }
                        let rawNorm = (val.location.x - 7) / max(1, width - 14)
                        let clamped = max(0, min(1, rawNorm))
                        let newVal = range.lowerBound + clamped * (range.upperBound - range.lowerBound)
                        value = newVal
                        onValueChanged?(newVal)
                    }
                    .onEnded { _ in
                        dragFlag.active = false
                    }
            )
        }
        .frame(width: 104, height: 24)
        .help("Drag to adjust size / thickness")
    }
}

private struct TaperedWedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let leftHalf: CGFloat = 1.4
        let rightHalf: CGFloat = min(6.5, rect.height * 0.46)
        p.move(to: CGPoint(x: rect.minX + 4, y: midY - leftHalf))
        p.addLine(to: CGPoint(x: rect.maxX - 4, y: midY - rightHalf))
        p.addArc(
            center: CGPoint(x: rect.maxX - 4, y: midY),
            radius: rightHalf,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX + 4, y: midY + leftHalf))
        p.addArc(
            center: CGPoint(x: rect.minX + 4, y: midY),
            radius: leftHalf,
            startAngle: .degrees(90),
            endAngle: .degrees(270),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Color Swatch Popover + Native Mac Custom Color Picker
public struct DesignerColorSwatchButton: View {
    @Binding var selectedColor: NSColor
    @Binding var isPresented: Bool
    var onBeginEdit: (() -> Void)? = nil
    var onColorSelected: ((NSColor) -> Void)? = nil

    public var body: some View {
        Button(action: { isPresented.toggle() }) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color(selectedColor))
                .frame(width: 22, height: 22)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.24), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 1.5, y: 0.5)
        }
        .buttonStyle(.plain)
        .help("Choose color or open custom color picker")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Color")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(verbatim: selectedColor.hexString)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Curated 4x2 Designer Swatches
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 8), count: 4), spacing: 8) {
                    ForEach(DesignerColorPreset.curated) { preset in
                        let isSelected = selectedColor.hexString == preset.hex
                        Button(action: {
                            onBeginEdit?()
                            selectedColor = preset.nsColor
                            onColorSelected?(preset.nsColor)
                            isPresented = false
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(preset.color)
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.primary.opacity(isSelected ? 0.85 : 0.18), lineWidth: isSelected ? 1.8 : 0.8)
                                    )
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(preset.nsColor.relativeLuminance > 0.6 ? .black : .white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                }

                Divider()

                // Native macOS Color Wheel / Eyedropper Trigger
                Button(action: {
                    isPresented = false
                    var pushedForPanel = false
                    DesignerColorPanelController.shared.openPanel(initialColor: selectedColor) { picked in
                        if !pushedForPanel {
                            pushedForPanel = true
                            onBeginEdit?()
                        }
                        selectedColor = picked
                        onColorSelected?(picked)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "eyedropper")
                            .font(.system(size: 11, weight: .medium))
                        Text("Custom Color...")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(width: 148)
        }
    }
}

// MARK: - Custom Arrow Style Vector Glyphs (Matching Reference UI)
private struct ArrowStyleGlyph: View {
    let style: ArrowStyle
    let isActive: Bool

    var body: some View {
        Canvas { ctx, size in
            let fg: Color = isActive ? .white : .primary.opacity(0.82)
            let midY = size.height / 2

            switch style {
            case .tapered:
                var p = Path()
                p.move(to: CGPoint(x: 3, y: midY - 1))
                p.addLine(to: CGPoint(x: 11, y: midY - 2.6))
                p.addLine(to: CGPoint(x: 10, y: midY - 5.2))
                p.addLine(to: CGPoint(x: 17, y: midY))
                p.addLine(to: CGPoint(x: 10, y: midY + 5.2))
                p.addLine(to: CGPoint(x: 11, y: midY + 2.6))
                p.addLine(to: CGPoint(x: 3, y: midY + 1))
                p.closeSubpath()
                ctx.fill(p, with: .color(fg))

            case .filledSingle:
                var line = Path()
                line.move(to: CGPoint(x: 3, y: midY))
                line.addLine(to: CGPoint(x: 13, y: midY))
                ctx.stroke(line, with: .color(fg), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

                var head = Path()
                head.move(to: CGPoint(x: 17, y: midY))
                head.addLine(to: CGPoint(x: 11.5, y: midY - 3.6))
                head.addLine(to: CGPoint(x: 11.5, y: midY + 3.6))
                head.closeSubpath()
                ctx.fill(head, with: .color(fg))

            case .openChevron:
                var line = Path()
                line.move(to: CGPoint(x: 3, y: midY))
                line.addLine(to: CGPoint(x: 16, y: midY))
                ctx.stroke(line, with: .color(fg), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

                var chev = Path()
                chev.move(to: CGPoint(x: 12, y: midY - 3.5))
                chev.addLine(to: CGPoint(x: 16.5, y: midY))
                chev.addLine(to: CGPoint(x: 12, y: midY + 3.5))
                ctx.stroke(chev, with: .color(fg), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            case .doubleEnded:
                var line = Path()
                line.move(to: CGPoint(x: 5, y: midY))
                line.addLine(to: CGPoint(x: 15, y: midY))
                ctx.stroke(line, with: .color(fg), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                var leftH = Path()
                leftH.move(to: CGPoint(x: 2.5, y: midY))
                leftH.addLine(to: CGPoint(x: 6.5, y: midY - 3.2))
                leftH.addLine(to: CGPoint(x: 6.5, y: midY + 3.2))
                leftH.closeSubpath()
                ctx.fill(leftH, with: .color(fg))

                var rightH = Path()
                rightH.move(to: CGPoint(x: 17.5, y: midY))
                rightH.addLine(to: CGPoint(x: 13.5, y: midY - 3.2))
                rightH.addLine(to: CGPoint(x: 13.5, y: midY + 3.2))
                rightH.closeSubpath()
                ctx.fill(rightH, with: .color(fg))
            }
        }
        .frame(width: 20, height: 18)
    }
}

// MARK: - Floating Contextual Properties Inspector Bar (Figma / Shottr Style)
public struct DesignerInspectorBar: View {
    @ObservedObject var state: ScreenshotEditorState

    private var activeInspectorTool: AnnotationTool? {
        if let idx = state.selectedAnnotationIndex, idx >= 0 && idx < state.annotations.count {
            return state.annotations[idx].tool
        }
        if state.currentTool == .pointer {
            return nil
        }
        return state.currentTool
    }

    public var body: some View {
        if let tool = activeInspectorTool {
            HStack(spacing: 10) {
                switch tool {
                case .arrow:
                    arrowControls
                case .text:
                    textControls
                case .rectangle:
                    rectangleControls
                case .distance:
                    rulerControls
                case .numberedPin:
                    pinControls
                case .pencil:
                    highlighterControls
                case .blur:
                    blurControls
                case .pointer:
                    EmptyView()
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 12, y: 4)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Arrow Inspector (Color | Tapered Width | 4 Arrow Styles | Flip Ends)
    private var arrowControls: some View {
        HStack(spacing: 10) {
            DesignerColorSwatchButton(
                selectedColor: state.activeInspectorColorBinding(for: .arrow),
                isPresented: $state.isColorPopoverOpen,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onColorSelected: { state.applyColor($0, for: .arrow) }
            )

            TaperedThicknessSlider(
                value: state.activeWidthBinding(for: .arrow),
                range: 2.0...10.0,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onValueChanged: { state.applyStrokeWidth($0, for: .arrow) }
            )

            // 4 Arrow Styles Segmented Control
            HStack(spacing: 2) {
                ForEach(ArrowStyle.allCases) { style in
                    let isSelected = state.currentArrowStyle == style
                    Button(action: {
                        state.beginPropertyEditUndoIfNeeded()
                        state.applyArrowStyle(style)
                    }) {
                        ArrowStyleGlyph(style: style, isActive: isSelected)
                            .frame(width: 26, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(isSelected ? Color(red: 10/255, green: 132/255, blue: 255/255) : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(style.rawValue)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))

            if state.selectedAnnotationIndex != nil {
                Button(action: { state.flipSelectedArrowDirection() }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary.opacity(0.8))
                        .frame(width: 24, height: 22)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Flip arrow direction")
            }
        }
    }

    // MARK: - Text Inspector (Color | Font Size Slider | Plain vs Badge Pill vs Speech Quote)
    private var textControls: some View {
        HStack(spacing: 10) {
            DesignerColorSwatchButton(
                selectedColor: state.activeInspectorColorBinding(for: .text),
                isPresented: $state.isColorPopoverOpen,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onColorSelected: { state.applyColor($0, for: .text) }
            )

            TaperedThicknessSlider(
                value: state.activeWidthBinding(for: .text),
                range: 11.0...34.0,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onValueChanged: { state.applyStrokeWidth($0, for: .text) }
            )

            HStack(spacing: 2) {
                ForEach(TextStyle.allCases) { style in
                    let isSelected = state.currentTextStyle == style
                    Button(action: {
                        state.beginPropertyEditUndoIfNeeded()
                        state.applyTextStyle(style)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: textStyleIcon(style))
                                .font(.system(size: 11, weight: .medium))
                            Text(textStyleShortLabel(style))
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(isSelected ? .white : .primary.opacity(0.85))
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? Color(red: 10/255, green: 132/255, blue: 255/255) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                    .help(style.rawValue)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
        }
    }

    private func textStyleIcon(_ style: TextStyle) -> String {
        switch style {
        case .plain: return "textformat"
        case .card: return "rectangle.fill"
        case .quoteBubble: return "text.bubble.fill"
        }
    }

    private func textStyleShortLabel(_ style: TextStyle) -> String {
        switch style {
        case .plain: return "Text"
        case .card: return "Pill"
        case .quoteBubble: return "Quote"
        }
    }

    // MARK: - Rectangle Inspector (Color | Stroke Width | Stroke vs Tinted vs Solid | Corners | Size Tag)
    private var rectangleControls: some View {
        HStack(spacing: 10) {
            DesignerColorSwatchButton(
                selectedColor: state.activeInspectorColorBinding(for: .rectangle),
                isPresented: $state.isColorPopoverOpen,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onColorSelected: { state.applyColor($0, for: .rectangle) }
            )

            if state.currentRectFillMode != .solid {
                TaperedThicknessSlider(
                    value: state.activeWidthBinding(for: .rectangle),
                    range: 1.0...12.0,
                    onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                    onValueChanged: { state.applyStrokeWidth($0, for: .rectangle) }
                )
            }

            // Fill Mode Segmented Control: Stroke | Tint | Solid
            HStack(spacing: 2) {
                ForEach(RectFillMode.allCases) { mode in
                    let isSelected = state.currentRectFillMode == mode
                    Button(action: {
                        state.beginPropertyEditUndoIfNeeded()
                        state.applyRectFillMode(mode)
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: rectFillIcon(mode))
                                .font(.system(size: 11, weight: .medium))
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(isSelected ? .white : .primary.opacity(0.85))
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? Color(red: 10/255, green: 132/255, blue: 255/255) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))

            // Corner Radius Toggle: Sharp (0px) vs Rounded (8px)
            Button(action: {
                state.beginPropertyEditUndoIfNeeded()
                let nextRadius: CGFloat = state.currentRectCornerRadius > 1 ? 0 : 8
                state.applyCornerRadius(nextRadius)
            }) {
                Image(systemName: state.currentRectCornerRadius > 1 ? "app" : "square")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(state.currentRectCornerRadius > 1 ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.8))
                    .frame(width: 24, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help(state.currentRectCornerRadius > 1 ? "Rounded corners (8px) — Click for sharp" : "Sharp corners — Click for rounded (8px)")

            // Show Width × Height Size Badge Toggle
            Button(action: {
                state.beginPropertyEditUndoIfNeeded()
                state.toggleRectSizeTag()
            }) {
                Text("W×H")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(state.currentRectShowSizeTag ? .white : .primary.opacity(0.8))
                    .padding(.horizontal, 6)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(state.currentRectShowSizeTag ? Color(red: 10/255, green: 132/255, blue: 255/255) : Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("Show width × height dimension badge")
        }
    }

    private func rectFillIcon(_ mode: RectFillMode) -> String {
        switch mode {
        case .stroke: return "rectangle"
        case .tinted: return "rectangle.inset.filled"
        case .solid: return "rectangle.fill"
        }
    }

    // MARK: - Ruler Inspector
    private var rulerControls: some View {
        HStack(spacing: 10) {
            DesignerColorSwatchButton(
                selectedColor: state.activeInspectorColorBinding(for: .distance),
                isPresented: $state.isColorPopoverOpen,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onColorSelected: { state.applyColor($0, for: .distance) }
            )

            Text("H / V UI edge snap • Hold ⌘ for free pixel")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Pin / Highlighter / Blur Inspectors
    private var pinControls: some View {
        HStack(spacing: 10) {
            DesignerColorSwatchButton(
                selectedColor: state.activeInspectorColorBinding(for: .numberedPin),
                isPresented: $state.isColorPopoverOpen,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onColorSelected: { state.applyColor($0, for: .numberedPin) }
            )
            Text("Click anywhere to drop pin #\(state.nextPinNumber)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var highlighterControls: some View {
        HStack(spacing: 10) {
            DesignerColorSwatchButton(
                selectedColor: state.activeInspectorColorBinding(for: .pencil),
                isPresented: $state.isColorPopoverOpen,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onColorSelected: { state.applyColor($0, for: .pencil) }
            )
            TaperedThicknessSlider(
                value: state.activeWidthBinding(for: .pencil),
                range: 4.0...28.0,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onValueChanged: { state.applyStrokeWidth($0, for: .pencil) }
            )
        }
    }

    private var blurControls: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkerboard.rectangle")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
            Text("Drag across sensitive text to redact with mosaic pixels")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
