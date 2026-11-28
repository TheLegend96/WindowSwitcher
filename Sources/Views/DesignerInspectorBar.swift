import AppKit
import SwiftUI

// MARK: - In-Popover Expandable Color Picker State (Zero NSColorPanel Window, Zero @State macro)

public final class ColorPickerPopoverUIState: ObservableObject {
    @Published public var showCustomSpectrum: Bool = false
    @Published public var hue: Double = 0.58
    @Published public var saturation: Double = 0.90
    @Published public var brightness: Double = 1.0
    @Published public var hexText: String = "#0A84FF"

    public init() {}

    public func sync(from color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 1
        srgb.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        if s > 0.01 { self.hue = Double(h) }
        self.saturation = Double(s)
        self.brightness = Double(b)
        self.hexText = srgb.hexString
    }

    public func currentNSColor() -> NSColor {
        let calibrated = NSColor(
            calibratedHue: CGFloat(hue),
            saturation: CGFloat(saturation),
            brightness: CGFloat(brightness),
            alpha: 1.0
        )
        return calibrated.usingColorSpace(.sRGB) ?? calibrated
    }
}

private final class SliderDragFlag {
    var active = false
}

// MARK: - Tapered Thickness Slider

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
                    TaperedWedgeShape()
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 14)

                    TaperedWedgeShape()
                        .fill(Color(red: 10/255, green: 132/255, blue: 255/255).opacity(0.32))
                        .frame(height: 14)
                        .mask(
                            HStack(spacing: 0) {
                                Rectangle().frame(width: thumbX)
                                Spacer(minLength: 0)
                            }
                        )

                    TaperedWedgeShape()
                        .stroke(Color.primary.opacity(0.16), lineWidth: 0.75)
                        .frame(height: 14)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Color.black.opacity(0.22), lineWidth: 0.75))
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
            .frame(width: 90, height: 22)

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
        let rightHalf: CGFloat = min(6.0, rect.height * 0.44)
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

// MARK: - Inline Expandable Figma-Style Color Picker Popover

public struct DesignerColorSwatchButton: View {
    @Binding var selectedColor: NSColor
    @Binding var isPresented: Bool
    @ObservedObject var pickerState: ColorPickerPopoverUIState
    var size: CGFloat = 22
    var onBeginEdit: (() -> Void)? = nil
    var onColorSelected: ((NSColor) -> Void)? = nil

    private let spectrumDragFlag = SliderDragFlag()

    public var body: some View {
        Button(action: {
            pickerState.sync(from: selectedColor)
            isPresented.toggle()
        }) {
            ZStack {
                Circle()
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(Color.primary.opacity(0.18), lineWidth: 0.75))

                Circle()
                    .fill(Color(selectedColor))
                    .frame(width: size - 6, height: size - 6)
                    .overlay(
                        Circle()
                            .stroke(
                                selectedColor.relativeLuminance > 0.85
                                    ? Color.black.opacity(0.18)
                                    : Color.black.opacity(0.08),
                                lineWidth: 0.75
                            )
                    )
            }
        }
        .buttonStyle(.plain)
        .help("Choose color")
        .onChange(of: isPresented) { _, open in
            if open {
                pickerState.sync(from: selectedColor)
            }
        }
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 11) {
                // Header
                HStack(alignment: .center) {
                    Text("Color")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Text(verbatim: selectedColor.hexString)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.06)))
                }

                // 4x2 Quick Presets
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                    ForEach(DesignerColorPreset.curated) { preset in
                        let isSelected = selectedColor.hexString == preset.hex
                        Button(action: {
                            onBeginEdit?()
                            selectedColor = preset.nsColor
                            onColorSelected?(preset.nsColor)
                            pickerState.sync(from: preset.nsColor)
                            if !pickerState.showCustomSpectrum {
                                isPresented = false
                            }
                        }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(preset.color)
                                    .frame(height: 26)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(
                                                isSelected
                                                    ? Color(red: 10/255, green: 132/255, blue: 255/255)
                                                    : Color.primary.opacity(preset.nsColor.relativeLuminance > 0.85 ? 0.22 : 0.12),
                                                lineWidth: isSelected ? 2.0 : 0.75
                                            )
                                    )

                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 9.5, weight: .bold))
                                        .foregroundColor(preset.nsColor.relativeLuminance > 0.6 ? .black : .white)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .help(preset.name)
                    }
                }

                // Inline Toggle Bar to Extend Popover Into Figma Spectrum Picker
                Button(action: {
                    withAnimation(.easeOut(duration: 0.16)) {
                        pickerState.showCustomSpectrum.toggle()
                        if pickerState.showCustomSpectrum {
                            pickerState.sync(from: selectedColor)
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(
                                AngularGradient(
                                    colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                                    center: .center
                                )
                            )
                            .frame(width: 13, height: 13)
                            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))

                        Text("Custom")
                            .font(.system(size: 11.5, weight: .medium))

                        Spacer()

                        Image(systemName: pickerState.showCustomSpectrum ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(pickerState.showCustomSpectrum ? 0.09 : 0.055))
                    )
                }
                .buttonStyle(.plain)

                // Expanded Figma-Style Inline 2D Saturation/Brightness + Hue Picker
                if pickerState.showCustomSpectrum {
                    VStack(spacing: 10) {
                        customSpectrumBox
                        customHueBar

                        HStack(spacing: 8) {
                            Text("Hex")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)

                            TextField("#0A84FF", text: popoverHexBinding)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 11.5, design: .monospaced))
                        }
                    }
                    .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(width: pickerState.showCustomSpectrum ? 228 : 178)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.76))
        }
    }

    private var customSpectrumBox: some View {
        GeometryReader { geo in
            let w: CGFloat = max(1.0, geo.size.width)
            let h: CGFloat = max(1.0, geo.size.height)
            let pureHue = Color(hue: pickerState.hue, saturation: 1.0, brightness: 1.0)
            let fillColor = Color(nsColor: pickerState.currentNSColor())
            let thumbX = max(7.0, min(w - 7.0, CGFloat(pickerState.saturation) * w))
            let thumbY = max(7.0, min(h - 7.0, CGFloat(1.0 - pickerState.brightness) * h))

            ZStack {
                LinearGradient(colors: [.white, pureHue], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)

                Circle()
                    .fill(fillColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 0.75))
                    .position(x: thumbX, y: thumbY)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.75)
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !spectrumDragFlag.active {
                            spectrumDragFlag.active = true
                            onBeginEdit?()
                        }
                        pickerState.saturation = max(0.0, min(1.0, Double(val.location.x / w)))
                        pickerState.brightness = max(0.0, min(1.0, 1.0 - Double(val.location.y / h)))
                        let c = pickerState.currentNSColor()
                        pickerState.hexText = c.hexString
                        selectedColor = c
                        onColorSelected?(c)
                    }
                    .onEnded { _ in
                        spectrumDragFlag.active = false
                    }
            )
        }
        .frame(height: 128)
    }

    private var customHueBar: some View {
        let hueStops: [Color] = [
            Color(hue: 0.0, saturation: 1, brightness: 1),
            Color(hue: 0.17, saturation: 1, brightness: 1),
            Color(hue: 0.33, saturation: 1, brightness: 1),
            Color(hue: 0.50, saturation: 1, brightness: 1),
            Color(hue: 0.67, saturation: 1, brightness: 1),
            Color(hue: 0.83, saturation: 1, brightness: 1),
            Color(hue: 1.0, saturation: 1, brightness: 1)
        ]

        return GeometryReader { geo in
            let w: CGFloat = max(1.0, geo.size.width)
            let thumbX = max(7.0, min(w - 7.0, CGFloat(pickerState.hue) * w))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(colors: hueStops, startPoint: .leading, endPoint: .trailing))
                    .frame(height: 12)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5))

                Circle()
                    .fill(Color(hue: pickerState.hue, saturation: 1, brightness: 1))
                    .frame(width: 15, height: 15)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
                    .overlay(Circle().stroke(Color.black.opacity(0.25), lineWidth: 0.6))
                    .position(x: thumbX, y: geo.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { val in
                        if !spectrumDragFlag.active {
                            spectrumDragFlag.active = true
                            onBeginEdit?()
                        }
                        pickerState.hue = max(0.0, min(0.999, Double(val.location.x / w)))
                        let c = pickerState.currentNSColor()
                        pickerState.hexText = c.hexString
                        selectedColor = c
                        onColorSelected?(c)
                    }
                    .onEnded { _ in
                        spectrumDragFlag.active = false
                    }
            )
        }
        .frame(height: 18)
    }

    private var popoverHexBinding: Binding<String> {
        Binding(
            get: { pickerState.hexText },
            set: { raw in
                pickerState.hexText = raw
                if let parsed = NSColor(hex: raw) {
                    onBeginEdit?()
                    selectedColor = parsed
                    onColorSelected?(parsed)
                    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
                    (parsed.usingColorSpace(.sRGB) ?? parsed).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                    if s > 0.01 { pickerState.hue = Double(h) }
                    pickerState.saturation = Double(s)
                    pickerState.brightness = Double(b)
                }
            }
        )
    }
}

// MARK: - Friendly, Compact Backdrop & Frame Studio Popover (Zero Intimidating Sidebar)

public struct BackdropStudioPopover: View {
    @ObservedObject var state: ScreenshotEditorState
    @ObservedObject private var wallpaperStore = MacWallpaperStore.shared
    @Environment(\.colorScheme) private var colorScheme

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 1. One-Click Cutout & Window Wrapper
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Frame")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    Button(action: { state.onRequestToggleBackgroundRemoval?() }) {
                        HStack(spacing: 5) {
                            if state.isRemovingBackground {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: state.backdropConfig.removeSubjectBackground ? "arrow.uturn.backward" : "scissors")
                                    .font(.system(size: 10.5, weight: .semibold))
                            }
                            Text(
                                state.isRemovingBackground
                                    ? "Cutting out…"
                                    : (state.backdropConfig.removeSubjectBackground ? "Restore Original" : "Remove BG")
                            )
                            .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 9)
                        .frame(height: 23)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(state.backdropConfig.removeSubjectBackground ? 0.12 : 0.06))
                        )
                        .overlay(
                            Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(state.isRemovingBackground)
                }

                // Window Frame Style Segmented Bar (Raw | Card | Window)
                HStack(spacing: 2) {
                    ForEach(WindowFrameStyle.allCases) { style in
                        let active = state.backdropConfig.frameStyle == style
                        Button(action: {
                            state.backdropConfig.frameStyle = style
                            state.onBackdropChanged?()
                        }) {
                            Text(style.rawValue)
                                .font(.system(size: 11.5, weight: active ? .semibold : .regular))
                                .foregroundColor(active ? .primary : .secondary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 24)
                                .background(AppleSegmentedSelectionPlate(isSelected: active))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2.5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.055)))

                if state.backdropConfig.frameStyle == .macOSWindow {
                    HStack(spacing: 8) {
                        TextField("Optional window title", text: Binding(
                            get: { state.backdropConfig.windowTitle },
                            set: {
                                state.backdropConfig.windowTitle = $0
                                state.onBackdropChanged?()
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))

                        Button(action: {
                            state.backdropConfig.useDarkWindowChrome.toggle()
                            state.onBackdropChanged?()
                        }) {
                            Image(systemName: state.backdropConfig.useDarkWindowChrome ? "moon.fill" : "sun.max")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.primary)
                                .frame(width: 26, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Light / Dark window bar")
                    }
                }
            }

            Divider()

            // 2. Canvas Background Picker (None | Gradient | Color | Photo | GIF)
            VStack(alignment: .leading, spacing: 9) {
                Text("Background")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary)

                HStack(spacing: 2) {
                    ForEach(BackdropType.allCases) { mode in
                        let active = state.backdropConfig.backdropType == mode
                        Button(action: {
                            state.backdropConfig.backdropType = mode
                            if mode == .photo && state.backdropConfig.customPhoto == nil {
                                if let def = wallpaperStore.defaultWallpaperImageAndId() {
                                    state.backdropConfig.wallpaperId = def.id
                                    state.backdropConfig.customPhoto = def.image
                                }
                            } else if mode == .gif && state.gifFrames.isEmpty {
                                state.gifFrames = ImageBackdropCompositor.generateBuiltInGIFFrames(presetId: state.backdropConfig.gifPresetId)
                            }
                            state.onBackdropChanged?()
                        }) {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: active ? .semibold : .regular))
                                .foregroundColor(active ? .primary : .secondary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                                .frame(height: 23)
                                .background(AppleSegmentedSelectionPlate(isSelected: active))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(2.5)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.055)))

                switch state.backdropConfig.backdropType {
                case .none:
                    Text("Clean transparent or raw canvas")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                case .gradient:
                    HStack(spacing: 8) {
                        ForEach(BackdropGradientPreset.all) { preset in
                            let selected = state.backdropConfig.gradientId == preset.id
                            Button(action: {
                                state.backdropConfig.gradientId = preset.id
                                state.onBackdropChanged?()
                            }) {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [preset.swiftUIStart, preset.swiftUIEnd],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 28, height: 28)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(
                                                selected ? Color.primary : Color.primary.opacity(0.14),
                                                lineWidth: selected ? 2.0 : 0.6
                                            )
                                    )
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                        }
                        Spacer(minLength: 0)
                    }

                case .solid:
                    HStack(spacing: 8) {
                        ForEach(["#F4F5F7", "#18181B", "#DBEAFE", "#FCE7F3", "#DCFCE7"], id: \.self) { hex in
                            let col = NSColor(hex: hex) ?? .white
                            let selected = state.backdropConfig.solidColor.hexString == col.hexString
                            Button(action: {
                                state.backdropConfig.solidColor = col
                                state.onBackdropChanged?()
                            }) {
                                Circle()
                                    .fill(Color(col))
                                    .frame(width: 24, height: 24)
                                    .overlay(
                                        Circle().strokeBorder(selected ? Color.primary : Color.primary.opacity(0.16), lineWidth: selected ? 2 : 0.7)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()

                        DesignerColorSwatchButton(
                            selectedColor: Binding(
                                get: { state.backdropConfig.solidColor },
                                set: {
                                    state.backdropConfig.solidColor = $0
                                    state.onBackdropChanged?()
                                }
                            ),
                            isPresented: $state.isBackdropColorPopoverOpen,
                            pickerState: state.backdropColorPickerState,
                            size: 24,
                            onColorSelected: {
                                state.backdropConfig.solidColor = $0
                                state.onBackdropChanged?()
                            }
                        )
                    }

                case .photo:
                    VStack(alignment: .leading, spacing: 9) {
                        let galleryPresets = Array(wallpaperStore.presets.prefix(12))
                        if !galleryPresets.isEmpty {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                                ForEach(galleryPresets) { preset in
                                    let isSelected = state.backdropConfig.wallpaperId == preset.id
                                    Button(action: {
                                        if let img = wallpaperStore.loadFullImage(for: preset) {
                                            state.backdropConfig.wallpaperId = preset.id
                                            state.backdropConfig.customPhoto = img
                                            state.backdropConfig.backdropType = .photo
                                            state.onBackdropChanged?()
                                        }
                                    }) {
                                    Color.primary.opacity(0.07)
                                        .frame(height: 30)
                                        .overlay {
                                            if let thumb = wallpaperStore.thumbnails[preset.id] {
                                                Image(nsImage: thumb)
                                                    .resizable()
                                                    .scaledToFill()
                                            }
                                        }
                                        .clipShape(RoundedRectangle(cornerRadius: 6.5, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6.5, style: .continuous)
                                                .strokeBorder(
                                                    isSelected
                                                        ? Color(red: 10/255, green: 132/255, blue: 255/255)
                                                        : Color.primary.opacity(0.14),
                                                    lineWidth: isSelected ? 2.0 : 0.6
                                                )
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .help(preset.name)
                                }
                            }
                        }

                        HStack(spacing: 10) {
                            Button(action: { state.onRequestChooseBackdropPhoto?() }) {
                                HStack(spacing: 5) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 11))
                                    Text(state.backdropConfig.wallpaperId == nil && state.backdropConfig.customPhoto != nil ? "Replace Photo…" : "Custom Image…")
                                        .font(.system(size: 11.5, weight: .medium))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .frame(height: 25)
                                .background(RoundedRectangle(cornerRadius: 6.5, style: .continuous).fill(Color.primary.opacity(0.07)))
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Toggle("Blur", isOn: Binding(
                                get: { state.backdropConfig.blurPhotoBackdrop },
                                set: {
                                    state.backdropConfig.blurPhotoBackdrop = $0
                                    state.onBackdropChanged?()
                                }
                            ))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                        }
                    }

                case .gif:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            ForEach(GIFLoopPreset.all) { preset in
                                let selected = state.backdropConfig.customGifURL == nil && state.backdropConfig.gifPresetId == preset.id
                                Button(action: {
                                    state.backdropConfig.customGifURL = nil
                                    state.backdropConfig.gifPresetId = preset.id
                                    state.gifFrames = ImageBackdropCompositor.generateBuiltInGIFFrames(presetId: preset.id)
                                    state.currentGifFrameIndex = 0
                                    state.onBackdropChanged?()
                                }) {
                                    HStack(spacing: 5) {
                                        Circle()
                                            .fill(Color(preset.colorC))
                                            .frame(width: 9, height: 9)
                                        Text(preset.name)
                                            .font(.system(size: 11, weight: selected ? .semibold : .regular))
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.horizontal, 9)
                                    .frame(height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(selected ? Color.primary.opacity(0.11) : Color.primary.opacity(0.045))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .strokeBorder(selected ? Color.primary.opacity(0.25) : Color.clear, lineWidth: 0.75)
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            Spacer()

                            Button(action: { state.onRequestChooseBackdropGIF?() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "plus")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("GIF…")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundColor(.primary)
                                .padding(.horizontal, 9)
                                .frame(height: 24)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.07)))
                            }
                            .buttonStyle(.plain)
                        }

                        if let url = state.backdropConfig.customGifURL {
                            Text("Loaded: \(url.lastPathComponent)")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }

            // 3. Padding, Corners & Ratio (Shown smoothly whenever Frame or Background active)
            if state.backdropConfig.backdropType != .none || state.backdropConfig.frameStyle != .none {
                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    if state.backdropConfig.backdropType != .none {
                        HStack {
                            Text("Padding")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 58, alignment: .leading)
                            Slider(value: Binding(
                                get: { state.backdropConfig.padding },
                                set: {
                                    state.backdropConfig.padding = $0
                                    state.onBackdropChanged?()
                                }
                            ), in: 16...96, step: 4)
                            Text(verbatim: "\(Int(state.backdropConfig.padding))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 26, alignment: .trailing)
                        }
                    }

                    if !state.hasEmbeddedShadow || state.backdropConfig.frameStyle != .none {
                        HStack {
                            Text("Corners")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 58, alignment: .leading)
                            Slider(value: Binding(
                                get: { state.backdropConfig.cornerRadius },
                                set: {
                                    state.backdropConfig.cornerRadius = $0
                                    state.onBackdropChanged?()
                                }
                            ), in: 0...28, step: 2)
                            Text(verbatim: "\(Int(state.backdropConfig.cornerRadius))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .frame(width: 26, alignment: .trailing)
                        }
                    }

                    if state.backdropConfig.backdropType != .none {
                        HStack(spacing: 6) {
                            Text("Ratio")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(.secondary)
                                .frame(width: 52, alignment: .leading)

                            HStack(spacing: 2) {
                                ForEach(BackdropAspectRatio.allCases) { ratio in
                                    let active = state.backdropConfig.aspectRatio == ratio
                                    Button(action: {
                                        state.backdropConfig.aspectRatio = ratio
                                        state.onBackdropChanged?()
                                    }) {
                                        Text(ratio.rawValue)
                                            .font(.system(size: 11, weight: active ? .semibold : .regular))
                                            .foregroundColor(active ? .primary : .secondary)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 22)
                                            .background(AppleSegmentedSelectionPlate(isSelected: active))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(2)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.055)))
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 326)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.78))
        .onAppear {
            wallpaperStore.preloadThumbnailsIfNeeded()
        }
    }
}

// MARK: - Arrow Glyphs & Segmented Selection Plate

private struct ArrowStyleGlyph: View {
    let style: ArrowStyle
    let isActive: Bool

    var body: some View {
        Canvas { ctx, size in
            let fg: Color = isActive ? .primary : .primary.opacity(0.72)
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

private struct AppleSegmentedSelectionPlate: View {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
            .fill(isSelected ? (colorScheme == .dark ? Color.white.opacity(0.16) : Color.white) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .strokeBorder(isSelected ? Color.primary.opacity(0.09) : Color.clear, lineWidth: 0.5)
            )
    }
}

// MARK: - Calm Bottom Contextual Properties Pill (Never Blocks the Image Top)

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
                case .pan:
                    panControls
                case .crop:
                    cropControls
                case .grabText:
                    grabTextControls
                case .arrow:
                    arrowControls
                case .text:
                    textControls
                case .rectangle:
                    rectangleControls
                case .spotlight:
                    spotlightControls
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
                Capsule()
                    .fill(.regularMaterial)
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
            )
            .shadow(color: Color.black.opacity(0.08), radius: 8, y: 2)
        }
    }

    // MARK: - Crop Inspector

    private var cropControls: some View {
        HStack(spacing: 10) {
            if let cropR = state.pendingCropRect {
                Text(verbatim: "\(Int(round(cropR.width)))×\(Int(round(cropR.height)))")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.primary)

                Divider().frame(height: 14)

                Button(action: { state.onRequestApplyCrop?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("Apply Crop")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Capsule().fill(Color(red: 10/255, green: 132/255, blue: 255/255)))
                }
                .buttonStyle(.plain)

                Button(action: { state.onRequestCancelCrop?() }) {
                    Text("Cancel")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "crop")
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                Text("Drag across the screenshot to choose what to keep")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func toolColorSwatch(for tool: AnnotationTool) -> some View {
        DesignerColorSwatchButton(
            selectedColor: state.activeInspectorColorBinding(for: tool),
            isPresented: $state.isColorPopoverOpen,
            pickerState: state.annotationColorPickerState,
            onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
            onColorSelected: { state.applyColor($0, for: tool) }
        )
    }

    // MARK: - Spotlight Inspector

    private var spotlightControls: some View {
        HStack(spacing: 10) {
            toolColorSwatch(for: .spotlight)

            Divider().frame(height: 14)

            Text("Drag around what to highlight — the rest gently dims")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Arrow Inspector

    private var arrowControls: some View {
        HStack(spacing: 10) {
            toolColorSwatch(for: .arrow)

            Divider().frame(height: 14)

            TaperedThicknessSlider(
                value: state.activeWidthBinding(for: .arrow),
                range: 2.0...10.0,
                unit: "px",
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onValueChanged: { state.applyStrokeWidth($0, for: .arrow) }
            )

            Divider().frame(height: 14)

            HStack(spacing: 2) {
                ForEach(ArrowStyle.allCases) { style in
                    let isSelected = state.currentArrowStyle == style
                    Button(action: {
                        state.beginPropertyEditUndoIfNeeded()
                        state.applyArrowStyle(style)
                    }) {
                        ArrowStyleGlyph(style: style, isActive: isSelected)
                            .frame(width: 28, height: 22)
                            .background(AppleSegmentedSelectionPlate(isSelected: isSelected))
                    }
                    .buttonStyle(.plain)
                    .help(style.rawValue)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7.5, style: .continuous).fill(Color.primary.opacity(0.06)))

            if state.selectedAnnotationIndex != nil {
                Button(action: { state.flipSelectedArrowDirection() }) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.primary.opacity(0.8))
                        .frame(width: 24, height: 22)
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
            toolColorSwatch(for: .text)

            Divider().frame(height: 14)

            TaperedThicknessSlider(
                value: state.activeWidthBinding(for: .text),
                range: 11.0...36.0,
                unit: "pt",
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onValueChanged: { state.applyStrokeWidth($0, for: .text) }
            )

            Divider().frame(height: 14)

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
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(AppleSegmentedSelectionPlate(isSelected: isSelected))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7.5, style: .continuous).fill(Color.primary.opacity(0.06)))

            if state.isEditingInlineText {
                Divider().frame(height: 14)

                Button(action: { state.onCommitInlineText?() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10.5, weight: .bold))
                        Text("Done")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(Color(red: 10/255, green: 132/255, blue: 255/255)))
                }
                .buttonStyle(.plain)
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
            toolColorSwatch(for: .rectangle)

            if state.currentRectFillMode != .solid {
                Divider().frame(height: 14)

                TaperedThicknessSlider(
                    value: state.activeWidthBinding(for: .rectangle),
                    range: 1.0...12.0,
                    unit: "px",
                    onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                    onValueChanged: { state.applyStrokeWidth($0, for: .rectangle) }
                )
            }

            Divider().frame(height: 14)

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
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(AppleSegmentedSelectionPlate(isSelected: isSelected))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7.5, style: .continuous).fill(Color.primary.opacity(0.06)))

            Button(action: {
                state.beginPropertyEditUndoIfNeeded()
                let nextRadius: CGFloat = state.currentRectCornerRadius > 1 ? 0 : 8
                state.applyCornerRadius(nextRadius)
            }) {
                Image(systemName: state.currentRectCornerRadius > 1 ? "app" : "square")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(state.currentRectCornerRadius > 1 ? .primary : .secondary)
                    .frame(width: 24, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Toggle rounded corners")
        }
    }

    private func rectFillIcon(_ mode: RectFillMode) -> String {
        switch mode {
        case .stroke: return "rectangle"
        case .tinted: return "rectangle.inset.filled"
        case .solid: return "rectangle.fill"
        }
    }

    // MARK: - Ruler, Pin, Highlighter, Blur Inspectors

    private var rulerControls: some View {
        HStack(spacing: 10) {
            toolColorSwatch(for: .distance)
            Divider().frame(height: 14)
            Text(verbatim: "\(state.hoveredHexColor)  •  \(Int(state.pixelSize.width))×\(Int(state.pixelSize.height)) px")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private var pinControls: some View {
        HStack(spacing: 10) {
            toolColorSwatch(for: .numberedPin)
            Divider().frame(height: 14)
            Text("Click anywhere to drop step #\(state.nextPinNumber)")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)
        }
    }

    private var highlighterControls: some View {
        HStack(spacing: 10) {
            toolColorSwatch(for: .pencil)
            Divider().frame(height: 14)
            TaperedThicknessSlider(
                value: state.activeWidthBinding(for: .pencil),
                range: 4.0...28.0,
                unit: "px",
                onBeginEdit: { state.beginPropertyEditUndoIfNeeded() },
                onValueChanged: { state.applyStrokeWidth($0, for: .pencil) }
            )
        }
    }

    private var panControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "hand.raised")
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Text("Drag canvas or swipe with two fingers • ⌘+Scroll or Pinch to zoom")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)

            if abs(state.zoomScale - 1.0) > 0.04 || hypot(state.panOffset.x, state.panOffset.y) > 8 {
                Divider().frame(height: 14)

                Button(action: { state.onRequestZoomFit?() }) {
                    Text("Reset View")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                        .padding(.horizontal, 9)
                        .frame(height: 22)
                        .background(Capsule().fill(Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var grabTextControls: some View {
        HStack(spacing: 10) {
            Image(systemName: "text.viewfinder")
                .font(.system(size: 12))
                .foregroundColor(Color(red: 10/255, green: 132/255, blue: 255/255))

            Text("Drag over any region to copy text")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)

            Divider().frame(height: 14)

            Button(action: { state.onRequestGrabOCRText?() }) {
                Text("Grab All")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 23)
                    .background(Capsule().fill(Color(red: 10/255, green: 132/255, blue: 255/255)))
            }
            .buttonStyle(.plain)

            Button(action: { state.selectTool(.pointer) }) {
                Text("Done")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 23)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var blurControls: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkerboard.rectangle")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Text("Drag over private details to blur")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundColor(.secondary)
        }
    }
}
