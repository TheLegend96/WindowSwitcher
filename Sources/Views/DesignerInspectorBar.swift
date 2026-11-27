import AppKit
import SwiftUI

// MARK: - Live NSColorPanel Bridge (Native macOS Color Picker & Eyedropper)
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

// MARK: - Tapered Wedge Thickness Slider (Figma / Shottr Style with Crisp Tabular Readout)
public struct TaperedThicknessSlider: View {
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    var unit: String = "px"
    var onBeginEdit: (() -> Void)? = nil
    var onValueChanged: ((CGFloat) -> Void)? = nil

    private let dragFlag = SliderDragFlag()

    public var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let height = geo.size.height
                let normalized = max(0, min(1, (value - range.lowerBound) / max(0.001, range.upperBound - range.lowerBound)))
                let thumbX = 7 + normalized * max(1, width - 14)

                ZStack(alignment: .leading) {
                    // Track contour clipped cleanly to the wedge
                    TaperedWedgeShape()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 14)

                    // Active Cobalt Azure fill clipped accurately inside wedge geometry
                    TaperedWedgeShape()
                        .fill(Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.36))
                        .frame(height: 14)
                        .mask(
                            TaperedWedgeShape()
                                .frame(height: 14)
                                .overlay(alignment: .leading) {
                                    EmptyView()
                                }
                                .mask(
                                    HStack(spacing: 0) {
                                        Rectangle().frame(width: thumbX)
                                        Spacer(minLength: 0)
                                    }
                                )
                        )

                    TaperedWedgeShape()
                        .stroke(Color.primary.opacity(0.18), lineWidth: 0.75)
                        .frame(height: 14)

                    // Machined circular Apple thumb
                    Circle()
                        .fill(Color.white)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(Color.black.opacity(0.20), lineWidth: 0.75))
                        .shadow(color: Color.black.opacity(0.14), radius: 2, y: 0.75)
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
            .frame(width: 96, height: 24)
            .help("Drag to adjust size")

            Text(verbatim: "\(Int(round(value))) \(unit)")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(minWidth: 30, alignment: .leading)
        }
    }
}

private struct TaperedWedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY
        let leftHalf: CGFloat = 1.5
        let rightHalf: CGFloat = min(6.2, rect.height * 0.44)
        p.move(to: CGPoint(x: rect.minX + 3, y: midY - leftHalf))
        p.addLine(to: CGPoint(x: rect.maxX - 4, y: midY - rightHalf))
        p.addArc(
            center: CGPoint(x: rect.maxX - 4, y: midY),
            radius: rightHalf,
            startAngle: .degrees(-90),
            endAngle: .degrees(90),
            clockwise: false
        )
        p.addLine(to: CGPoint(x: rect.minX + 3, y: midY + leftHalf))
        p.addArc(
            center: CGPoint(x: rect.minX + 3, y: midY),
            radius: leftHalf,
            startAngle: .degrees(90),
            endAngle: .degrees(270),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Apple Color Well Swatch + Native Mac Custom Color Picker
public struct DesignerColorSwatchButton: View {
    @Binding var selectedColor: NSColor
    @Binding var isPresented: Bool
    var onBeginEdit: (() -> Void)? = nil
    var onColorSelected: ((NSColor) -> Void)? = nil

    public var body: some View {
        Button(action: { isPresented.toggle() }) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.75))

                Circle()
                    .fill(Color(selectedColor))
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(
                                selectedColor.relativeLuminance > 0.85
                                    ? Color.black.opacity(0.16)
                                    : Color.black.opacity(0.08),
                                lineWidth: 0.75
                            )
                    )
            }
            .shadow(color: Color.black.opacity(0.06), radius: 1, y: 0.5)
        }
        .buttonStyle(.plain)
        .help("Choose color or open custom color wheel")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Color")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(verbatim: selectedColor.hexString)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Curated 4x2 Designer Swatches
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(26), spacing: 8), count: 4), spacing: 8) {
                    ForEach(DesignerColorPreset.curated) { preset in
                        let isSelected = selectedColor.hexString == preset.hex
                        Button(action: {
                            onBeginEdit?()
                            selectedColor = preset.nsColor
                            onColorSelected?(preset.nsColor)
                            isPresented = false
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(preset.color)
                                    .frame(width: 26, height: 26)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(
                                                isSelected
                                                    ? Color(red: 10/255, green: 132/255, blue: 255/255)
                                                    : Color.primary.opacity(preset.nsColor.relativeLuminance > 0.85 ? 0.22 : 0.14),
                                                lineWidth: isSelected ? 2.0 : 0.75
                                            )
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
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundColor(Color(red: 10/255, green: 132/255, blue: 255/255))
                        Text("Custom Color...")
                            .font(.system(size: 11.5, weight: .medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(12)
            .frame(width: 158)
        }
    }
}

// MARK: - Custom Arrow Style Vector Glyphs
private struct ArrowStyleGlyph: View {
    let style: ArrowStyle
    let isActive: Bool

    var body: some View {
        Canvas { ctx, size in
            let fg: Color = isActive ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.78)
            let midY = size.height / 2

            switch style {
            case .tapered:
                var p = Path()
                p.move(to: CGPoint(x: 3, y: midY - 0.9))
                p.addLine(to: CGPoint(x: 11, y: midY - 2.4))
                p.addLine(to: CGPoint(x: 10, y: midY - 5.0))
                p.addLine(to: CGPoint(x: 17, y: midY))
                p.addLine(to: CGPoint(x: 10, y: midY + 5.0))
                p.addLine(to: CGPoint(x: 11, y: midY + 2.4))
                p.addLine(to: CGPoint(x: 3, y: midY + 0.9))
                p.closeSubpath()
                ctx.fill(p, with: .color(fg))

            case .filledSingle:
                var line = Path()
                line.move(to: CGPoint(x: 3, y: midY))
                line.addLine(to: CGPoint(x: 13, y: midY))
                ctx.stroke(line, with: .color(fg), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))

                var head = Path()
                head.move(to: CGPoint(x: 17, y: midY))
                head.addLine(to: CGPoint(x: 11.5, y: midY - 3.5))
                head.addLine(to: CGPoint(x: 11.5, y: midY + 3.5))
                head.closeSubpath()
                ctx.fill(head, with: .color(fg))

            case .openChevron:
                var line = Path()
                line.move(to: CGPoint(x: 3, y: midY))
                line.addLine(to: CGPoint(x: 16, y: midY))
                ctx.stroke(line, with: .color(fg), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

                var chev = Path()
                chev.move(to: CGPoint(x: 12, y: midY - 3.4))
                chev.addLine(to: CGPoint(x: 16.5, y: midY))
                chev.addLine(to: CGPoint(x: 12, y: midY + 3.4))
                ctx.stroke(chev, with: .color(fg), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            case .doubleEnded:
                var line = Path()
                line.move(to: CGPoint(x: 5, y: midY))
                line.addLine(to: CGPoint(x: 15, y: midY))
                ctx.stroke(line, with: .color(fg), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))

                var leftH = Path()
                leftH.move(to: CGPoint(x: 2.5, y: midY))
                leftH.addLine(to: CGPoint(x: 6.5, y: midY - 3.1))
                leftH.addLine(to: CGPoint(x: 6.5, y: midY + 3.1))
                leftH.closeSubpath()
                ctx.fill(leftH, with: .color(fg))

                var rightH = Path()
                rightH.move(to: CGPoint(x: 17.5, y: midY))
                rightH.addLine(to: CGPoint(x: 13.5, y: midY - 3.1))
                rightH.addLine(to: CGPoint(x: 13.5, y: midY + 3.1))
                rightH.closeSubpath()
                ctx.fill(rightH, with: .color(fg))
            }
        }
        .frame(width: 20, height: 18)
    }
}

// MARK: - Apple HIG Segmented Pill Plate Helper
private struct AppleSegmentedSelectionPlate: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(isSelected ? Color(nsColor: .controlBackgroundColor) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? Color.primary.opacity(0.10) : Color.clear, lineWidth: 0.6)
            )
            .shadow(color: isSelected ? Color.black.opacity(0.08) : .clear, radius: 1.5, y: 0.5)
    }
}

// MARK: - Floating Contextual Properties Inspector Bar (Apple HIG / Figma Craft)
public struct DesignerInspectorBar: View {
    @ObservedObject var state: ScreenshotEditorState

    private var activeInspectorTool: AnnotationTool? {
        if state.isEditingInlineText {
            return .text
        }
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.11), lineWidth: 0.6)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 14, y: 5)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: - Arrow Inspector
    private var arrowControls: some View {
        HStack(spacing: 10) {
            DesignerColorSwatchButton(
                selectedColor: state.activeInspectorColorBinding(for: .arrow),
                isPresented: $state.isColorPopoverOpen,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onColorSelected: { state.applyColor($0, for: .arrow) }
            )

            Divider().frame(height: 16)

            TaperedThicknessSlider(
                value: state.activeWidthBinding(for: .arrow),
                range: 2.0...10.0,
                unit: "px",
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onValueChanged: { state.applyStrokeWidth($0, for: .arrow) }
            )

            Divider().frame(height: 16)

            HStack(spacing: 2) {
                ForEach(ArrowStyle.allCases) { style in
                    let isSelected = state.currentArrowStyle == style
                    Button(action: {
                        state.beginPropertyEditUndoIfNeeded()
                        state.applyArrowStyle(style)
                    }) {
                        ArrowStyleGlyph(style: style, isActive: isSelected)
                            .frame(width: 28, height: 24)
                            .background(AppleSegmentedSelectionPlate(isSelected: isSelected))
                    }
                    .buttonStyle(.plain)
                    .help(style.rawValue)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))

            if state.selectedAnnotationIndex != nil {
                Button(action: { state.flipSelectedArrowDirection() }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary.opacity(0.82))
                        .frame(width: 26, height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("Flip arrow direction")
            }
        }
    }

    // MARK: - Text Inspector
    private var textControls: some View {
        HStack(spacing: 10) {
            DesignerColorSwatchButton(
                selectedColor: state.activeInspectorColorBinding(for: .text),
                isPresented: $state.isColorPopoverOpen,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onColorSelected: { state.applyColor($0, for: .text) }
            )

            Divider().frame(height: 16)

            TaperedThicknessSlider(
                value: state.activeWidthBinding(for: .text),
                range: 11.0...36.0,
                unit: "pt",
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onValueChanged: { state.applyStrokeWidth($0, for: .text) }
            )

            Divider().frame(height: 16)

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
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        }
                        .foregroundColor(isSelected ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.82))
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(AppleSegmentedSelectionPlate(isSelected: isSelected))
                    }
                    .buttonStyle(.plain)
                    .help(style.rawValue)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))

            if state.isEditingInlineText {
                Divider().frame(height: 16)

                Button(action: { state.onCommitInlineText?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("Done")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(red: 10/255, green: 132/255, blue: 255/255))
                    )
                }
                .buttonStyle(.plain)
                .help("Finish typing (Return)")
            }
        }
    }

    private func textStyleIcon(_ style: TextStyle) -> String {
        switch style {
        case .plain: return "textformat"
        case .card: return "capsule"
        case .quoteBubble: return "quote.bubble"
        }
    }

    private func textStyleShortLabel(_ style: TextStyle) -> String {
        switch style {
        case .plain: return "Plain"
        case .card: return "Pill"
        case .quoteBubble: return "Quote"
        }
    }

    // MARK: - Rectangle Inspector
    private var rectangleControls: some View {
        HStack(spacing: 10) {
            DesignerColorSwatchButton(
                selectedColor: state.activeInspectorColorBinding(for: .rectangle),
                isPresented: $state.isColorPopoverOpen,
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onColorSelected: { state.applyColor($0, for: .rectangle) }
            )

            if state.currentRectFillMode != .solid {
                Divider().frame(height: 16)

                TaperedThicknessSlider(
                    value: state.activeWidthBinding(for: .rectangle),
                    range: 1.0...12.0,
                    unit: "px",
                    onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                    onValueChanged: { state.applyStrokeWidth($0, for: .rectangle) }
                )
            }

            Divider().frame(height: 16)

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
                                .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                        }
                        .foregroundColor(isSelected ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.82))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(AppleSegmentedSelectionPlate(isSelected: isSelected))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))

            Divider().frame(height: 16)

            HStack(spacing: 4) {
                Button(action: {
                    state.beginPropertyEditUndoIfNeeded()
                    let nextRadius: CGFloat = state.currentRectCornerRadius > 1 ? 0 : 8
                    state.applyCornerRadius(nextRadius)
                }) {
                    Image(systemName: state.currentRectCornerRadius > 1 ? "app" : "square")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(state.currentRectCornerRadius > 1 ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.8))
                        .frame(width: 26, height: 24)
                        .background(AppleSegmentedSelectionPlate(isSelected: state.currentRectCornerRadius > 1))
                }
                .buttonStyle(.plain)
                .help(state.currentRectCornerRadius > 1 ? "Rounded corners (8px) — Click for sharp" : "Sharp corners — Click for rounded (8px)")

                Button(action: {
                    state.beginPropertyEditUndoIfNeeded()
                    state.toggleRectSizeTag()
                }) {
                    Text("W×H")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(state.currentRectShowSizeTag ? Color(red: 10/255, green: 132/255, blue: 255/255) : .primary.opacity(0.8))
                        .padding(.horizontal, 7)
                        .frame(height: 24)
                        .background(AppleSegmentedSelectionPlate(isSelected: state.currentRectShowSizeTag))
                }
                .buttonStyle(.plain)
                .help("Show width × height dimension badge")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
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

            Divider().frame(height: 16)

            Text("H / V UI edge snap  •  Hold ⌘ for free pixel")
                .font(.system(size: 11.5, weight: .medium))
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
            Divider().frame(height: 16)
            Text("Click anywhere to drop pin #\(state.nextPinNumber)")
                .font(.system(size: 11.5, weight: .medium))
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
            Divider().frame(height: 16)
            TaperedThicknessSlider(
                value: state.activeWidthBinding(for: .pencil),
                range: 4.0...28.0,
                unit: "px",
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onValueChanged: { state.applyStrokeWidth($0, for: .pencil) }
            )
        }
    }

    private var blurControls: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkerboard.rectangle")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Drag across sensitive text or fields to redact with mosaic pixels")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
