import SwiftUI
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case screenshots = "Screenshots"
    case designerTools = "Designer Tools"
    case switcher = "Switcher"
    case appearance = "Appearance"
    case general = "General"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .designerTools: return "ruler.fill"
        case .switcher: return "macwindow.on.rectangle"
        case .appearance: return "paintbrush.fill"
        case .general: return "gearshape.fill"
        }
    }
}

public final class SettingsUIState: ObservableObject {
    public static let shared = SettingsUIState()

    @Published public var selectedTab: SettingsTab = .screenshots
    @Published public var searchQuery: String = ""

    // Exceptions selection
    @Published public var selectedExceptionId: String = "com.apple.finder"
    @Published public var showAddExceptionSheet: Bool = false
    @Published public var newAppName: String = ""
    @Published public var newBundleId: String = ""

    // Shortcut recording
    @Published public var recordingTargetId: String? = nil
    public var ocrEventMonitor: Any? = nil

    public func startRecording(targetId: String, onRecorded: @escaping (KeyCombination) -> Void) {
        stopRecording()
        recordingTargetId = targetId

        ocrEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // Esc
                self?.stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let rawFlags = flags.rawValue

            if rawFlags != 0 && event.keyCode != 55 && event.keyCode != 58 && event.keyCode != 56 && event.keyCode != 59 {
                let combo = KeyCombination(keyCode: event.keyCode, modifiers: rawFlags)
                onRecorded(combo)
                self?.stopRecording()
                return nil
            }

            return event
        }
    }

    public func stopRecording() {
        if let monitor = ocrEventMonitor {
            NSEvent.removeMonitor(monitor)
            ocrEventMonitor = nil
        }
        recordingTargetId = nil
    }
}

public struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var updater = UpdateManager.shared
    @ObservedObject private var uiState = SettingsUIState.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar Navigation
            sidebarView
                .frame(width: 220)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - Content Pane
            Group {
                switch uiState.selectedTab {
                case .screenshots:
                    ScrollView(.vertical, showsIndicators: true) {
                        screenshotsPane
                            .padding(26)
                    }
                case .designerTools:
                    ScrollView(.vertical, showsIndicators: true) {
                        designerToolsPane
                            .padding(26)
                    }
                case .switcher:
                    ScrollView(.vertical, showsIndicators: true) {
                        switcherPane
                            .padding(26)
                    }
                case .appearance:
                    ScrollView(.vertical, showsIndicators: true) {
                        appearancePane
                            .padding(26)
                    }
                case .general:
                    ScrollView(.vertical, showsIndicators: true) {
                        generalPane
                            .padding(26)
                    }
                }
            }
            .frame(minWidth: 600, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 820, height: 600)
        .onAppear {
            permissions.checkPermissions()
            if let first = settings.exceptionsList.first {
                uiState.selectedExceptionId = first.bundleId
            }
        }
    }

    // MARK: - 1. Sidebar View
    private var sidebarView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // App Branding Header with Cobalt Azure App Icon
            HStack(spacing: 12) {
                AppBrandingIcon(size: 38, cornerRadius: 9)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WindowSwitcher")
                        .font(.system(size: 14, weight: .bold))
                    Text("v\(updater.currentVersion) (Apple Silicon)")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 14)

            // Search Filter
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("Search settings", text: $uiState.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                if !uiState.searchQuery.isEmpty {
                    Button(action: { uiState.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.bottom, 12)

            // Navigation Tabs
            VStack(spacing: 2) {
                ForEach(SettingsTab.allCases) { tab in
                    sidebarItem(tab: tab)
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Divider()

            // Quit App Button
            Button(action: { NSApp.terminate(nil) }) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 12, weight: .medium))
                    Text("Quit Window Switcher")
                        .font(.system(size: 12))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
        }
    }

    private func sidebarItem(tab: SettingsTab) -> some View {
        let isSelected = uiState.selectedTab == tab
        return Button(action: { uiState.selectedTab = tab }) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? .white : settings.accentColor)
                    .frame(width: 18)

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? settings.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 2. Appearance Pane
    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Appearance")
                    .font(.system(size: 20, weight: .bold))
                Text("Customize how the switcher HUD looks and feels.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // 3 Style Cards (Thumbnails, App Icons, Titles) — NO PRO BADGES
            HStack(spacing: 12) {
                appearanceStyleCard(
                    style: .thumbnails,
                    label: "Thumbnails",
                    description: "Live window previews"
                ) {
                    ZStack {
                        Color(white: 0.12)
                        HStack(spacing: 6) {
                            miniCardPreview(hasImage: true)
                            miniCardPreview(hasImage: false)
                        }
                        .padding(8)
                    }
                }

                appearanceStyleCard(
                    style: .icons,
                    label: "App Icons",
                    description: "Focused application icons"
                ) {
                    ZStack {
                        Color(white: 0.12)
                        HStack(spacing: 10) {
                            Image(systemName: "safari.fill").font(.system(size: 22)).foregroundColor(.blue)
                            Image(systemName: "terminal.fill").font(.system(size: 22)).foregroundColor(.white)
                            Image(systemName: "folder.fill").font(.system(size: 22)).foregroundColor(.cyan)
                        }
                    }
                }

                appearanceStyleCard(
                    style: .titles,
                    label: "Window Titles",
                    description: "Compact list layout"
                ) {
                    ZStack {
                        Color(white: 0.12)
                        VStack(alignment: .leading, spacing: 3) {
                            miniTitleRow(text: "Safari — GitHub", isSelected: true)
                            miniTitleRow(text: "Terminal — zsh", isSelected: false)
                            miniTitleRow(text: "Finder — Projects", isSelected: false)
                        }
                        .padding(8)
                    }
                }
            }

            Divider()

            // Segmented Controls (Size, Theme, After keys released) - CLEAN TEXT ONLY, NO EMOJIS, NO ICONS
            VStack(spacing: 14) {
                // Size
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Card size")
                            .font(.system(size: 13, weight: .medium))
                        Text("Controls the dimensions of preview cards in the switcher HUD.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.cardSize) {
                        Text("Small").tag(CardSize.small)
                        Text("Medium").tag(CardSize.medium)
                        Text("Large").tag(CardSize.large)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                // Theme
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Color theme")
                            .font(.system(size: 13, weight: .medium))
                        Text("Adapts switcher HUD vibrancy to light or dark mode.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.themeMode) {
                        Text("System").tag(ThemeMode.system)
                        Text("Dark").tag(ThemeMode.dark)
                        Text("Light").tag(ThemeMode.light)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                // After keys released
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("After keys are released")
                            .font(.system(size: 13, weight: .medium))
                        Text("What happens immediately when modifier keys are released.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.afterRelease) {
                        Text("Focus Window").tag("Focus")
                        Text("Keep Open").tag("Hold")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
            }

            Divider()

            // Liquid Glass Styling Section (Unified from Open Canvas)
            VStack(alignment: .leading, spacing: 14) {
                Text("Liquid Glass & Optics")
                    .font(.system(size: 14, weight: .bold))

                // Accent Highlight Color
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accent highlight color")
                            .font(.system(size: 13, weight: .medium))
                        Text("Selection border and active glow color.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        accentDot(hex: "#0A84FF")
                        accentDot(hex: "#BF5AF2")
                        accentDot(hex: "#FF375F")
                        accentDot(hex: "#30D158")
                        accentDot(hex: "#FF9F0A")
                        accentDot(hex: "#64D2FF")
                        accentDot(hex: "#8E8E93")

                        TextField("Hex", text: $settings.customAccentColorHex)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 75)
                    }
                }

                // HUD Corner Radius
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("HUD corner curvature")
                            .font(.system(size: 13, weight: .medium))
                        Text("Smoothness of Apple squircle curvature: \(Int(settings.hudCornerRadius))px")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Slider(value: $settings.hudCornerRadius, in: 16...32, step: 2)
                        .frame(width: 200)
                }

                // Specular Border Width
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Specular border width")
                            .font(.system(size: 13, weight: .medium))
                        Text("Thickness of refraction dispersion caustics: \(String(format: "%.1f", settings.borderWidth))px")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Slider(value: $settings.borderWidth, in: 0.5...3.0, step: 0.5)
                        .frame(width: 200)
                }

                // Drop Shadow Depth
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Drop shadow depth")
                            .font(.system(size: 13, weight: .medium))
                        Text("Elevation elevation above open windows.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.shadowDepth) {
                        Text("Subtle").tag("Subtle Depth")
                        Text("Balanced").tag("Apple HIG Balanced")
                        Text("Floating").tag("Floating Deep")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
            }

            Divider()

            // Display Placement
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show switcher on")
                        .font(.system(size: 13, weight: .medium))
                    Text("Which display to place the switcher HUD on multi-monitor setups.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Picker("", selection: $settings.screenPlacement) {
                    ForEach(ScreenPlacement.allCases) { placement in
                        Text(placement.rawValue).tag(placement)
                    }
                }
                .frame(width: 220)
            }
        }
    }

    private func appearanceStyleCard<Content: View>(
        style: SwitcherStyle,
        label: String,
        description: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = settings.switcherStyle == style
        return Button(action: { settings.switcherStyle = style }) {
            VStack(alignment: .leading, spacing: 8) {
                content()
                    .frame(height: 85)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? settings.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2 : 0.8)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 12.5, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? settings.accentColor : .primary)
                    Text(description)
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? settings.accentColor.opacity(0.06) : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? settings.accentColor.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func miniCardPreview(hasImage: Bool) -> some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.white.opacity(0.15))
                .frame(width: 60, height: 38)
                .overlay(
                    Image(systemName: hasImage ? "photo" : "macwindow")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.5))
                )
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white.opacity(0.3))
                .frame(width: 36, height: 4)
        }
    }

    private func miniTitleRow(text: String, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isSelected ? settings.accentColor : Color.white.opacity(0.4))
                .frame(width: 5, height: 5)
            Text(text)
                .font(.system(size: 8.5))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(isSelected ? settings.accentColor.opacity(0.3) : Color.clear)
        )
    }

    private func accentDot(hex: String) -> some View {
        let isSelected = settings.customAccentColorHex.lowercased() == hex.lowercased()
        let color = Color(hex: hex) ?? settings.accentColor
        return Button(action: { settings.customAccentColorHex = hex }) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 20, height: 20)
                if isSelected {
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .frame(width: 18, height: 18)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 1. Screenshots & Capture Pane (HERO TAB)
    private var screenshotsPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Screenshots & Capture")
                    .font(.system(size: 20, weight: .bold))
                Text("Capture full-resolution Retina screenshots, active windows, and extract text.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Hero Action Banner
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(settings.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(settings.accentColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Area Screenshot & Designer Studio")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(.primary)
                    Text("Drag a selection box to measure distances, annotate, and inspect pixels.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button(action: {
                    ScreenshotCoordinator.shared.startAreaCapture()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Take Screenshot")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(settings.accentColor)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Inset Grouped Shortcuts Table (Shottr-Inspired)
            VStack(alignment: .leading, spacing: 8) {
                Text("Capture Shortcuts")
                    .font(.system(size: 13, weight: .semibold))

                VStack(spacing: 0) {
                    // Row 1: Unified Area & Window Capture with Freeze Frame & Apple Shadow
                    shortcutTableRow(
                        title: "Screenshot & Designer Studio",
                        description: "Freezes screen. Drag area or click any window to capture with Apple drop shadow",
                        targetId: "screenshot",
                        combination: $settings.screenshotKeyCombination,
                        defaultCombo: .defaultScreenshot,
                        onTry: { ScreenshotCoordinator.shared.startAreaCapture() }
                    )

                    Divider().padding(.horizontal, 12)

                    // Row 2: Screen Text Recognition (OCR)
                    shortcutTableRow(
                        title: "Instant screen text recognition (OCR)",
                        description: "Extract text from images, format paragraphs, and cut line breaks",
                        targetId: "ocr",
                        combination: $settings.ocrKeyCombination,
                        defaultCombo: .defaultOCR,
                        onTry: { ScreenOCRCoordinator.shared.startSelection() }
                    )
                }
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            Divider()

            // Capture Behavior Options
            VStack(alignment: .leading, spacing: 12) {
                Text("Capture Behavior")
                    .font(.system(size: 13, weight: .semibold))

                Toggle(isOn: $settings.autoOpenEditor) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open in Designer Studio after capture")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Immediately opens the screenshot in the vector annotation window.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)

                Toggle(isOn: $settings.playShutterSound) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Play camera shutter sound")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Plays Apple camera audio feedback upon capturing.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
    }

    private func shortcutTableRow(
        title: String,
        description: String,
        targetId: String,
        combination: Binding<KeyCombination>,
        defaultCombo: KeyCombination,
        onTry: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundColor(.primary)
                Text(description)
                    .font(.system(size: 10.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Try") {
                onTry()
            }
            .controlSize(.small)

            ShortcutRecorderField(
                targetId: targetId,
                keyCombination: combination,
                defaultCombination: defaultCombo
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - 2. Designer Tools & Inspection Pane
    private var designerToolsPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Designer Tools & Inspection")
                    .font(.system(size: 20, weight: .bold))
                Text("Measure distances, audit spacing grids, and validate color contrast.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Smart Distance Measurement
            VStack(alignment: .leading, spacing: 10) {
                Text("Smart Distance & Spacing")
                    .font(.system(size: 13, weight: .semibold))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hold ⌥ Option to inspect element distances")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Hovering over UI elements in the editor automatically detects borders and shows distances in pixels.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.enableSmartDistance)
                        .toggleStyle(.switch)
                }
                .padding(14)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            // 4px / 8px Grid Audit
            VStack(alignment: .leading, spacing: 10) {
                Text("Design System Grid Audit")
                    .font(.system(size: 13, weight: .semibold))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Spacing rhythm compliance")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Highlights non-standard spacings (e.g. 13px, 15px) in amber to catch implementation bugs.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.gridAuditUnit) {
                        Text("4px Grid").tag(4)
                        Text("8px Grid").tag(8)
                        Text("Off").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                .padding(14)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            // Annotation Toolkit Overview
            VStack(alignment: .leading, spacing: 8) {
                Text("Designer Studio Tool Shortcuts")
                    .font(.system(size: 13, weight: .semibold))

                VStack(spacing: 6) {
                    shortcutRow(keys: ["D"], description: "Smart Dimension Ruler (Strict H/V + UI Edge Snap)")
                    shortcutRow(keys: ["⌥ Hover"], description: "Live Pixel Distance Preview across buttons & gaps")
                    shortcutRow(keys: ["Scroll", "Pinch"], description: "Zoom in/out anchored on cursor (Space+Drag to pan)")
                    shortcutRow(keys: ["A"], description: "Callout Arrow")
                    shortcutRow(keys: ["N"], description: "Numbered QA Pin (①, ②, ③)")
                    shortcutRow(keys: ["R"], description: "Component Bounding Box (width × height px)")
                    shortcutRow(keys: ["T"], description: "Text Callout Note (double-click to edit)")
                    shortcutRow(keys: ["B"], description: "Mosaic Redaction Blur Box")
                    shortcutRow(keys: ["Tab"], description: "Copy hovered Hex color • ⇧Tab measures WCAG Contrast")
                    shortcutRow(keys: ["⌘", "Z"], description: "Undo • ⌘⇧Z Redo • ⌘C Copy Annotated Image")
                }
            }
        }
    }

    // MARK: - 3. Window Switcher Pane
    private var switcherPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Window Switcher")
                    .font(.system(size: 20, weight: .bold))
                Text("Fast, 60 FPS live-mirrored window switching behavior.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Primary Activation Shortcut (Strictly Mutually Exclusive)
            VStack(alignment: .leading, spacing: 10) {
                Text("Activation Shortcut")
                    .font(.system(size: 13, weight: .semibold))

                Text("Choose which shortcut triggers Window Switcher. Only the selected shortcut will be active.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    // Option 1: Command + Tab
                    Button(action: {
                        settings.primaryShortcut = .commandTab
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: settings.primaryShortcut == .commandTab ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 14))
                                .foregroundColor(settings.primaryShortcut == .commandTab ? settings.accentColor : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("⌘ Command + Tab")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Replaces macOS app switcher with individual window switching")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(settings.primaryShortcut == .commandTab ? settings.accentColor.opacity(0.08) : Color.primary.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(settings.primaryShortcut == .commandTab ? settings.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    // Option 2: Option + Tab
                    Button(action: {
                        settings.primaryShortcut = .optionTab
                    }) {
                        HStack(spacing: 10) {
                            Image(systemName: settings.primaryShortcut == .optionTab ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 14))
                                .foregroundColor(settings.primaryShortcut == .optionTab ? settings.accentColor : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("⌥ Option + Tab")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)
                                Text("Classic Windows Alt-Tab (leaves macOS ⌘-Tab untouched)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(settings.primaryShortcut == .optionTab ? settings.accentColor.opacity(0.08) : Color.primary.opacity(0.02))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(settings.primaryShortcut == .optionTab ? settings.accentColor.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // Window Switcher Filtering
            VStack(alignment: .leading, spacing: 14) {
                Text("Window Filtering")
                    .font(.system(size: 13, weight: .semibold))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show windows from")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Filter switcher cards by application.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.appsFilter) {
                        Text("All apps").tag("All apps")
                        Text("Active app").tag("Active app")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show windows across")
                            .font(.system(size: 12.5, weight: .medium))
                        Text("Filter switcher cards by Space.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Picker("", selection: $settings.spacesFilter) {
                        Text("All Spaces").tag("All Spaces")
                        Text("Current Space").tag("Current Space")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }

            Divider()

            // Window Visibility & Filtering
            VStack(alignment: .leading, spacing: 12) {
                Text("Window Visibility & Filtering")
                    .font(.system(size: 13, weight: .semibold))

                VStack(spacing: 12) {
                    toggleSettingRow(
                        title: "Show minimized windows",
                        description: "Include windows that have been minimized to the Dock.",
                        isOn: $settings.showMinimizedWindows
                    )

                    toggleSettingRow(
                        title: "Show hidden windows",
                        description: "Include windows from hidden applications (⌘H).",
                        isOn: $settings.showHiddenWindows
                    )

                    toggleSettingRow(
                        title: "Show fullscreen windows",
                        description: "Include windows running in macOS full-screen spaces.",
                        isOn: $settings.showFullscreenWindows
                    )

                    toggleSettingRow(
                        title: "Show apps with no open windows",
                        description: "Display running applications even when they have no active windows.",
                        isOn: $settings.showAppsWithNoWindows
                    )
                }
                .padding(14)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }

            Divider()

            // Quick Navigation Shortcuts Cheat Sheet
            VStack(alignment: .leading, spacing: 10) {
                Text("Keyboard Navigation While Switcher is Open")
                    .font(.system(size: 13, weight: .semibold))

                VStack(spacing: 8) {
                    shortcutRow(keys: ["Tab", "⇧ Tab"], description: "Cycle forward and backward through open windows")
                    shortcutRow(keys: ["←", "→", "↑", "↓"], description: "Navigate directly across window card grid")
                    shortcutRow(keys: ["Return", "Space"], description: "Focus selected window and close switcher")
                    shortcutRow(keys: ["W", "⌫"], description: "Close the currently highlighted window")
                    shortcutRow(keys: ["Esc"], description: "Dismiss switcher without activating any window")
                }
            }
        }
    }

    private func shortcutRow(keys: [String], description: String) -> some View {
        HStack {
            HStack(spacing: 5) {
                ForEach(keys, id: \.self) { k in
                    Text(k)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(NSColor.windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(Color.primary.opacity(0.15), lineWidth: 0.8)
                        )
                }
            }
            .frame(width: 140, alignment: .leading)

            Text(description)
                .font(.system(size: 12))
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private func toggleSettingRow(title: String, description: String, isOn: Binding<Bool>) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
        }
    }

    // MARK: - 4. General Pane (Robust Auto-Updater & Clean Layout)
    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 22) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("General")
                    .font(.system(size: 20, weight: .bold))
                Text("Manage system startup, background thumbnail rendering, and updates.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // System Integration
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start at login")
                            .font(.system(size: 13, weight: .medium))
                        Text("Automatically launch Window Switcher when you log in to macOS.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.startAtLogin)
                        .toggleStyle(.switch)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Menubar icon")
                            .font(.system(size: 13, weight: .medium))
                        Text("Show quick access item in the macOS status menu bar.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $settings.showMenubarIcon)
                        .toggleStyle(.switch)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text("Capture windows in the background")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $settings.captureInBackground)
                            .toggleStyle(.switch)
                    }
                    Text("Pre-renders thumbnails for 0ms HUD opening. Disable to minimize background GPU usage on battery.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            Divider()

            // Software Updates & GitHub Releases
            VStack(alignment: .leading, spacing: 12) {
                Text("Software Updates")
                    .font(.system(size: 13, weight: .semibold))

                // Update Status Card
                HStack(spacing: 14) {
                    updateStatusIcon

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text("Window Switcher")
                                .font(.system(size: 13, weight: .semibold))
                            Text("v\(updater.currentVersion)")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.secondary)

                            if case .upToDate = updater.status {
                                Text("Latest")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }

                        updateStatusDescription
                    }

                    Spacer()

                    updateActionButton
                }
                .padding(14)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Update Policy
                HStack {
                    Text("Check for updates")
                        .font(.system(size: 12.5, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.updatePolicy) {
                        Text("Automatically on launch").tag("Check for updates periodically")
                        Text("Manually only").tag("Check manually")
                    }
                    .frame(width: 220)
                }
            }

            Divider()

            // System Permissions
            VStack(alignment: .leading, spacing: 12) {
                Text("System Permissions (100% Local & Private)")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 12) {
                    permissionCard(
                        title: "Accessibility",
                        isGranted: permissions.hasAccessibility,
                        action: { permissions.requestAccessibility() }
                    )
                    permissionCard(
                        title: "Screen Recording",
                        isGranted: permissions.hasScreenRecording,
                        action: { permissions.requestScreenRecording() }
                    )
                }
            }

            Divider()

            // Excluded Applications Rules
            exceptionsPane

            Divider()

            // Reset Button
            HStack {
                Spacer()
                Button("Reset All Settings to Defaults") {
                    settings.resetToDefaults()
                }
                .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var updateStatusIcon: some View {
        switch updater.status {
        case .idle, .upToDate:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(.green)
        case .checking:
            ProgressView()
                .scaleEffect(0.7)
        case .available:
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 22))
                .foregroundColor(settings.accentColor)
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 22))
                .foregroundColor(settings.accentColor)
        case .installing, .readyToRelaunch:
            Image(systemName: "sparkles")
                .font(.system(size: 22))
                .foregroundColor(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 22))
                .foregroundColor(.orange)
        }
    }

    @ViewBuilder
    private var updateStatusDescription: some View {
        switch updater.status {
        case .idle:
            Text("Window Switcher is up to date.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .checking:
            Text("Checking GitHub Releases for updates...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .upToDate(let ver):
            Text("You are on the latest version (\(ver)). Checked just now.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .available(let ver, let notes, _, _):
            Text("Version \(ver) is available. \(notes)")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
        case .downloading(let progress):
            Text("Downloading update DMG: \(Int(progress * 100))%")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .installing:
            Text("Mounting DMG and installing update to /Applications...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        case .readyToRelaunch:
            Text("Update installed! Relaunch Window Switcher to complete.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.green)
        case .error(let msg):
            Text("Unable to check: \(msg)")
                .font(.system(size: 11))
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        switch updater.status {
        case .idle, .upToDate, .error:
            Button("Check for Updates Now...") {
                updater.checkForUpdates(userInitiated: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .checking:
            ProgressView()
                .scaleEffect(0.65)

        case .available(_, _, let downloadUrl, _):
            Button("Download & Install Update") {
                updater.downloadAndInstall(from: downloadUrl)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .downloading(let progress):
            ProgressView(value: progress)
                .frame(width: 80)

        case .installing:
            ProgressView()
                .scaleEffect(0.65)

        case .readyToRelaunch:
            Button("Relaunch Now") {
                updater.relaunch()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }

    private func permissionCard(title: String, isGranted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(isGranted ? .green : .orange)
                .font(.system(size: 16))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(isGranted ? "Active" : "Required")
                    .font(.system(size: 10.5))
                    .foregroundColor(isGranted ? .green : .orange)
            }

            Spacer()

            if !isGranted {
                Button("Enable", action: action)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - 5. Excluded Apps Pane
    private var exceptionsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Excluded Applications & Rules")
                    .font(.system(size: 20, weight: .bold))
                Text("Control which apps appear in Window Switcher and when keyboard shortcuts are ignored.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Explanatory Guidance Callout Card
            HStack(spacing: 12) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 18))
                    .foregroundColor(settings.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("How App Rules Work")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Add applications you want to customize. For example, disable Window Switcher shortcuts while games, virtual machines, or remote desktops are in focus, or hide background tools from the switcher.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )

            // Master-Detail Split Pane
            HStack(alignment: .top, spacing: 14) {
                // Left Column: App List with authentic icons
                VStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(settings.exceptionsList, id: \.bundleId) { app in
                                let isSelected = uiState.selectedExceptionId == app.bundleId
                                Button(action: {
                                    uiState.selectedExceptionId = app.bundleId
                                }) {
                                    HStack(spacing: 10) {
                                        NativeAppIconView(bundleId: app.bundleId, size: 28)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(app.name)
                                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                                                .foregroundColor(isSelected ? .white : .primary)
                                                .lineLimit(1)
                                            Text(app.bundleId)
                                                .font(.system(size: 10))
                                                .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                                                .lineLimit(1)
                                        }

                                        Spacer()

                                        if app.ignoreShortcuts == "When in focus" || app.ignoreShortcuts == "When active" {
                                            Text("Pass-Through")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(isSelected ? Color.white.opacity(0.2) : settings.accentColor.opacity(0.12))
                                                .foregroundColor(isSelected ? .white : settings.accentColor)
                                                .clipShape(Capsule())
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(isSelected ? settings.accentColor : Color.clear)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                    }

                    Divider()

                    // Add / Remove toolbar
                    HStack(spacing: 10) {
                        Button(action: chooseApplicationFromDisk) {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Add App...")
                                    .font(.system(size: 11.5, weight: .medium))
                            }
                        }
                        .controlSize(.small)

                        Spacer()

                        Button(action: {
                            if let idx = settings.exceptionsList.firstIndex(where: { $0.bundleId == uiState.selectedExceptionId }) {
                                settings.exceptionsList.remove(at: idx)
                                uiState.selectedExceptionId = settings.exceptionsList.first?.bundleId ?? ""
                            }
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                                .foregroundColor(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                        .disabled(settings.exceptionsList.isEmpty)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
                .frame(width: 260, height: 350)
                .background(Color.primary.opacity(0.02))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )

                // Right Column: Detail Configuration
                if let selected = settings.exceptionsList.first(where: { $0.bundleId == uiState.selectedExceptionId }) {
                    VStack(alignment: .leading, spacing: 18) {
                        // App Banner
                        HStack(spacing: 14) {
                            NativeAppIconView(bundleId: selected.bundleId, size: 44)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(selected.name)
                                    .font(.system(size: 16, weight: .bold))
                                Text(selected.bundleId)
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        Divider()

                        // Rule 1: Shortcut Key Behavior
                        VStack(alignment: .leading, spacing: 6) {
                            Text("When using this app:")
                                .font(.system(size: 12.5, weight: .semibold))

                            Picker("", selection: Binding(
                                get: {
                                    (selected.ignoreShortcuts == "When in focus" || selected.ignoreShortcuts == "When active") ? "When in focus" : "Never"
                                },
                                set: { newMode in
                                    if let idx = settings.exceptionsList.firstIndex(where: { $0.bundleId == selected.bundleId }) {
                                        settings.exceptionsList[idx].ignoreShortcuts = newMode
                                    }
                                }
                            )) {
                                Text("Pass-through shortcuts (Disable Switcher in this app)").tag("When in focus")
                                Text("Normal (Window Switcher active)").tag("Never")
                            }
                            .pickerStyle(.radioGroup)
                            .padding(.leading, 4)

                            Text("Recommended for full-screen games, Screen Sharing, and virtual machines so their native keyboard shortcuts aren't intercepted.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                        }

                        Divider()

                        // Rule 2: Switcher Visibility
                        VStack(alignment: .leading, spacing: 6) {
                            Text("In the Switcher HUD:")
                                .font(.system(size: 12.5, weight: .semibold))

                            Picker("", selection: Binding(
                                get: { selected.hideWindows },
                                set: { newMode in
                                    if let idx = settings.exceptionsList.firstIndex(where: { $0.bundleId == selected.bundleId }) {
                                        settings.exceptionsList[idx].hideWindows = newMode
                                    }
                                }
                            )) {
                                Text("Hide when no windows open").tag("When no open window")
                                Text("Always hide from switcher").tag("Always")
                                Text("Always show in switcher").tag("Never")
                            }
                            .pickerStyle(.radioGroup)
                            .padding(.leading, 4)

                            Text("Control whether this application appears in the switcher card list.")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)
                        }

                        Spacer()
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: 350)
                    .background(Color.primary.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                } else {
                    // Empty state when no app selected
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 38))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("No Excluded Applications")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Window Switcher handles all application windows normally. Click 'Add App...' to configure custom rules for specific apps.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)

                        Button(action: chooseApplicationFromDisk) {
                            Label("Add Application...", systemImage: "plus")
                        }
                        .controlSize(.regular)
                        .padding(.top, 4)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: 350)
                    .background(Color.primary.opacity(0.02))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func chooseApplicationFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Exclude App"
        panel.message = "Choose an application to configure rules for Window Switcher"

        if panel.runModal() == .OK, let url = panel.url {
            let bundle = Bundle(url: url)
            let name = bundle?.infoDictionary?["CFBundleDisplayName"] as? String
                ?? bundle?.infoDictionary?["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
            let bundleId = bundle?.bundleIdentifier ?? ("custom." + url.deletingPathExtension().lastPathComponent)

            if !settings.exceptionsList.contains(where: { $0.bundleId == bundleId }) {
                settings.exceptionsList.append(AppException(
                    name: name,
                    bundleId: bundleId,
                    hideWindows: "When no open window",
                    ignoreShortcuts: "When in focus"
                ))
            }
            uiState.selectedExceptionId = bundleId
        }
    }
}

// MARK: - Interactive Apple HIG Shortcut Recorder Component
private struct ShortcutRecorderField: View {
    @ObservedObject var uiState = SettingsUIState.shared
    let targetId: String
    @Binding var keyCombination: KeyCombination
    let defaultCombination: KeyCombination

    var isRecordingThis: Bool {
        uiState.recordingTargetId == targetId
    }

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                if isRecordingThis {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 5, height: 5)
                        Text("Press keys…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    if keyCombination.isEmpty {
                        Text("Record")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        Text(keyCombination.compactDisplay)
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Button(action: {
                            keyCombination = .empty
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10.5))
                                .foregroundColor(.secondary.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .help("Clear shortcut")
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3.5)
            .frame(width: 96, height: 26)
            .background(
                Capsule()
                    .fill(isRecordingThis ? Color.blue.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isRecordingThis
                            ? Color.blue.opacity(0.7)
                            : Color.primary.opacity(0.12),
                        lineWidth: isRecordingThis ? 1.2 : 0.8
                    )
            )
            .shadow(color: Color.black.opacity(0.02), radius: 1, y: 0.5)
            .contentShape(Capsule())
            .onTapGesture {
                if isRecordingThis {
                    uiState.stopRecording()
                } else {
                    uiState.startRecording(targetId: targetId) { newCombo in
                        keyCombination = newCombo
                    }
                }
            }

            if keyCombination != defaultCombination {
                Button(action: {
                    uiState.stopRecording()
                    keyCombination = defaultCombination
                }) {
                    Text("Reset")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Reset to default")
            }
        }
        .onDisappear {
            uiState.stopRecording()
        }
    }
}
