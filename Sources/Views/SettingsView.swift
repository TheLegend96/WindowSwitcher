import SwiftUI
import AppKit

// MARK: - Settings Navigation Tabs

public enum SettingsTab: String, CaseIterable, Identifiable {
    case screenshots = "Screenshots"
    case designerTools = "Designer Tools"
    case switcher = "Switcher"
    case appearance = "Appearance"
    case apps = "Apps & Rules"
    case general = "General"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .designerTools: return "ruler.fill"
        case .switcher: return "macwindow.on.rectangle"
        case .appearance: return "paintbrush.fill"
        case .apps: return "square.grid.2x2.fill"
        case .general: return "gearshape.fill"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .screenshots: return Color(red: 0.039, green: 0.518, blue: 1.0)   // Apple System Blue #0A84FF
        case .designerTools: return Color(red: 1.0, green: 0.584, blue: 0.0)   // Apple System Orange #FF9500
        case .switcher: return Color(red: 0.369, green: 0.361, blue: 0.902)    // Apple System Indigo #5E5CE6
        case .appearance: return Color(red: 1.0, green: 0.216, blue: 0.373)    // Apple System Pink/Rose #FF375F
        case .apps: return Color(red: 0.188, green: 0.820, blue: 0.345)        // Apple System Green #30D158
        case .general: return Color(red: 0.557, green: 0.557, blue: 0.576)     // Apple System Gray #8E8E93
        }
    }

    public var isBlueBadge: Bool {
        self == .screenshots
    }

    public var subtitle: String {
        switch self {
        case .screenshots:
            return "Capture frozen frames, active window shadows, and on-screen text."
        case .designerTools:
            return "Measure UI distances, verify grid rhythm, and inspect colors at pixel level."
        case .switcher:
            return "Configure trigger shortcuts, window ordering, and visibility filters."
        case .appearance:
            return "Choose your HUD layout style, sizing, theme, and glass acoustics."
        case .apps:
            return "Customize per-application switcher visibility and shortcut pass-through rules."
        case .general:
            return "Manage login launch, permissions, background caching, and updates."
        }
    }

    public var isSystemGroup: Bool {
        self == .apps || self == .general
    }
}

// MARK: - Search Index

private struct SettingsSearchItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let keywords: String
    let tab: SettingsTab

    func matches(_ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return title.lowercased().contains(q)
            || subtitle.lowercased().contains(q)
            || keywords.lowercased().contains(q)
            || tab.rawValue.lowercased().contains(q)
    }
}

private let allSearchItems: [SettingsSearchItem] = [
    SettingsSearchItem(title: "Area & Window Capture Shortcut", subtitle: "Freeze screen and drag an area or click any window", keywords: "screenshot option capture freeze shadow", tab: .screenshots),
    SettingsSearchItem(title: "Active Window Shortcut", subtitle: "Snap the frontmost window immediately with shadow", keywords: "window capture active shadow", tab: .screenshots),
    SettingsSearchItem(title: "Screen Text Recognition (OCR)", subtitle: "Copy detected text directly from any selected region", keywords: "ocr extract copy text", tab: .screenshots),
    SettingsSearchItem(title: "Auto-open Designer Studio", subtitle: "Launch the canvas editor right after capture", keywords: "editor studio canvas workflow", tab: .screenshots),
    SettingsSearchItem(title: "Play Camera Shutter Sound", subtitle: "Play audio feedback when capturing or saving", keywords: "sound audio shutter", tab: .screenshots),

    SettingsSearchItem(title: "Smart Distance & Edge Snapping", subtitle: "Snap vertical and horizontal rulers to buttons and borders", keywords: "ruler dimension snap measure distance", tab: .designerTools),
    SettingsSearchItem(title: "Layout Grid Audit Unit", subtitle: "Flag spacings off the 4 px or 8 px layout grid", keywords: "4px 8px grid rhythm audit spacing", tab: .designerTools),
    SettingsSearchItem(title: "Studio Keyboard Shortcuts", subtitle: "Reference keys for Ruler, Arrow, Text, Rectangle, Undo", keywords: "shortcuts keys arrow text rectangle undo", tab: .designerTools),

    SettingsSearchItem(title: "Switcher Trigger Shortcut", subtitle: "Bind Option+Tab or replace macOS Command+Tab", keywords: "command option tab shortcut hotkey trigger", tab: .switcher),
    SettingsSearchItem(title: "After Releasing Keys", subtitle: "Focus selected window or keep HUD open for inspection", keywords: "release focus hold keep open", tab: .switcher),
    SettingsSearchItem(title: "Applications & Spaces Filtering", subtitle: "Show windows across all apps or current active Space", keywords: "filter spaces screens active apps", tab: .switcher),
    SettingsSearchItem(title: "Window Visibility Flags", subtitle: "Include minimized, hidden, fullscreen, or windowless apps", keywords: "minimized hidden fullscreen no windows", tab: .switcher),
    SettingsSearchItem(title: "Navigation Hotkeys", subtitle: "Arrow keys, Tab cycling, Q quit, W close window", keywords: "quit close arrows keyboard navigation", tab: .switcher),

    SettingsSearchItem(title: "Switcher Layout Style", subtitle: "Thumbnails, App Icons, Window Titles, or Compact Cards", keywords: "thumbnails icons titles compact cards bento command tab", tab: .appearance),
    SettingsSearchItem(title: "Tile Size & Color Theme", subtitle: "Small, Medium, or Large cards in System, Light, or Dark", keywords: "size small medium large theme light dark system", tab: .appearance),
    SettingsSearchItem(title: "Accent Highlight Color", subtitle: "Customize selection border hex or Apple system tint", keywords: "color accent hex ring highlight", tab: .appearance),
    SettingsSearchItem(title: "HUD Corner Curvature & Elevation", subtitle: "Adjust squircle radius, border stroke, and shadow depth", keywords: "corner radius curvature border shadow depth elevation", tab: .appearance),
    SettingsSearchItem(title: "Multi-Monitor Placement", subtitle: "Choose active screen, cursor screen, menu bar, or all displays", keywords: "display monitor placement screen", tab: .appearance),

    SettingsSearchItem(title: "Excluded Apps & Pass-Through Rules", subtitle: "Hide specific apps or bypass shortcuts for games and VMs", keywords: "exclude ignore rules game vm pass through finder", tab: .apps),

    SettingsSearchItem(title: "Launch at Login & Menu Bar Icon", subtitle: "Start automatically with macOS and toggle menu bar item", keywords: "login startup menubar icon", tab: .general),
    SettingsSearchItem(title: "Background Thumbnail Rendering", subtitle: "Keep thumbnails warm for instant 0 ms switcher opening", keywords: "background thumbnail cache gpu", tab: .general),
    SettingsSearchItem(title: "Accessibility & Screen Recording Permissions", subtitle: "Verify required macOS privacy permissions", keywords: "permissions accessibility screen recording privacy", tab: .general),
    SettingsSearchItem(title: "Software Updates & GitHub Releases", subtitle: "Check for new releases automatically or manually", keywords: "update version check github relaunch", tab: .general),
    SettingsSearchItem(title: "Reset All Preferences", subtitle: "Restore every setting back to factory defaults", keywords: "reset defaults factory", tab: .general)
]

// MARK: - Observable UI State (Zero @State macro usage for CLI builds)

public final class SettingsUIState: ObservableObject {
    public static let shared = SettingsUIState()

    @Published public var selectedTab: SettingsTab = .screenshots
    @Published public var searchQuery: String = ""

    // Hover & UI feedback
    @Published public var hoveredTab: SettingsTab? = nil
    @Published public var hoveredStyle: SwitcherStyle? = nil
    @Published public var didConfirmReset: Bool = false

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

// MARK: - Native Sidebar Vibrancy

private struct SidebarVibrancyView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .sidebar
        nsView.blendingMode = .behindWindow
    }
}

// MARK: - Root Settings View

public struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var updater = UpdateManager.shared
    @ObservedObject private var uiState = SettingsUIState.shared
    @Environment(\.colorScheme) private var colorScheme

    private var canvasBackground: Color {
        colorScheme == .dark
            ? Color(red: 0.110, green: 0.110, blue: 0.118)
            : Color(red: 0.957, green: 0.957, blue: 0.965)
    }

    private var cardSurface: Color {
        colorScheme == .dark
            ? Color(red: 0.149, green: 0.149, blue: 0.161)
            : Color.white
    }

    private var cardHairline: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.09)
            : Color.black.opacity(0.07)
    }

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            sidebarView
                .frame(width: 232)

            Rectangle()
                .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.09))
                .frame(width: 1)

            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(canvasBackground)
        }
        .frame(width: 860, height: 620)
        .preferredColorScheme(
            settings.themeMode == .light ? .light :
            (settings.themeMode == .dark ? .dark : nil)
        )
        .onAppear {
            permissions.checkPermissions()
            if !settings.exceptionsList.contains(where: { $0.bundleId == uiState.selectedExceptionId }),
               let first = settings.exceptionsList.first {
                uiState.selectedExceptionId = first.bundleId
            }
        }
    }

    // MARK: - macOS System Settings Sidebar

    private var sidebarView: some View {
        ZStack {
            SidebarVibrancyView()

            VStack(spacing: 0) {
                // Leave natural headroom for the window traffic lights
                Spacer().frame(height: 36)

                // Pill Search Field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("Search", text: $uiState.searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))

                    if !uiState.searchQuery.isEmpty {
                        Button(action: { uiState.searchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(
                    Capsule()
                        .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.055))
                )
                .overlay(
                    Capsule()
                        .stroke(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 0.75)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                // Navigation Tabs
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(SettingsTab.allCases.filter { !$0.isSystemGroup }) { tab in
                            sidebarRow(tab: tab)
                        }

                        Rectangle()
                            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
                            .frame(height: 1)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                        ForEach(SettingsTab.allCases.filter { $0.isSystemGroup }) { tab in
                            sidebarRow(tab: tab)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }

                Spacer(minLength: 0)

                // Quiet App Footer
                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.07))
                    .frame(height: 1)

                HStack(spacing: 8) {
                    AppBrandingIcon(size: 22, cornerRadius: 5.5)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("Window Switcher")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Text("Preferences")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text("v\(updater.currentVersion)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private func sidebarRow(tab: SettingsTab) -> some View {
        let isSelected = uiState.selectedTab == tab && uiState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let isHovered = uiState.hoveredTab == tab && !isSelected

        return Button(action: {
            uiState.searchQuery = ""
            uiState.selectedTab = tab
        }) {
            HStack(spacing: 10) {
                SquircleBadge(
                    symbol: tab.icon,
                    color: tab.badgeColor,
                    isInvertedOnBlueSelection: isSelected && tab.isBlueBadge,
                    showSelectionRim: isSelected && !tab.isBlueBadge,
                    size: 21,
                    cornerRadius: 5.5,
                    symbolSize: 11
                )

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if tab == .general && (!permissions.hasAccessibility || !permissions.hasScreenRecording) {
                    Circle()
                        .fill(isSelected ? Color.white : Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? Color(red: 0.039, green: 0.518, blue: 1.0)
                            : (isHovered ? Color.primary.opacity(0.055) : Color.clear)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            uiState.hoveredTab = hovering ? tab : (uiState.hoveredTab == tab ? nil : uiState.hoveredTab)
        }
    }

    // MARK: - Detail Routing & Search Results

    @ViewBuilder
    private var detailContent: some View {
        let trimmedQuery = uiState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            ScrollView(.vertical, showsIndicators: true) {
                searchResultsPane(query: trimmedQuery)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
            }
        } else if uiState.selectedTab == .apps {
            // Apps & Rules uses full height master-detail split without outer scroll clipping
            appsPane
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    switch uiState.selectedTab {
                    case .screenshots:
                        screenshotsPane
                    case .designerTools:
                        designerToolsPane
                    case .switcher:
                        switcherPane
                    case .appearance:
                        appearancePane
                    case .apps:
                        appsPane
                    case .general:
                        generalPane
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 24)
            }
        }
    }

    private func searchResultsPane(query: String) -> some View {
        let matches = allSearchItems.filter { $0.matches(query) }

        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                SquircleBadge(symbol: "magnifyingglass", color: Color(red: 0.039, green: 0.518, blue: 1.0), size: 28, cornerRadius: 7, symbolSize: 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Search results for \"\(query)\"")
                        .font(.system(size: 19, weight: .bold))
                    Text("\(matches.count) \(matches.count == 1 ? "setting" : "settings") matched")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Clear") {
                    uiState.searchQuery = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if matches.isEmpty {
                insetCard {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 26, weight: .light))
                            .foregroundColor(.secondary)
                        Text("No matching settings")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Try searching for \"shortcut\", \"cards\", \"ruler\", \"login\", or \"permissions\".")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                    .padding(.horizontal, 20)
                }
            } else {
                insetCard {
                    VStack(spacing: 0) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                            Button(action: {
                                uiState.selectedTab = item.tab
                                uiState.searchQuery = ""
                            }) {
                                HStack(spacing: 12) {
                                    SquircleBadge(
                                        symbol: item.tab.icon,
                                        color: item.tab.badgeColor,
                                        size: 24,
                                        cornerRadius: 6,
                                        symbolSize: 12
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.primary)
                                        Text(item.subtitle)
                                            .font(.system(size: 11.5))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(item.tab.rawValue)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < matches.count - 1 {
                                insetDivider(leading: 52)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - 1. Screenshots Pane

    private var screenshotsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            paneHeader(for: .screenshots)

            // Action Banner Card
            insetCard {
                HStack(spacing: 14) {
                    SquircleBadge(
                        symbol: "viewfinder.circle.fill",
                        color: Color(red: 0.039, green: 0.518, blue: 1.0),
                        size: 36,
                        cornerRadius: 9,
                        symbolSize: 18
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Instant Freeze & Window Capture")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("Drag to select a screen area or single-click any window for an Apple-style shadow capture.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Button(action: {
                        ScreenshotCoordinator.shared.startAreaCapture()
                    }) {
                        Text("Take Screenshot")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color(red: 0.039, green: 0.518, blue: 1.0))
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }

            // Capture Shortcuts Group
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Capture shortcuts")

                insetCard {
                    VStack(spacing: 0) {
                        shortcutRow(
                            title: "Area & window capture",
                            subtitle: "Freeze all screens, drag a region, or click a window",
                            targetId: "screenshot",
                            combination: $settings.screenshotKeyCombination,
                            defaultCombo: .defaultScreenshot,
                            onTry: { ScreenshotCoordinator.shared.startAreaCapture() }
                        )

                        insetDivider()

                        shortcutRow(
                            title: "Capture active window",
                            subtitle: "Snap the frontmost window directly with soft elevation shadow",
                            targetId: "activeWindow",
                            combination: $settings.activeWindowKeyCombination,
                            defaultCombo: .defaultActiveWindow,
                            onTry: { ScreenshotCoordinator.shared.captureActiveWindow() }
                        )

                        insetDivider()

                        shortcutRow(
                            title: "Screen text recognition (OCR)",
                            subtitle: "Extract clean text from images, videos, or locked views",
                            targetId: "ocr",
                            combination: $settings.ocrKeyCombination,
                            defaultCombo: .defaultOCR,
                            onTry: { ScreenOCRCoordinator.shared.startSelection() }
                        )
                    }
                }
            }

            // Capture Behavior Group
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Workflow")

                insetCard {
                    VStack(spacing: 0) {
                        switchRow(
                            title: "Auto-open Designer Studio",
                            subtitle: "Open the canvas editor immediately after capturing a screenshot.",
                            isOn: $settings.autoOpenEditor
                        )

                        insetDivider()

                        switchRow(
                            title: "Play camera shutter sound",
                            subtitle: "Play subtle audio confirmation when capturing or copying.",
                            isOn: $settings.playShutterSound
                        )
                    }
                }
            }
        }
    }

    private func shortcutRow(
        title: String,
        subtitle: String,
        targetId: String,
        combination: Binding<KeyCombination>,
        defaultCombo: KeyCombination,
        onTry: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 8)

            Button(action: onTry) {
                Text("Try")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)

            ShortcutRecorderField(
                targetId: targetId,
                keyCombination: combination,
                defaultCombination: defaultCombo
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - 2. Designer Tools Pane

    private var designerToolsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            paneHeader(for: .designerTools)

            // Measurement & Grid Audit
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Measurement & snapping")

                insetCard {
                    VStack(spacing: 0) {
                        switchRow(
                            title: "Smart distance & edge snapping",
                            subtitle: "Snap vertical and horizontal rulers automatically to buttons, labels, and borders.",
                            isOn: $settings.enableSmartDistance
                        )

                        insetDivider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Spacing grid audit")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Highlight off-grid measurements in amber while auditing layouts.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }

                            Spacer(minLength: 12)

                            Picker("", selection: $settings.gridAuditUnit) {
                                Text("4 px Grid").tag(4)
                                Text("8 px Grid").tag(8)
                                Text("Off").tag(1)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 210)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }

            // Tool Keyboard Shortcuts
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Studio keyboard shortcuts")

                insetCard {
                    VStack(spacing: 0) {
                        studioShortcutRow(symbol: "cursorarrow", color: Color(red: 0.039, green: 0.518, blue: 1.0), name: "Select & Drag", detail: "Select, move, or resize annotations", key: "V")
                        insetDivider(leading: 50)
                        studioShortcutRow(symbol: "ruler", color: Color(red: 1.0, green: 0.584, blue: 0.0), name: "Dimension Ruler", detail: "Horizontal & vertical snap caliper", key: "D")
                        insetDivider(leading: 50)
                        studioShortcutRow(symbol: "arrow.up.right", color: Color(red: 0.188, green: 0.820, blue: 0.345), name: "Arrow Annotation", detail: "Single, double, or pointed callouts", key: "A")
                        insetDivider(leading: 50)
                        studioShortcutRow(symbol: "character.textbox", color: Color(red: 0.369, green: 0.361, blue: 0.902), name: "Text Callout", detail: "Inline plain, pill, or quote styling", key: "T")
                        insetDivider(leading: 50)
                        studioShortcutRow(symbol: "rectangle", color: Color(red: 1.0, green: 0.216, blue: 0.373), name: "Rectangle Frame", detail: "Stroked outline or solid fill box", key: "R")
                        insetDivider(leading: 50)
                        studioShortcutRow(symbol: "arrow.uturn.backward", color: Color(red: 0.557, green: 0.557, blue: 0.576), name: "Undo / Redo", detail: "Step forward or back in annotation history", key: "⌘Z / ⌘⇧Z")
                    }
                }
            }
        }
    }

    private func studioShortcutRow(symbol: String, color: Color, name: String, detail: String, key: String) -> some View {
        HStack(spacing: 12) {
            SquircleBadge(symbol: symbol, color: color, size: 22, cornerRadius: 5.5, symbolSize: 11)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .medium))
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.75)
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 3. Switcher Pane

    private var switcherPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            paneHeader(for: .switcher)

            // Trigger Selector Cards
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Activation shortcut")

                HStack(spacing: 12) {
                    triggerCard(
                        trigger: .commandTab,
                        keys: "⌘ + Tab",
                        title: "Command + Tab",
                        subtitle: "Replace the stock macOS app switcher with window-level switching."
                    )

                    triggerCard(
                        trigger: .optionTab,
                        keys: "⌥ + Tab",
                        title: "Option + Tab",
                        subtitle: "Run alongside macOS Command-Tab without overriding the system HUD."
                    )
                }

                insetCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("After releasing shortcut")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Choose whether releasing the modifier key switches focus immediately.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.afterRelease) {
                                Text("Focus Window").tag("Focus")
                                Text("Keep Open").tag("Hold")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        insetDivider()

                        switchRow(
                            title: "Show live window preview badge",
                            subtitle: "Display live status indicators on minimized or audio-playing windows.",
                            isOn: $settings.showWindowBadges
                        )
                    }
                }
            }

            // Filtering Scope
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Scope & ordering")

                insetCard {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Applications")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Filter switcher items by running applications.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.appsFilter) {
                                Text("All apps").tag("All apps")
                                Text("Active app").tag("Active app")
                            }
                            .frame(width: 170)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        insetDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("macOS Spaces")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Show windows from every Space or only the current desktop.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.spacesFilter) {
                                Text("All Spaces").tag("All Spaces")
                                Text("Current Space").tag("Current Space")
                            }
                            .frame(width: 170)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }

            // Visibility Flags
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Included windows")

                insetCard {
                    VStack(spacing: 0) {
                        switchRow(
                            title: "Minimized windows",
                            subtitle: "Keep Dock-minimized windows accessible in the switcher.",
                            isOn: $settings.showMinimizedWindows
                        )
                        insetDivider()
                        switchRow(
                            title: "Hidden apps",
                            subtitle: "Include windows belonging to Command-H hidden apps.",
                            isOn: $settings.showHiddenWindows
                        )
                        insetDivider()
                        switchRow(
                            title: "Fullscreen spaces",
                            subtitle: "Include apps occupying dedicated fullscreen Spaces.",
                            isOn: $settings.showFullscreenWindows
                        )
                        insetDivider()
                        switchRow(
                            title: "Running apps with no open windows",
                            subtitle: "List background-open apps like Mail or Finder even with zero windows.",
                            isOn: $settings.showAppsWithNoWindows
                        )
                    }
                }
            }

            // Navigation Hotkeys
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Quick actions while HUD is open")

                insetCard {
                    HStack(spacing: 8) {
                        hotkeyChip(keys: "↑ ↓ ← →", label: "Navigate")
                        hotkeyChip(keys: "Return", label: "Focus")
                        hotkeyChip(keys: "W", label: "Close Window")
                        hotkeyChip(keys: "Q", label: "Quit App")
                        hotkeyChip(keys: "H / M", label: "Hide / Min")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(12)
                }
            }
        }
    }

    private func triggerCard(trigger: ShortcutTrigger, keys: String, title: String, subtitle: String) -> some View {
        let isSelected = settings.primaryShortcut == trigger
        let accent = settings.accentColor

        return Button(action: {
            settings.primaryShortcut = trigger
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(keys)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .primary)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? accent : Color.primary.opacity(0.07))
                        )

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(accent)
                    }
                }

                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? accent : cardHairline, lineWidth: isSelected ? 2 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func hotkeyChip(keys: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. Appearance Pane (with Compact Cards + 2x2 Grid)

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            paneHeader(for: .appearance)

            // 2x2 Layout Picker Grid
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Switcher layout")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12)
                    ],
                    spacing: 12
                ) {
                    // 1. Thumbnails
                    appearanceStyleCard(
                        style: .thumbnails,
                        label: "Thumbnails",
                        description: "Live window previews in floating cards"
                    ) {
                        ZStack {
                            Color(red: 0.11, green: 0.11, blue: 0.13)
                            HStack(spacing: 8) {
                                miniThumbnailCard(isSelected: false)
                                miniThumbnailCard(isSelected: true)
                            }
                            .padding(10)
                        }
                    }

                    // 2. App Icons (Command+Tab)
                    appearanceStyleCard(
                        style: .icons,
                        label: "App Icons",
                        description: "Horizontal Command-Tab icon strip"
                    ) {
                        ZStack {
                            Color(red: 0.11, green: 0.11, blue: 0.13)
                            HStack(spacing: 8) {
                                miniCmdTabIcon(symbol: "terminal.fill", bg: Color(white: 0.20), name: "Ghostty", isSelected: false)
                                miniCmdTabIcon(symbol: "envelope.fill", bg: Color(red: 0.04, green: 0.52, blue: 1.0), name: "Mail", isSelected: true)
                                miniCmdTabIcon(symbol: "safari.fill", bg: Color(red: 0.19, green: 0.69, blue: 0.78), name: "Safari", isSelected: false)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.08))
                                    .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 0.7))
                            )
                        }
                    }

                    // 3. Window Titles (4-Column List)
                    appearanceStyleCard(
                        style: .titles,
                        label: "Window Titles",
                        description: "4-column vertical window list"
                    ) {
                        ZStack {
                            Color(red: 0.11, green: 0.11, blue: 0.13)
                            VStack(spacing: 3) {
                                miniTitleRow(app: "Ghostty", color: Color(white: 0.25), title: "workspace", isSelected: false)
                                miniTitleRow(app: "Mail", color: Color(red: 0.04, green: 0.52, blue: 1.0), title: "Release Notes", isSelected: true)
                                miniTitleRow(app: "Code", color: Color(red: 0.19, green: 0.52, blue: 0.90), title: "SettingsView.swift", isSelected: false)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 0.6))
                            )
                            .padding(.horizontal, 12)
                        }
                    }

                    // 4. Compact Cards (2x2 Bento Grid)
                    appearanceStyleCard(
                        style: .cards,
                        label: "Compact Cards",
                        description: "2–3 column tile grid with app & title"
                    ) {
                        ZStack {
                            Color(red: 0.11, green: 0.11, blue: 0.13)
                            VStack(spacing: 5) {
                                HStack(spacing: 5) {
                                    miniCompactCard(app: "Code", title: "App.swift", color: Color(red: 0.04, green: 0.52, blue: 1.0), isSelected: true)
                                    miniCompactCard(app: "Mail", title: "Inbox", color: Color(red: 0.20, green: 0.68, blue: 0.96), isSelected: false)
                                }
                                HStack(spacing: 5) {
                                    miniCompactCard(app: "Spotify", title: "Playing", color: Color(red: 0.18, green: 0.80, blue: 0.44), isSelected: false)
                                    miniCompactCard(app: "Figma", title: "Specs", color: Color(red: 0.68, green: 0.32, blue: 0.87), isSelected: false)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                }
            }

            // Sizing, Theme & Placement
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Sizing & theme")

                insetCard {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Card & icon size")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Scale dimensions of thumbnails, strips, or tiles in the HUD.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.cardSize) {
                                Text("Small").tag(CardSize.small)
                                Text("Medium").tag(CardSize.medium)
                                Text("Large").tag(CardSize.large)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        insetDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Color appearance")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Follow macOS System appearance or lock Light / Dark glass.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.themeMode) {
                                Text("System").tag(ThemeMode.system)
                                Text("Light").tag(ThemeMode.light)
                                Text("Dark").tag(ThemeMode.dark)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        insetDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Display placement")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Choose where the switcher appears on multi-monitor setups.")
                                    .font(.system(size: 11.5))
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
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        insetDivider()

                        switchRow(
                            title: "Smooth motion transitions",
                            subtitle: "Animate switcher focus rings and panel dismissal.",
                            isOn: $settings.animationsEnabled
                        )
                    }
                }
            }

            // Optics & Surface Styling
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Glass & surface")

                insetCard {
                    VStack(spacing: 0) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Accent highlight")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Selection ring and active badge tint.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 7) {
                                accentDot(hex: "#0A84FF")
                                accentDot(hex: "#5E5CE6")
                                accentDot(hex: "#BF5AF2")
                                accentDot(hex: "#FF375F")
                                accentDot(hex: "#30D158")
                                accentDot(hex: "#FF9F0A")

                                TextField("#0A84FF", text: $settings.customAccentColorHex)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 72)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        insetDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("HUD corner radius")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Curvature of outer switcher container (\(Int(settings.hudCornerRadius)) pt)")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Slider(value: $settings.hudCornerRadius, in: 16...32, step: 2)
                                .frame(width: 190)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        insetDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Specular border width")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Outer rim stroke around the glass surface (\(String(format: "%.1f", settings.borderWidth)) pt)")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Slider(value: $settings.borderWidth, in: 0.5...3.0, step: 0.5)
                                .frame(width: 190)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        insetDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Drop shadow depth")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Adjust HUD elevation above open desktop windows.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.shadowDepth) {
                                Text("Subtle").tag("Subtle Depth")
                                Text("Balanced").tag("Apple HIG Balanced")
                                Text("Floating").tag("Floating Deep")
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 220)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
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
        let isHovered = uiState.hoveredStyle == style && !isSelected
        let accent = settings.accentColor

        return Button(action: {
            withAnimation(.easeInOut(duration: 0.16)) {
                settings.switcherStyle = style
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                content()
                    .frame(height: 82)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .padding(6)

                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(label)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(accent)
                    } else {
                        Circle()
                            .stroke(Color.primary.opacity(0.20), lineWidth: 1.2)
                            .frame(width: 15, height: 15)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .padding(.top, 2)
            }
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? accent : (isHovered ? Color.primary.opacity(0.18) : cardHairline),
                        lineWidth: isSelected ? 2 : 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            uiState.hoveredStyle = hovering ? style : (uiState.hoveredStyle == style ? nil : uiState.hoveredStyle)
        }
    }

    private func miniThumbnailCard(isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Circle()
                    .fill(isSelected ? settings.accentColor : Color.white.opacity(0.35))
                    .frame(width: 7, height: 7)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.45))
                    .frame(width: 34, height: 4)
                Spacer()
            }
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white.opacity(isSelected ? 0.20 : 0.10))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(5)
        .frame(width: 82, height: 52)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? settings.accentColor : Color.white.opacity(0.12), lineWidth: isSelected ? 1.5 : 0.6)
        )
    }

    private func miniCmdTabIcon(symbol: String, bg: Color, name: String, isSelected: Bool) -> some View {
        VStack(spacing: 3) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(bg)
                    .frame(width: 24, height: 24)
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.22) : Color.clear)
            )

            Text(name)
                .font(.system(size: 7.5, weight: isSelected ? .bold : .medium))
                .foregroundColor(.white.opacity(isSelected ? 1.0 : 0.72))
        }
    }

    private func miniTitleRow(app: String, color: Color, title: String, isSelected: Bool) -> some View {
        HStack(spacing: 5) {
            Text(app)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(.white.opacity(isSelected ? 0.98 : 0.60))
                .frame(width: 34, alignment: .trailing)

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(color)
                .frame(width: 9, height: 9)

            Text(title)
                .font(.system(size: 8.5, weight: isSelected ? .semibold : .regular))
                .foregroundColor(.white.opacity(isSelected ? 1.0 : 0.80))
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? settings.accentColor : Color.clear)
        )
    }

    private func miniCompactCard(app: String, title: String, color: Color, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(color)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 8.5, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text(app)
                    .font(.system(size: 7))
                    .foregroundColor(.white.opacity(0.60))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.07))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(isSelected ? settings.accentColor : Color.white.opacity(0.10), lineWidth: isSelected ? 1.4 : 0.6)
        )
    }

    private func accentDot(hex: String) -> some View {
        let color = Color(hex: hex) ?? .blue
        let isSelected = settings.customAccentColorHex.uppercased() == hex.uppercased()

        return Button(action: {
            settings.customAccentColorHex = hex
        }) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)

                if isSelected {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 2)
                        .frame(width: 14, height: 14)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Apps & Rules Pane

    private var appsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                paneHeader(for: .apps)
                Spacer()
                Button(action: chooseApplicationFromDisk) {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add App")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(cardHairline, lineWidth: 0.75)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .top, spacing: 14) {
                // Left Sidebar List of Configured Applications
                insetCard {
                    VStack(spacing: 0) {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 2) {
                                ForEach(settings.exceptionsList) { app in
                                    let isSelected = uiState.selectedExceptionId == app.bundleId
                                    Button(action: {
                                        uiState.selectedExceptionId = app.bundleId
                                    }) {
                                        HStack(spacing: 9) {
                                            NativeAppIconView(bundleId: app.bundleId, size: 22)

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(app.name)
                                                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                                    .foregroundColor(isSelected ? .white : .primary)
                                                    .lineLimit(1)

                                                Text(app.ignoreShortcuts == "When in focus" ? "Pass-through" : "Switcher Rule")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                                            }
                                            Spacer(minLength: 0)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(isSelected ? Color(red: 0.039, green: 0.518, blue: 1.0) : Color.clear)
                                        )
                                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(8)
                        }

                        insetDivider(leading: 0)

                        HStack(spacing: 0) {
                            Button(action: chooseApplicationFromDisk) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .medium))
                                    .frame(width: 30, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Rectangle()
                                .fill(cardHairline)
                                .frame(width: 1, height: 14)

                            Button(action: removeSelectedException) {
                                Image(systemName: "minus")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(canRemoveSelected ? .primary : .secondary.opacity(0.4))
                                    .frame(width: 30, height: 26)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canRemoveSelected)

                            Spacer()
                        }
                        .padding(.horizontal, 4)
                    }
                }
                .frame(width: 210)
                .frame(maxHeight: .infinity)

                // Right Rule Inspector
                if let index = settings.exceptionsList.firstIndex(where: { $0.bundleId == uiState.selectedExceptionId }) {
                    let selectedApp = settings.exceptionsList[index]

                    VStack(alignment: .leading, spacing: 14) {
                        insetCard {
                            HStack(spacing: 12) {
                                NativeAppIconView(bundleId: selectedApp.bundleId, size: 42)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedApp.name)
                                        .font(.system(size: 15, weight: .bold))
                                    Text(selectedApp.bundleId)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .padding(16)
                        }

                        insetCard {
                            VStack(spacing: 0) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Global shortcuts")
                                            .font(.system(size: 13, weight: .medium))
                                        Text("Ignore Window Switcher triggers when this app is frontmost.")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Picker("", selection: Binding(
                                        get: { settings.exceptionsList[index].ignoreShortcuts },
                                        set: { settings.exceptionsList[index].ignoreShortcuts = $0 }
                                    )) {
                                        Text("Pass-through").tag("When in focus")
                                        Text("Active normally").tag("Never")
                                    }
                                    .frame(width: 150)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)

                                insetDivider()

                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("HUD visibility")
                                            .font(.system(size: 13, weight: .medium))
                                        Text("Control whether this app appears inside the switcher strip.")
                                            .font(.system(size: 11.5))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Picker("", selection: Binding(
                                        get: { settings.exceptionsList[index].hideWindows },
                                        set: { settings.exceptionsList[index].hideWindows = $0 }
                                    )) {
                                        Text("Hide when empty").tag("When no open window")
                                        Text("Always hide").tag("Always")
                                        Text("Always show").tag("Never")
                                    }
                                    .frame(width: 150)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        }

                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    insetCard {
                        VStack(spacing: 10) {
                            Image(systemName: "app.dashed")
                                .font(.system(size: 28, weight: .light))
                                .foregroundColor(.secondary)
                            Text("No application selected")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Add an application to configure per-app pass-through shortcuts or visibility rules.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 280)
                            Button("Add App…", action: chooseApplicationFromDisk)
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .padding(.top, 4)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(24)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var canRemoveSelected: Bool {
        settings.exceptionsList.contains(where: { $0.bundleId == uiState.selectedExceptionId })
    }

    private func removeSelectedException() {
        settings.exceptionsList.removeAll(where: { $0.bundleId == uiState.selectedExceptionId })
        uiState.selectedExceptionId = settings.exceptionsList.first?.bundleId ?? ""
    }

    // MARK: - 6. General Pane (System, Permissions, Updates, Maintenance)

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            paneHeader(for: .general)

            // System Integration
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("System & startup")

                insetCard {
                    VStack(spacing: 0) {
                        switchRow(
                            title: "Start at login",
                            subtitle: "Launch Window Switcher automatically when you sign in.",
                            isOn: $settings.startAtLogin
                        )

                        insetDivider()

                        switchRow(
                            title: "Show menu bar icon",
                            subtitle: "Display quick settings and capture actions in the macOS menu bar.",
                            isOn: $settings.showMenubarIcon
                        )

                        insetDivider()

                        switchRow(
                            title: "Background thumbnail cache",
                            subtitle: "Pre-capture open window previews so the HUD opens in 0 ms.",
                            isOn: $settings.captureInBackground
                        )
                    }
                }
            }

            // macOS Privacy Permissions
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Permissions")

                insetCard {
                    VStack(spacing: 0) {
                        permissionRow(
                            symbol: "accessibility",
                            color: Color(red: 0.039, green: 0.518, blue: 1.0),
                            title: "Accessibility",
                            subtitle: "Required for global Option/Command-Tab interception and window focus.",
                            granted: permissions.hasAccessibility,
                            action: { permissions.requestAccessibility() }
                        )

                        insetDivider(leading: 50)

                        permissionRow(
                            symbol: "record.circle",
                            color: Color(red: 0.188, green: 0.820, blue: 0.345),
                            title: "Screen Recording",
                            subtitle: "Required for frozen frame screenshots, window previews, and Designer Studio.",
                            granted: permissions.hasScreenRecording,
                            action: { permissions.requestScreenRecording() }
                        )
                    }
                }
            }

            // Software Updates
            VStack(alignment: .leading, spacing: 8) {
                sectionTitle("Software updates")

                insetCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            AppBrandingIcon(size: 36, cornerRadius: 8)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("Window Switcher")
                                        .font(.system(size: 13.5, weight: .semibold))
                                    Text("v\(updater.currentVersion)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }
                                updateStatusSubtitle
                            }

                            Spacer()

                            updateActionButton
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)

                        insetDivider()

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Check for updates")
                                    .font(.system(size: 13, weight: .medium))
                                Text("Fetch release builds directly from GitHub Releases.")
                                    .font(.system(size: 11.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Picker("", selection: $settings.updatePolicy) {
                                Text("Automatically on launch").tag("Check for updates periodically")
                                Text("Manually only").tag("Check manually")
                            }
                            .frame(width: 210)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }

            // Reset Maintenance Row
            HStack {
                if uiState.didConfirmReset {
                    Text("Preferences restored to factory defaults.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Reset All Settings to Defaults") {
                    settings.resetToDefaults()
                    uiState.didConfirmReset = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var updateStatusSubtitle: some View {
        switch updater.status {
        case .idle:
            Text("Ready to check GitHub Releases for newer builds.")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
        case .checking:
            Text("Checking GitHub Releases…")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
        case .upToDate(let ver):
            Text("You are up to date on version \(ver).")
                .font(.system(size: 11.5))
                .foregroundColor(Color(red: 0.16, green: 0.72, blue: 0.30))
        case .available(let ver, let notes, _, _):
            Text("Version \(ver) available — \(notes)")
                .font(.system(size: 11.5))
                .foregroundColor(Color(red: 0.039, green: 0.518, blue: 1.0))
                .lineLimit(1)
        case .downloading(let progress):
            Text("Downloading update… \(Int(progress * 100))%")
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundColor(.secondary)
        case .installing:
            Text("Installing update into /Applications…")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
        case .readyToRelaunch:
            Text("Update installed. Relaunch Window Switcher to finish.")
                .font(.system(size: 11.5))
                .foregroundColor(Color(red: 0.16, green: 0.72, blue: 0.30))
        case .error(let msg):
            Text("Unable to check: \(msg)")
                .font(.system(size: 11.5))
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        switch updater.status {
        case .checking, .downloading, .installing:
            ProgressView()
                .controlSize(.small)
        case .available(_, _, let downloadUrl, _):
            Button("Download & Install") {
                updater.downloadAndInstall(from: downloadUrl)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        case .readyToRelaunch:
            Button("Relaunch Now") {
                updater.relaunch()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        default:
            Button("Check Now") {
                updater.checkForUpdates(userInitiated: true)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func permissionRow(
        symbol: String,
        color: Color,
        title: String,
        subtitle: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            SquircleBadge(symbol: symbol, color: color, size: 22, cornerRadius: 5.5, symbolSize: 11)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Granted")
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundColor(Color(red: 0.16, green: 0.72, blue: 0.30))
            } else {
                Button("Grant", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Shared Apple System Settings Primitives

    private func paneHeader(for tab: SettingsTab) -> some View {
        HStack(spacing: 12) {
            SquircleBadge(
                symbol: tab.icon,
                color: tab.badgeColor,
                size: 28,
                cornerRadius: 7,
                symbolSize: 14
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(tab.rawValue)
                    .font(.system(size: 20, weight: .bold))
                Text(tab.subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundColor(.secondary)
            .padding(.leading, 4)
    }

    private func insetCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(cardHairline, lineWidth: 0.75)
            )
    }

    private func insetDivider(leading: CGFloat = 16) -> some View {
        Rectangle()
            .fill(cardHairline)
            .frame(height: 1)
            .padding(.leading, leading)
    }

    private func switchRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - App Open Panel Helper

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

// MARK: - macOS Squircle Icon Badge

private struct SquircleBadge: View {
    let symbol: String
    let color: Color
    var isInvertedOnBlueSelection: Bool = false
    var showSelectionRim: Bool = false
    var size: CGFloat = 21
    var cornerRadius: CGFloat = 5.5
    var symbolSize: CGFloat = 11

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    isInvertedOnBlueSelection
                        ? AnyShapeStyle(Color.white)
                        : AnyShapeStyle(
                            LinearGradient(
                                colors: [color.opacity(0.92), color],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    showSelectionRim
                        ? Color.white.opacity(0.80)
                        : Color.white.opacity(0.22),
                    lineWidth: showSelectionRim ? 1.25 : 0.6
                )

            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundColor(isInvertedOnBlueSelection ? color : .white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.10), radius: 1, y: 0.5)
    }
}

// MARK: - Interactive Shortcut Recorder Pill

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
                            .fill(Color(red: 0.039, green: 0.518, blue: 1.0))
                            .frame(width: 5, height: 5)
                        Text("Press keys…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                } else if keyCombination.isEmpty {
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
            .padding(.horizontal, 8)
            .frame(width: 96, height: 24)
            .background(
                Capsule()
                    .fill(isRecordingThis ? Color.blue.opacity(0.10) : Color.primary.opacity(0.05))
            )
            .overlay(
                Capsule()
                    .stroke(
                        isRecordingThis
                            ? Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.85)
                            : Color.primary.opacity(0.12),
                        lineWidth: isRecordingThis ? 1.2 : 0.75
                    )
            )
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
