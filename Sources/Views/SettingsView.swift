import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Settings Navigation Tabs

public enum SettingsTab: String, CaseIterable, Identifiable {
    case screenshots = "Screenshots"
    case designerTools = "Designer Tools"
    case switcher = "Switcher"
    case appearance = "Appearance"
    case apps = "Apps & Rules"
    case general = "General"
    case privacy = "Privacy"
    case about = "About"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .designerTools: return "ruler.fill"
        case .switcher: return "macwindow.on.rectangle"
        case .appearance: return "paintbrush.fill"
        case .apps: return "square.grid.2x2.fill"
        case .general: return "gearshape.fill"
        case .privacy: return "lock.fill"
        case .about: return "info.circle.fill"
        }
    }

    public var badgeColor: Color {
        switch self {
        case .screenshots: return Color(red: 0.039, green: 0.518, blue: 1.0)    // System Blue
        case .designerTools: return Color(red: 1.0, green: 0.584, blue: 0.0)    // System Orange
        case .switcher: return Color(red: 0.369, green: 0.361, blue: 0.902)     // System Indigo
        case .appearance: return Color(red: 1.0, green: 0.216, blue: 0.373)     // System Rose
        case .apps: return Color(red: 0.188, green: 0.820, blue: 0.345)         // System Green
        case .general: return Color(red: 0.431, green: 0.431, blue: 0.451)      // System Slate
        case .privacy: return Color(red: 1.0, green: 0.231, blue: 0.188)        // System Red
        case .about: return Color(red: 0.557, green: 0.557, blue: 0.576)        // System Gray
        }
    }

    public var groupIndex: Int {
        switch self {
        case .screenshots, .designerTools: return 0
        case .switcher, .appearance, .apps: return 1
        case .general, .privacy, .about: return 2
        }
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
    SettingsSearchItem(title: "Area & window capture shortcut", subtitle: "Freeze all displays and drag a box or click a window", keywords: "screenshot option capture freeze shadow", tab: .screenshots),
    SettingsSearchItem(title: "Capture active window shortcut", subtitle: "Snap the frontmost window immediately with elevation shadow", keywords: "window capture active shadow", tab: .screenshots),
    SettingsSearchItem(title: "Screen text recognition (OCR)", subtitle: "Copy detected text directly from any frozen region", keywords: "ocr extract copy text", tab: .screenshots),
    SettingsSearchItem(title: "Auto-open Designer Studio", subtitle: "Launch the canvas editor right after capture", keywords: "editor studio canvas workflow", tab: .screenshots),
    SettingsSearchItem(title: "Play camera shutter sound", subtitle: "Play audio feedback on capture", keywords: "sound audio shutter", tab: .screenshots),

    SettingsSearchItem(title: "Smart distance & edge snapping", subtitle: "Snap vertical and horizontal rulers to UI edges", keywords: "ruler dimension snap measure distance", tab: .designerTools),
    SettingsSearchItem(title: "Spacing grid audit unit", subtitle: "Flag spacings off the 4 px or 8 px layout grid", keywords: "4px 8px grid rhythm audit spacing", tab: .designerTools),
    SettingsSearchItem(title: "Studio keyboard shortcuts", subtitle: "Keys for Select, Ruler, Arrow, Text, Rectangle, Undo", keywords: "shortcuts keys arrow text rectangle undo", tab: .designerTools),

    SettingsSearchItem(title: "Switcher activation shortcut", subtitle: "Bind Option+Tab or replace macOS Command+Tab", keywords: "command option tab shortcut hotkey trigger", tab: .switcher),
    SettingsSearchItem(title: "After releasing modifier", subtitle: "Focus window immediately or keep HUD open", keywords: "release focus hold keep open", tab: .switcher),
    SettingsSearchItem(title: "Applications & Spaces scope", subtitle: "Filter windows across all apps or current active Space", keywords: "filter spaces screens active apps", tab: .switcher),
    SettingsSearchItem(title: "Included window states", subtitle: "Minimized, hidden, fullscreen, or windowless apps", keywords: "minimized hidden fullscreen no windows", tab: .switcher),

    SettingsSearchItem(title: "Live switcher layout style", subtitle: "Thumbnails, App Icons, Window Titles, or Compact Cards", keywords: "thumbnails icons titles compact cards bento command tab", tab: .appearance),
    SettingsSearchItem(title: "Tile size & color appearance", subtitle: "Small, Medium, or Large in System, Light, or Dark", keywords: "size small medium large theme light dark system", tab: .appearance),
    SettingsSearchItem(title: "Accent highlight color", subtitle: "Customize selection border tint or hex code", keywords: "color accent hex ring highlight", tab: .appearance),
    SettingsSearchItem(title: "HUD curvature, border & shadow", subtitle: "Corner radius, specular stroke, and drop shadow depth", keywords: "corner radius border shadow depth elevation", tab: .appearance),

    SettingsSearchItem(title: "Excluded apps & pass-through rules", subtitle: "Hide specific apps or bypass shortcuts in full-screen apps", keywords: "exclude ignore rules game vm pass through finder", tab: .apps),

    SettingsSearchItem(title: "Launch at login & menu bar icon", subtitle: "Start automatically at login and toggle status icon", keywords: "login startup menubar icon spotlight", tab: .general),
    SettingsSearchItem(title: "Haptic & sound feedback on switch", subtitle: "Trackpad Force Touch tick and audio feedback when cycling", keywords: "haptic vibration sound feedback switch tick", tab: .general),
    SettingsSearchItem(title: "Software updates & beta channel", subtitle: "Check schedule and pre-release GitHub builds", keywords: "update version check github beta daily", tab: .general),
    SettingsSearchItem(title: "Backup, export & import settings", subtitle: "Save preferences to JSON or restore from another Mac", keywords: "backup export import json reset", tab: .general),

    SettingsSearchItem(title: "Accessibility & Screen Recording", subtitle: "Verify required macOS privacy permissions", keywords: "permissions accessibility screen recording privacy lock", tab: .privacy),
    SettingsSearchItem(title: "About Window Switcher", subtitle: "Version, build info, source code, releases, and updates", keywords: "about version github release build source code", tab: .about)
]

// MARK: - Observable UI State (Zero @State macro usage for CLI builds)

public final class SettingsUIState: ObservableObject {
    public static let shared = SettingsUIState()

    @Published public var selectedTab: SettingsTab = .screenshots
    @Published public var searchQuery: String = ""

    // Interactive preview stage state
    @Published public var previewSelectedIndex: Int = 1
    @Published public var rulerDemoGap: Int = 12

    // Hover & transient UI feedback
    @Published public var hoveredTab: SettingsTab? = nil
    @Published public var hoveredStyle: SwitcherStyle? = nil
    @Published public var hoveredBentoId: String? = nil
    @Published public var statusMessage: String? = nil
    @Published public var copiedBuildInfo: Bool = false

    // Exceptions selection
    @Published public var selectedExceptionId: String = "com.apple.finder"

    // Shortcut recording
    @Published public var recordingTargetId: String? = nil
    public var ocrEventMonitor: Any? = nil

    public func flashStatus(_ message: String) {
        statusMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) { [weak self] in
            if self?.statusMessage == message {
                self?.statusMessage = nil
            }
        }
    }

    public func flashCopiedBuild() {
        copiedBuildInfo = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.copiedBuildInfo = false
        }
    }

    public func startRecording(targetId: String, onRecorded: @escaping (KeyCombination) -> Void) {
        stopRecording()
        recordingTargetId = targetId

        ocrEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 {
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

// MARK: - Full-Bleed Native Liquid Glass Backdrops

private struct SidebarGlassBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .sidebar

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

private struct DetailSheetBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .windowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .windowBackground
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

// MARK: - SwiftUI Liquid Glass Effect Helpers (macOS 26+ Native, Fallback on 14–15)

private struct LiquidGlassShapeModifier<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    let interactive: Bool
    let fallbackFill: Color
    let specularStrokeOpacity: Double

    @available(macOS 26.0, *)
    private func buildGlass() -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if interactive { glass = glass.interactive() }
        return glass
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(buildGlass(), in: shape)
        } else {
            content
                .background(shape.fill(fallbackFill))
                .overlay(
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(specularStrokeOpacity),
                                Color.white.opacity(specularStrokeOpacity * 0.25)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                )
        }
    }
}

private extension View {
    func applyLiquidGlass<S: InsettableShape>(
        in shape: S,
        tint: Color? = nil,
        interactive: Bool = false,
        fallbackFill: Color = Color.white.opacity(0.65),
        specularOpacity: Double = 0.55
    ) -> some View {
        self.modifier(
            LiquidGlassShapeModifier(
                shape: shape,
                tint: tint,
                interactive: interactive,
                fallbackFill: fallbackFill,
                specularStrokeOpacity: specularOpacity
            )
        )
    }
}

// MARK: - Root Settings View

public struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject var updater = UpdateManager.shared
    @ObservedObject private var uiState = SettingsUIState.shared
    @Environment(\.colorScheme) private var colorScheme

    private let accentBlue = Color(red: 0.039, green: 0.518, blue: 1.0)

    private var sheetTintOverlay: Color {
        colorScheme == .dark
            ? Color(red: 0.11, green: 0.11, blue: 0.125).opacity(0.84)
            : Color(white: 0.99).opacity(0.88)
    }

    private var glowingCardFill: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.065)
            : Color.white.opacity(0.76)
    }

    private var cardBorderGradient: LinearGradient {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color.white.opacity(0.18), Color.white.opacity(0.05)]
                : [Color.white.opacity(0.95), Color.black.opacity(0.06)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cardGlowShadow: Color {
        colorScheme == .dark
            ? Color.black.opacity(0.16)
            : Color.black.opacity(0.025)
    }

    private var innerDividerColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.065)
    }

    public init() {}

    public var body: some View {
        ZStack(alignment: .leading) {
            // Single continuous window surface (zero middle gap or white seam)
            DetailSheetBackdrop()
                .ignoresSafeArea(.all)

            sheetTintOverlay
                .ignoresSafeArea(.all)

            HStack(spacing: 0) {
                sidebarView
                    .frame(width: 214)

                Rectangle()
                    .fill(colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08))
                    .frame(width: 1)
                    .ignoresSafeArea(.all)

                VStack(spacing: 0) {
                    inlineTopBar

                    detailContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 780, minHeight: 560)
        .frame(width: 850, height: 620)
        .ignoresSafeArea(.all)
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

    // MARK: - Full-Bleed Liquid Glass Sidebar

    private var sidebarView: some View {
        ZStack {
            SidebarGlassBackdrop()
                .ignoresSafeArea(.all)

            // Subtle top-to-bottom pearlescent glass veil extending behind traffic lights
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color.white.opacity(0.03), Color.clear]
                    : [Color.white.opacity(0.28), Color.white.opacity(0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(.all)

            VStack(spacing: 0) {
                // Headroom purely for traffic light controls — NO opaque bar
                Spacer().frame(height: 44)

                // Liquid Glass Capsule Search Input
                HStack(spacing: 7) {
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
                                .foregroundColor(.secondary.opacity(0.75))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 11)
                .frame(height: 30)
                .applyLiquidGlass(
                    in: Capsule(),
                    interactive: true,
                    fallbackFill: colorScheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.55)
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

                // Sidebar Items
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(SettingsTab.allCases.filter { $0.groupIndex == 0 }) { tab in
                            sidebarRow(tab: tab)
                        }

                        sidebarDivider

                        ForEach(SettingsTab.allCases.filter { $0.groupIndex == 1 }) { tab in
                            sidebarRow(tab: tab)
                        }

                        sidebarDivider

                        ForEach(SettingsTab.allCases.filter { $0.groupIndex == 2 }) { tab in
                            sidebarRow(tab: tab)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }

                Spacer(minLength: 0)

                // Show Details Progressive Disclosure Toggle
                HStack(spacing: 8) {
                    Text("Show Details")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)

                    Spacer()

                    Toggle("", isOn: $settings.showDetailsInSettings)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .padding(.top, 8)
            }
        }
    }

    private var sidebarDivider: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.06))
            .frame(height: 1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
    }

    private func sidebarRow(tab: SettingsTab) -> some View {
        let isSearching = !uiState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isSelected = uiState.selectedTab == tab && !isSearching
        let isHovered = uiState.hoveredTab == tab && !isSelected

        return Button(action: {
            uiState.searchQuery = ""
            uiState.selectedTab = tab
        }) {
            HStack(spacing: 9) {
                SquircleBadge(
                    symbol: tab.icon,
                    color: tab.badgeColor,
                    size: 20,
                    cornerRadius: 5.5,
                    symbolSize: 10.5
                )

                Text(tab.rawValue)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if tab == .privacy && (!permissions.hasAccessibility || !permissions.hasScreenRecording) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 29)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(colorScheme == .dark ? Color.white.opacity(0.11) : Color.black.opacity(0.065))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.6)
                            )
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            uiState.hoveredTab = hovering ? tab : (uiState.hoveredTab == tab ? nil : uiState.hoveredTab)
        }
    }

    // MARK: - Seamless Inline Header

    private var inlineTopBar: some View {
        let trimmedQuery = uiState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        return HStack(spacing: 12) {
            Text(trimmedQuery.isEmpty ? uiState.selectedTab.rawValue : "Search results")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.primary)

            Spacer()

            if !trimmedQuery.isEmpty {
                glassPillButton("Clear search", action: { uiState.searchQuery = "" })
            } else if uiState.selectedTab == .screenshots {
                Button(action: { ScreenshotCoordinator.shared.startAreaCapture() }) {
                    HStack(spacing: 5) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(accentBlue)
                        Text("Take Screenshot")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 27)
                    .applyLiquidGlass(
                        in: Capsule(),
                        interactive: true,
                        fallbackFill: glowingCardFill
                    )
                }
                .buttonStyle(.plain)
            } else if uiState.selectedTab == .apps {
                Button(action: chooseApplicationFromDisk) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Add App")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundColor(.primary)
                    .padding(.horizontal, 12)
                    .frame(height: 27)
                    .applyLiquidGlass(in: Capsule(), interactive: true, fallbackFill: glowingCardFill)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 26)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Content Routing

    @ViewBuilder
    private var detailContent: some View {
        let trimmedQuery = uiState.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            ScrollView(.vertical, showsIndicators: true) {
                searchResultsPane(query: trimmedQuery)
                    .padding(.horizontal, 26)
                    .padding(.top, 4)
                    .padding(.bottom, 26)
            }
        } else if uiState.selectedTab == .apps {
            appsPane
                .padding(.horizontal, 26)
                .padding(.top, 4)
                .padding(.bottom, 26)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                Group {
                    switch uiState.selectedTab {
                    case .screenshots: screenshotsPane
                    case .designerTools: designerToolsPane
                    case .switcher: switcherPane
                    case .appearance: appearancePane
                    case .apps: appsPane
                    case .general: generalPane
                    case .privacy: privacyPane
                    case .about: aboutPane
                    }
                }
                .padding(.horizontal, 26)
                .padding(.top, 4)
                .padding(.bottom, 26)
            }
        }
    }

    // MARK: - Search Results

    private func searchResultsPane(query: String) -> some View {
        let matches = allSearchItems.filter { $0.matches(query) }

        return VStack(alignment: .leading, spacing: 12) {
            sectionHeading("\(matches.count) \(matches.count == 1 ? "result" : "results") for \"\(query)\"")

            if matches.isEmpty {
                glassCard {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(.secondary)
                        Text("No matching settings")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("Try \"haptic\", \"cards\", \"ruler\", \"backup\", or \"about\"")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            } else {
                glassCard {
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
                                        size: 22,
                                        cornerRadius: 5.5,
                                        symbolSize: 11
                                    )

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title)
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundColor(.primary)
                                        if settings.showDetailsInSettings {
                                            Text(item.subtitle)
                                                .font(.system(size: 11.5))
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }
                                    }

                                    Spacer()

                                    Text(item.tab.rawValue)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)

                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(.secondary.opacity(0.6))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 11)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            if index < matches.count - 1 {
                                rowDivider(leading: 50)
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
            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Capture shortcuts")

                glassCard {
                    VStack(spacing: 0) {
                        shortcutRow(
                            title: "Area & window capture",
                            subtitle: "Freeze screen frames, drag a region, or click any window for shadow capture.",
                            targetId: "screenshot",
                            combination: $settings.screenshotKeyCombination,
                            defaultCombo: .defaultScreenshot,
                            onTry: { ScreenshotCoordinator.shared.startAreaCapture() }
                        )

                        rowDivider()

                        shortcutRow(
                            title: "Capture active window",
                            subtitle: "Immediately snapshot the frontmost window with Apple elevation shadow.",
                            targetId: "activeWindow",
                            combination: $settings.activeWindowKeyCombination,
                            defaultCombo: .defaultActiveWindow,
                            onTry: { ScreenshotCoordinator.shared.captureActiveWindow() }
                        )

                        rowDivider()

                        shortcutRow(
                            title: "Screen text recognition (OCR)",
                            subtitle: "Select any region on screen to copy detected text directly to the clipboard.",
                            targetId: "ocr",
                            combination: $settings.ocrKeyCombination,
                            defaultCombo: .defaultOCR,
                            onTry: { ScreenOCRCoordinator.shared.startSelection() }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Workflow")

                glassCard {
                    VStack(spacing: 0) {
                        toggleRow(
                            title: "Auto-open Designer Studio",
                            subtitle: "Launch the annotation and caliper canvas immediately after capturing.",
                            isOn: $settings.autoOpenEditor
                        )

                        rowDivider()

                        toggleRow(
                            title: "Play camera shutter sound",
                            subtitle: "Play audio feedback when a capture completes or copies to clipboard.",
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
            rowLabel(title: title, subtitle: subtitle)

            Spacer(minLength: 8)

            glassPillButton("Try", action: onTry)

            ShortcutRecorderField(
                targetId: targetId,
                keyCombination: combination,
                defaultCombination: defaultCombo
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - 2. Designer Tools Pane

    private var designerToolsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            interactiveCaliperStage

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Measurement & snapping")

                glassCard {
                    VStack(spacing: 0) {
                        toggleRow(
                            title: "Smart distance & edge snapping",
                            subtitle: "Snap horizontal and vertical rulers automatically to buttons, icons, and layout borders.",
                            isOn: $settings.enableSmartDistance
                        )

                        rowDivider()

                        HStack(spacing: 12) {
                            rowLabel(
                                title: "Spacing grid audit",
                                subtitle: "Highlight measurements that fall off the chosen layout rhythm in amber."
                            )
                            Spacer(minLength: 8)
                            CleanSegmentedPicker(
                                selection: $settings.gridAuditUnit,
                                options: [("4 px", 4), ("8 px", 8), ("Off", 1)]
                            )
                            .frame(width: 174)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Canvas shortcuts")

                glassCard {
                    VStack(spacing: 0) {
                        keycapRow(title: "Select & move", subtitle: "Drag objects, handles, and resize bounds", key: "V")
                        rowDivider()
                        keycapRow(title: "Dimension ruler", subtitle: "Horizontal and vertical snap caliper", key: "D")
                        rowDivider()
                        keycapRow(title: "Arrow annotation", subtitle: "Single, double, or pointed callouts", key: "A")
                        rowDivider()
                        keycapRow(title: "Text callout", subtitle: "Plain label, capsule badge, or quote block", key: "T")
                        rowDivider()
                        keycapRow(title: "Rectangle frame", subtitle: "Stroke outline or solid filled container", key: "R")
                        rowDivider()
                        keycapRow(title: "Undo & redo", subtitle: "Step backward or forward through edits", key: "⌘Z / ⌘⇧Z")
                    }
                }
            }
        }
    }

    private var interactiveCaliperStage: some View {
        let gap = uiState.rulerDemoGap
        let auditUnit = settings.gridAuditUnit
        let isAuditEnabled = auditUnit > 1
        let isOffGrid = isAuditEnabled && (gap % auditUnit != 0)
        let caliperColor: Color = isOffGrid
            ? Color(red: 1.0, green: 0.62, blue: 0.04)
            : accentBlue

        return ZStack {
            Color(red: 0.114, green: 0.118, blue: 0.129)

            Canvas { context, size in
                let step: CGFloat = 12
                var x: CGFloat = step
                while x < size.width {
                    var y: CGFloat = step
                    while y < size.height {
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - 0.6, y: y - 0.6, width: 1.2, height: 1.2)),
                            with: .color(.white.opacity(0.08))
                        )
                        y += step
                    }
                    x += step
                }
            }

            VStack(spacing: 10) {
                HStack(spacing: 0) {
                    Text("Save Changes")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accentBlue))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(settings.enableSmartDistance ? caliperColor.opacity(0.85) : Color.clear, lineWidth: 1)
                        )

                    ZStack {
                        if settings.enableSmartDistance {
                            Rectangle().fill(caliperColor).frame(width: CGFloat(gap), height: 1.5)
                            HStack {
                                Rectangle().fill(caliperColor).frame(width: 1.5, height: 14)
                                Spacer()
                                Rectangle().fill(caliperColor).frame(width: 1.5, height: 14)
                            }
                            .frame(width: CGFloat(gap))
                        }
                    }
                    .frame(width: CGFloat(gap), height: 30)

                    Text("Cancel")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 14)
                        .frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.white.opacity(0.11)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(settings.enableSmartDistance ? caliperColor.opacity(0.85) : Color.white.opacity(0.14), lineWidth: 0.8)
                        )
                }

                HStack(spacing: 6) {
                    Text("\(gap) px")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(caliperColor))

                    Text(
                        !settings.enableSmartDistance
                            ? "Edge snapping paused"
                            : (isOffGrid
                                ? "Off \(auditUnit) px grid"
                                : (isAuditEnabled ? "Aligned to \(auditUnit) px grid" : "Grid audit off"))
                    )
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.75))
                }
            }

            VStack {
                Spacer()
                HStack {
                    Text("Interactive caliper preview")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.white.opacity(0.45))
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach([12, 14, 16, 24], id: \.self) { testGap in
                            Button(action: { uiState.rulerDemoGap = testGap }) {
                                Text("\(testGap)")
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundColor(uiState.rulerDemoGap == testGap ? .black : .white.opacity(0.75))
                                    .padding(.horizontal, 7)
                                    .frame(height: 20)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                            .fill(uiState.rulerDemoGap == testGap ? Color.white : Color.white.opacity(0.10))
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .frame(height: 124)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(innerDividerColor, lineWidth: 0.75)
        )
    }

    private func keycapRow(title: String, subtitle: String, key: String) -> some View {
        HStack {
            rowLabel(title: title, subtitle: subtitle)
            Spacer()
            Text(key)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
                .padding(.horizontal, 9)
                .frame(height: 23)
                .applyLiquidGlass(in: RoundedRectangle(cornerRadius: 6, style: .continuous), fallbackFill: Color.primary.opacity(0.06))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 3. Switcher Pane

    private var switcherPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Trigger & release")

                HStack(spacing: 12) {
                    triggerCard(
                        trigger: .commandTab,
                        keys: "⌘ Tab",
                        title: "Command + Tab",
                        subtitle: "Replace macOS app switcher with window-level switching"
                    )

                    triggerCard(
                        trigger: .optionTab,
                        keys: "⌥ Tab",
                        title: "Option + Tab",
                        subtitle: "Run alongside stock macOS Command-Tab"
                    )
                }

                glassCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            rowLabel(
                                title: "After releasing modifier",
                                subtitle: "Immediately raise the selected window or hold the HUD open."
                            )
                            Spacer()
                            CleanSegmentedPicker(
                                selection: $settings.afterRelease,
                                options: [("Focus Window", "Focus"), ("Keep Open", "Hold")]
                            )
                            .frame(width: 196)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        toggleRow(
                            title: "Window status indicators",
                            subtitle: "Show hidden, minimized, or playing indicators on tiles.",
                            isOn: $settings.showWindowBadges
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Scope & visibility")

                glassCard {
                    VStack(spacing: 0) {
                        menuRow(
                            title: "Applications",
                            subtitle: "Show windows from all running apps or only the active app.",
                            selection: $settings.appsFilter,
                            options: [("All apps", "All apps"), ("Active app", "Active app")]
                        )

                        rowDivider()

                        menuRow(
                            title: "macOS Spaces",
                            subtitle: "Restrict window list to the current desktop Space.",
                            selection: $settings.spacesFilter,
                            options: [("All Spaces", "All Spaces"), ("Current Space", "Current Space")]
                        )

                        rowDivider()

                        toggleRow(
                            title: "Include minimized windows",
                            subtitle: "Keep Dock-minimized windows selectable in the switcher.",
                            isOn: $settings.showMinimizedWindows
                        )

                        rowDivider()

                        toggleRow(
                            title: "Include hidden applications",
                            subtitle: "List windows belonging to applications hidden via ⌘H.",
                            isOn: $settings.showHiddenWindows
                        )

                        rowDivider()

                        toggleRow(
                            title: "Include fullscreen spaces",
                            subtitle: "Show windows running inside dedicated fullscreen Spaces.",
                            isOn: $settings.showFullscreenWindows
                        )

                        rowDivider()

                        toggleRow(
                            title: "Show apps without open windows",
                            subtitle: "Include running apps that currently have zero windows open.",
                            isOn: $settings.showAppsWithNoWindows
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("While switcher is open")

                glassCard {
                    HStack(spacing: 8) {
                        hotkeyChip(keys: "↑ ↓ ← →", label: "Navigate")
                        hotkeyChip(keys: "Return", label: "Focus")
                        hotkeyChip(keys: "W", label: "Close")
                        hotkeyChip(keys: "Q", label: "Quit")
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
            settings.triggerSwitchFeedback(isCommit: false)
        }) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(keys)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(isSelected ? .white : .primary)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(isSelected ? accent : Color.primary.opacity(0.08)))

                    Spacer()

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14.5))
                            .foregroundColor(accent)
                    }
                }

                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)

                if settings.showDetailsInSettings {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .applyLiquidGlass(
                in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                interactive: true,
                fallbackFill: glowingCardFill
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? accent : innerDividerColor, lineWidth: isSelected ? 1.5 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                .applyLiquidGlass(in: RoundedRectangle(cornerRadius: 5.5, style: .continuous), fallbackFill: Color.primary.opacity(0.07))
            Text(label)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 4. Appearance Pane

    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            liveSwitcherDesktopStage

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("HUD layout style")

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    styleSelectorTile(style: .thumbnails, title: "Thumbnails", symbol: "rectangle.grid.2x2")
                    styleSelectorTile(style: .icons, title: "App Icons", symbol: "square.grid.3x1.below.line.grid.1x2")
                    styleSelectorTile(style: .titles, title: "Window Titles", symbol: "list.bullet.indent")
                    styleSelectorTile(style: .cards, title: "Compact Cards", symbol: "rectangle.split.2x2")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Sizing & placement")

                glassCard {
                    VStack(spacing: 0) {
                        HStack {
                            rowLabel(title: "Tile size", subtitle: "Scale window previews, icon strips, and card tiles.")
                            Spacer()
                            CleanSegmentedPicker(
                                selection: $settings.cardSize,
                                options: [("Small", CardSize.small), ("Medium", CardSize.medium), ("Large", CardSize.large)]
                            )
                            .frame(width: 224)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        HStack {
                            rowLabel(title: "Color theme", subtitle: "Match macOS System appearance or lock Light / Dark glass.")
                            Spacer()
                            CleanSegmentedPicker(
                                selection: $settings.themeMode,
                                options: [("System", ThemeMode.system), ("Light", ThemeMode.light), ("Dark", ThemeMode.dark)]
                            )
                            .frame(width: 224)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        HStack {
                            rowLabel(title: "Display placement", subtitle: "Select which monitor presents the switcher HUD.")
                            Spacer()
                            Picker("", selection: $settings.screenPlacement) {
                                ForEach(ScreenPlacement.allCases) { placement in
                                    Text(placement.rawValue).tag(placement)
                                }
                            }
                            .frame(width: 190)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        toggleRow(
                            title: "Smooth animations",
                            subtitle: "Animate focus rings and dismissal transitions.",
                            isOn: $settings.animationsEnabled
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Optics & accent")

                glassCard {
                    VStack(spacing: 0) {
                        HStack {
                            rowLabel(title: "Accent color", subtitle: "Selection highlight ring and active row fill.")
                            Spacer()
                            HStack(spacing: 7) {
                                accentDot(hex: "#007AFF")
                                accentDot(hex: "#5E5CE6")
                                accentDot(hex: "#BF5AF2")
                                accentDot(hex: "#FF375F")
                                accentDot(hex: "#30D158")
                                accentDot(hex: "#FF9F0A")

                                TextField("#007AFF", text: $settings.customAccentColorHex)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11, design: .monospaced))
                                    .frame(width: 70)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        HStack {
                            rowLabel(title: "Corner curvature", subtitle: "Outer squircle radius of the HUD shell (\(Int(settings.hudCornerRadius)) pt)")
                            Spacer()
                            Slider(value: $settings.hudCornerRadius, in: 16...32, step: 2)
                                .frame(width: 184)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        HStack {
                            rowLabel(title: "Specular border", subtitle: "Rim line thickness around the HUD surface (\(String(format: "%.1f", settings.borderWidth)) pt)")
                            Spacer()
                            Slider(value: $settings.borderWidth, in: 0.5...3.0, step: 0.5)
                                .frame(width: 184)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        HStack {
                            rowLabel(title: "Shadow elevation", subtitle: "Adjust HUD depth and shadow spread above open windows.")
                            Spacer()
                            CleanSegmentedPicker(
                                selection: $settings.shadowDepth,
                                options: [("Subtle", "Subtle Depth"), ("Balanced", "Apple HIG Balanced"), ("Floating", "Floating Deep")]
                            )
                            .frame(width: 228)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                }
            }
        }
    }

    private var liveSwitcherDesktopStage: some View {
        let resolvedDark: Bool = {
            switch settings.themeMode {
            case .dark: return true
            case .light: return false
            case .system: return colorScheme == .dark
            }
        }()

        let accent = settings.accentColor
        let items: [(app: String, title: String, bundleId: String)] = [
            ("Terminal", "zsh — build", "com.apple.Terminal"),
            ("Safari", "Apple Design", "com.apple.Safari"),
            ("Mail", "Release Notes", "com.apple.mail"),
            ("Notes", "Architecture", "com.apple.Notes")
        ]
        let hudBg = resolvedDark ? Color(white: 0.14).opacity(0.82) : Color(white: 0.96).opacity(0.84)
        let ink = resolvedDark ? Color.white : Color(white: 0.10)
        let subInk = resolvedDark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
        let shadowRadius: CGFloat = settings.shadowDepth == "Floating Deep" ? 18 : (settings.shadowDepth == "Subtle Depth" ? 4 : 11)
        let radius = CGFloat(min(settings.hudCornerRadius, 24)) * 0.85

        return ZStack(alignment: .top) {
            LinearGradient(
                colors: resolvedDark
                    ? [Color(red: 0.14, green: 0.17, blue: 0.24), Color(red: 0.09, green: 0.10, blue: 0.15)]
                    : [Color(red: 0.78, green: 0.84, blue: 0.92), Color(red: 0.91, green: 0.89, blue: 0.87)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            HStack(spacing: 10) {
                Image(systemName: "applelogo")
                    .font(.system(size: 8))
                Text("WindowSwitcher")
                    .font(.system(size: 8.5, weight: .semibold))
                Spacer()
                Text("Preview")
                    .font(.system(size: 8, weight: .medium))
            }
            .foregroundColor(ink.opacity(0.8))
            .padding(.horizontal, 12)
            .frame(height: 18)
            .background(resolvedDark ? Color.black.opacity(0.28) : Color.white.opacity(0.42))

            VStack {
                Spacer(minLength: 20)

                Group {
                    switch settings.switcherStyle {
                    case .icons:
                        HStack(spacing: 10) {
                            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                                let active = uiState.previewSelectedIndex == idx
                                Button(action: {
                                    uiState.previewSelectedIndex = idx
                                    settings.triggerSwitchFeedback(isCommit: false)
                                }) {
                                    VStack(spacing: 4) {
                                        NativeAppIconView(bundleId: item.bundleId, size: settings.cardSize == .small ? 30 : (settings.cardSize == .large ? 40 : 34))
                                            .padding(4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .fill(active ? (resolvedDark ? Color.white.opacity(0.18) : Color.black.opacity(0.10)) : Color.clear)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .stroke(active ? accent.opacity(0.85) : Color.clear, lineWidth: 1.5)
                                            )

                                        Text(item.app)
                                            .font(.system(size: 9.5, weight: active ? .semibold : .regular))
                                            .foregroundColor(active ? ink : subInk)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .applyLiquidGlass(in: Capsule(), interactive: true, fallbackFill: hudBg)
                        .overlay(Capsule().stroke(ink.opacity(0.12), lineWidth: CGFloat(settings.borderWidth)))

                    case .titles:
                        VStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                                let active = uiState.previewSelectedIndex == idx
                                Button(action: {
                                    uiState.previewSelectedIndex = idx
                                    settings.triggerSwitchFeedback(isCommit: false)
                                }) {
                                    HStack(spacing: 8) {
                                        Text(item.app)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(active ? .white.opacity(0.92) : subInk)
                                            .frame(width: 56, alignment: .trailing)

                                        NativeAppIconView(bundleId: item.bundleId, size: 15)

                                        Text(item.title)
                                            .font(.system(size: 10.5, weight: active ? .semibold : .regular))
                                            .foregroundColor(active ? .white : ink)
                                            .lineLimit(1)

                                        Spacer()

                                        if settings.showWindowBadges && idx == 0 {
                                            Image(systemName: "eye.slash")
                                                .font(.system(size: 8.5))
                                                .foregroundColor(active ? .white.opacity(0.85) : subInk)
                                        }
                                    }
                                    .padding(.horizontal, 10)
                                    .frame(width: 288, height: 22)
                                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(active ? accent : Color.clear))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(6)
                        .applyLiquidGlass(in: RoundedRectangle(cornerRadius: radius * 0.7, style: .continuous), fallbackFill: hudBg)
                        .overlay(RoundedRectangle(cornerRadius: radius * 0.7, style: .continuous).stroke(ink.opacity(0.12), lineWidth: CGFloat(settings.borderWidth)))

                    case .cards:
                        LazyVGrid(columns: [GridItem(.fixed(144), spacing: 7), GridItem(.fixed(144), spacing: 7)], spacing: 7) {
                            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                                let active = uiState.previewSelectedIndex == idx
                                Button(action: {
                                    uiState.previewSelectedIndex = idx
                                    settings.triggerSwitchFeedback(isCommit: false)
                                }) {
                                    HStack(spacing: 7) {
                                        NativeAppIconView(bundleId: item.bundleId, size: 22)
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(item.title)
                                                .font(.system(size: 10, weight: .semibold))
                                                .foregroundColor(active && resolvedDark ? .white : ink)
                                                .lineLimit(1)
                                            Text(item.app)
                                                .font(.system(size: 8.5))
                                                .foregroundColor(subInk)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 8)
                                    .frame(height: 34)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(active ? accent.opacity(resolvedDark ? 0.28 : 0.14) : (resolvedDark ? Color.white.opacity(0.06) : Color.black.opacity(0.04)))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(active ? accent : ink.opacity(0.08), lineWidth: active ? 1.5 : 0.6)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .fixedSize()
                        .padding(8)
                        .applyLiquidGlass(in: RoundedRectangle(cornerRadius: radius * 0.72, style: .continuous), fallbackFill: hudBg)
                        .overlay(RoundedRectangle(cornerRadius: radius * 0.72, style: .continuous).stroke(ink.opacity(0.12), lineWidth: CGFloat(settings.borderWidth)))

                    case .thumbnails:
                        HStack(spacing: 8) {
                            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                                let active = uiState.previewSelectedIndex == idx
                                Button(action: {
                                    uiState.previewSelectedIndex = idx
                                    settings.triggerSwitchFeedback(isCommit: false)
                                }) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack(spacing: 4) {
                                            NativeAppIconView(bundleId: item.bundleId, size: 13)
                                            Text(item.app)
                                                .font(.system(size: 9, weight: .semibold))
                                                .foregroundColor(ink)
                                                .lineLimit(1)
                                        }
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(resolvedDark ? Color.white.opacity(0.09) : Color.black.opacity(0.06))
                                            .overlay(
                                                VStack(alignment: .leading, spacing: 3) {
                                                    RoundedRectangle(cornerRadius: 1.5).fill(accent.opacity(0.35)).frame(width: 34, height: 4)
                                                    RoundedRectangle(cornerRadius: 1.5).fill(ink.opacity(0.14)).frame(width: 52, height: 3)
                                                    RoundedRectangle(cornerRadius: 1.5).fill(ink.opacity(0.10)).frame(width: 40, height: 3)
                                                }
                                                .padding(6),
                                                alignment: .topLeading
                                            )
                                    }
                                    .padding(6)
                                    .frame(width: settings.cardSize == .small ? 76 : (settings.cardSize == .large ? 92 : 84), height: 64)
                                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(resolvedDark ? Color.white.opacity(0.06) : Color.white.opacity(0.75)))
                                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(active ? accent : ink.opacity(0.10), lineWidth: active ? 1.8 : 0.7))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(10)
                        .applyLiquidGlass(in: RoundedRectangle(cornerRadius: radius, style: .continuous), fallbackFill: hudBg)
                        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(ink.opacity(0.12), lineWidth: CGFloat(settings.borderWidth)))
                    }
                }
                .shadow(color: Color.black.opacity(resolvedDark ? 0.45 : 0.16), radius: shadowRadius, y: 4)

                Spacer(minLength: 16)
            }
        }
        .frame(height: 152)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(innerDividerColor, lineWidth: 0.75)
        )
    }

    private func styleSelectorTile(style: SwitcherStyle, title: String, symbol: String) -> some View {
        let isSelected = settings.switcherStyle == style
        let isHovered = uiState.hoveredStyle == style && !isSelected
        let accent = settings.accentColor

        return Button(action: {
            settings.switcherStyle = style
            settings.triggerSwitchFeedback(isCommit: false)
        }) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isSelected ? accent : .secondary)

                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .applyLiquidGlass(
                in: RoundedRectangle(cornerRadius: 11, style: .continuous),
                interactive: true,
                fallbackFill: glowingCardFill
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent : (isHovered ? Color.primary.opacity(0.18) : innerDividerColor),
                        lineWidth: isSelected ? 1.6 : 0.75
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            uiState.hoveredStyle = hovering ? style : (uiState.hoveredStyle == style ? nil : uiState.hoveredStyle)
        }
    }

    private func accentDot(hex: String) -> some View {
        let color = Color(hex: hex) ?? .blue
        let isSelected = settings.customAccentColorHex.uppercased() == hex.uppercased()

        return Button(action: { settings.customAccentColorHex = hex }) {
            ZStack {
                Circle().fill(color).frame(width: 16, height: 16)
                if isSelected {
                    Circle().strokeBorder(Color.white, lineWidth: 2).frame(width: 12, height: 12)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - 5. Apps & Rules Pane

    private var appsPane: some View {
        glassCard {
            HStack(spacing: 0) {
                // Left Application List Column
                VStack(spacing: 0) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 2) {
                            ForEach(settings.exceptionsList) { app in
                                let isSelected = uiState.selectedExceptionId == app.bundleId
                                Button(action: { uiState.selectedExceptionId = app.bundleId }) {
                                    HStack(spacing: 9) {
                                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                            .fill(isSelected ? Color.primary.opacity(0.65) : Color.clear)
                                            .frame(width: 2.5, height: 14)

                                        NativeAppIconView(bundleId: app.bundleId, size: 22)

                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(app.name)
                                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
                                                .foregroundColor(.primary)
                                                .lineLimit(1)

                                            if settings.showDetailsInSettings {
                                                Text(app.ignoreShortcuts == "When in focus" ? "Pass-through" : "Switcher Rule")
                                                    .font(.system(size: 10))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(isSelected ? Color.primary.opacity(colorScheme == .dark ? 0.11 : 0.065) : Color.clear)
                                    )
                                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(8)
                    }

                    rowDivider(leading: 0)

                    HStack(spacing: 0) {
                        Button(action: chooseApplicationFromDisk) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 30, height: 26)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        Rectangle().fill(innerDividerColor).frame(width: 1, height: 14)

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
                .frame(width: 204)
                .frame(maxHeight: .infinity)

                Rectangle()
                    .fill(innerDividerColor)
                    .frame(width: 1)

                // Right Integrated Rule Inspector Column
                if let index = settings.exceptionsList.firstIndex(where: { $0.bundleId == uiState.selectedExceptionId }) {
                    let selectedApp = settings.exceptionsList[index]

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            NativeAppIconView(bundleId: selectedApp.bundleId, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(selectedApp.name)
                                    .font(.system(size: 14.5, weight: .semibold))
                                Text(selectedApp.bundleId)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(16)

                        rowDivider(leading: 0)

                        HStack {
                            rowLabel(title: "Global shortcuts", subtitle: "Bypass Window Switcher triggers when this app is frontmost.")
                            Spacer()
                            Picker("", selection: Binding(
                                get: { settings.exceptionsList[index].ignoreShortcuts },
                                set: { settings.exceptionsList[index].ignoreShortcuts = $0 }
                            )) {
                                Text("Pass-through").tag("When in focus")
                                Text("Active normally").tag("Never")
                            }
                            .frame(width: 168)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        rowDivider(leading: 16)

                        HStack {
                            rowLabel(title: "HUD visibility", subtitle: "Control whether this application appears inside the switcher.")
                            Spacer()
                            Picker("", selection: Binding(
                                get: { settings.exceptionsList[index].hideWindows },
                                set: { settings.exceptionsList[index].hideWindows = $0 }
                            )) {
                                Text("Hide when empty").tag("When no open window")
                                Text("Always hide").tag("Always")
                                Text("Always show").tag("Never")
                            }
                            .frame(width: 168)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 26, weight: .light))
                            .foregroundColor(.secondary)
                        Text("No application selected")
                            .font(.system(size: 13.5, weight: .semibold))
                        Text("Add an application to configure per-app pass-through shortcuts or visibility rules.")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 260)
                        glassPillButton("Add App…", action: chooseApplicationFromDisk)
                            .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(20)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var canRemoveSelected: Bool {
        settings.exceptionsList.contains(where: { $0.bundleId == uiState.selectedExceptionId })
    }

    private func removeSelectedException() {
        settings.exceptionsList.removeAll(where: { $0.bundleId == uiState.selectedExceptionId })
        uiState.selectedExceptionId = settings.exceptionsList.first?.bundleId ?? ""
    }

    // MARK: - 6. General Pane

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Startup")

                glassCard {
                    VStack(spacing: 0) {
                        toggleRow(
                            title: "Launch at login",
                            subtitle: "Open Window Switcher automatically when you log in.",
                            isOn: $settings.startAtLogin
                        )

                        rowDivider()

                        toggleRow(
                            title: "Show menu bar icon",
                            subtitle: "Display the icon in the menu bar. Reopen Preferences anytime from Spotlight.",
                            isOn: $settings.showMenubarIcon
                        )

                        rowDivider()

                        toggleRow(
                            title: "Background thumbnail cache",
                            subtitle: "Pre-capture open window previews so the HUD appears instantaneously.",
                            isOn: $settings.captureInBackground
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Feedback")

                glassCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            rowLabel(
                                title: "Haptic feedback on switch",
                                subtitle: "A subtle tap when cycling or selecting a window. Force Touch trackpads."
                            )
                            Spacer(minLength: 12)
                            Toggle("", isOn: Binding(
                                get: { settings.hapticFeedbackOnSwitch },
                                set: { newValue in
                                    settings.hapticFeedbackOnSwitch = newValue
                                    if newValue {
                                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                    }
                                }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        HStack(spacing: 12) {
                            rowLabel(
                                title: "Sound on switch",
                                subtitle: "Play a crisp system sound when stepping between windows."
                            )
                            Spacer()
                            Picker("", selection: Binding(
                                get: { settings.soundOnSwitch },
                                set: { newValue in
                                    settings.soundOnSwitch = newValue
                                    if newValue != "Off", let sound = NSSound(named: NSSound.Name(newValue)) {
                                        sound.volume = 0.25
                                        sound.play()
                                    }
                                }
                            )) {
                                Text("Off").tag("Off")
                                Text("Tink").tag("Tink")
                                Text("Pop").tag("Pop")
                                Text("Morse").tag("Morse")
                            }
                            .frame(width: 112)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Updates")

                glassCard {
                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            rowLabel(title: "Check for updates", subtitle: updateStatusLine)
                            Spacer()
                            updateActionButton
                            Picker("", selection: $settings.updatePolicy) {
                                Text("Automatic").tag("Check for updates periodically")
                                Text("Manual").tag("Check manually")
                            }
                            .frame(width: 116)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        toggleRow(
                            title: "Include beta releases",
                            subtitle: "Receive pre-release builds from GitHub Releases when available.",
                            isOn: $settings.includeBetaReleases
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Backup")

                glassCard {
                    VStack(spacing: 0) {
                        HStack {
                            rowLabel(
                                title: "Export settings",
                                subtitle: "Save all your settings to a JSON file you can back up or move to another Mac."
                            )
                            Spacer()
                            glassPillButton("Export…", action: exportSettingsToDisk)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        HStack {
                            rowLabel(
                                title: "Import settings",
                                subtitle: "Replace your current configuration from a previously exported file."
                            )
                            Spacer()
                            glassPillButton("Import…", action: importSettingsFromDisk)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)

                        rowDivider()

                        HStack {
                            rowLabel(
                                title: "Reset all preferences",
                                subtitle: "Restore every shortcut, style, and rule back to defaults."
                            )
                            Spacer()
                            glassPillButton("Reset…") {
                                settings.resetToDefaults()
                                uiState.flashStatus("Preferences restored to factory defaults")
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                    }
                }

                if let msg = uiState.statusMessage {
                    Text(msg)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundColor(accentBlue)
                        .padding(.leading, 4)
                }
            }
        }
    }

    private var updateStatusLine: String {
        switch updater.status {
        case .idle:
            return "Current version v\(updater.currentVersion) — ready to check GitHub Releases."
        case .checking:
            return "Checking GitHub Releases…"
        case .upToDate(let ver):
            return "Up to date on v\(ver)."
        case .available(let ver, _, _, _):
            return "Version \(ver) is available to install."
        case .downloading(let progress):
            return "Downloading update (\(Int(progress * 100))%)…"
        case .installing:
            return "Installing update into /Applications…"
        case .readyToRelaunch:
            return "Update installed. Relaunch Window Switcher to complete."
        case .error(let msg):
            return "Unable to check: \(msg)"
        }
    }

    @ViewBuilder
    private var updateActionButton: some View {
        switch updater.status {
        case .checking, .downloading, .installing:
            ProgressView().controlSize(.small)
        case .available(_, _, let downloadUrl, _):
            glassPillButton("Install") { updater.downloadAndInstall(from: downloadUrl) }
        case .readyToRelaunch:
            glassPillButton("Relaunch") { updater.relaunch() }
        default:
            glassPillButton("Check Now") { updater.checkForUpdates(userInitiated: true) }
        }
    }

    // MARK: - 7. Privacy Pane

    private var privacyPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("System permissions")

                glassCard {
                    VStack(spacing: 0) {
                        permissionRow(
                            title: "Accessibility",
                            subtitle: "Intercept Option/Command-Tab shortcuts and focus windows across spaces.",
                            granted: permissions.hasAccessibility,
                            action: { permissions.requestAccessibility() }
                        )

                        rowDivider()

                        permissionRow(
                            title: "Screen Recording",
                            subtitle: "Capture frozen frames, live window thumbnails, and Designer Studio measurements.",
                            granted: permissions.hasScreenRecording,
                            action: { permissions.requestScreenRecording() }
                        )
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                sectionHeading("Data & local processing")

                glassCard {
                    HStack {
                        rowLabel(
                            title: "On-device capture & OCR",
                            subtitle: "All screenshots, pixel buffers, and text recognition run locally using Apple Vision and ScreenCaptureKit. Nothing leaves your Mac."
                        )
                        Spacer()
                        Text("Local Only")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.16, green: 0.72, blue: 0.30))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                            .applyLiquidGlass(
                                in: Capsule(),
                                tint: Color(red: 0.188, green: 0.820, blue: 0.345).opacity(0.16),
                                fallbackFill: Color(red: 0.188, green: 0.820, blue: 0.345).opacity(0.14)
                            )
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func permissionRow(title: String, subtitle: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            rowLabel(title: title, subtitle: subtitle)
            Spacer()
            if granted {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                    Text("Granted")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(Color(red: 0.16, green: 0.72, blue: 0.30))
            } else {
                glassPillButton("Grant Access", action: action)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - 8. About Pane (Liquid Glass Showcase Inspired by Reference)

    private var aboutPane: some View {
        let buildString = "v\(updater.currentVersion) · Apple Silicon (arm64)"

        return VStack(spacing: 0) {
            Spacer().frame(height: 22)

            // Hero Header Block
            HStack(alignment: .center, spacing: 26) {
                AppBrandingIcon(size: 84, cornerRadius: 20)
                    .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.10), radius: 8, y: 3)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Window Switcher")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.primary)

                    Text("Faster window switching & frozen-frame studio for macOS")
                        .font(.system(size: 13.5))
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Button(action: {
                            updater.checkForUpdates(userInitiated: true)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 11.5, weight: .semibold))
                                    .foregroundColor(.secondary)
                                Text(updater.isChecking ? "Checking…" : "Check for Updates")
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .applyLiquidGlass(
                                in: Capsule(),
                                interactive: true,
                                fallbackFill: glowingCardFill
                            )
                        }
                        .buttonStyle(.plain)

                        if case .upToDate(let v) = updater.status {
                            Text("Up to date (v\(v))")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundColor(Color(red: 0.16, green: 0.72, blue: 0.30))
                        }
                    }
                    .padding(.top, 4)

                    HStack(spacing: 8) {
                        Text(buildString)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundColor(.secondary)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString("Window Switcher \(buildString)", forType: .string)
                            uiState.flashCopiedBuild()
                        }) {
                            Image(systemName: uiState.copiedBuildInfo ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 11))
                                .foregroundColor(uiState.copiedBuildInfo ? accentBlue : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Copy build info")
                    }
                    .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Spacer().frame(height: 30)

            // 3 Luminous Liquid Glass Bento Action Cards
            HStack(spacing: 14) {
                aboutBentoCard(
                    id: "source",
                    symbol: "chevron.left.forwardslash.chevron.right",
                    title: "Source Code",
                    url: "https://github.com/TheLegend96/WindowSwitcher"
                )
                aboutBentoCard(
                    id: "issue",
                    symbol: "exclamationmark.bubble.fill",
                    title: "Report an Issue",
                    url: "https://github.com/TheLegend96/WindowSwitcher/issues"
                )
                aboutBentoCard(
                    id: "releases",
                    symbol: "shippingbox.fill",
                    title: "Releases",
                    url: "https://github.com/TheLegend96/WindowSwitcher/releases"
                )
            }

            Spacer().frame(height: 28)

            Text("© 2026 Window Switcher")
                .font(.system(size: 11.5))
                .foregroundColor(.secondary.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    private func aboutBentoCard(id: String, symbol: String, title: String, url: String) -> some View {
        let isHovered = uiState.hoveredBentoId == id

        return Button(action: {
            if let target = URL(string: url) {
                NSWorkspace.shared.open(target)
            }
        }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.055))
                        .frame(width: 30, height: 30)

                    Image(systemName: symbol)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 94)
            .applyLiquidGlass(
                in: RoundedRectangle(cornerRadius: 14, style: .continuous),
                interactive: true,
                fallbackFill: glowingCardFill
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(cardBorderGradient, lineWidth: isHovered ? 1.0 : 0.75)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            uiState.hoveredBentoId = hovering ? id : (uiState.hoveredBentoId == id ? nil : uiState.hoveredBentoId)
        }
    }

    // MARK: - Shared Liquid Glass Primitives

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.primary)
            .padding(.leading, 4)
    }

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(glowingCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(innerDividerColor, lineWidth: 0.75)
            )
    }

    private func rowDivider(leading: CGFloat = 16) -> some View {
        Rectangle()
            .fill(innerDividerColor)
            .frame(height: 1)
            .padding(.leading, leading)
    }

    private func rowLabel(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)

            if settings.showDetailsInSettings {
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            rowLabel(title: title, subtitle: subtitle)
            Spacer(minLength: 12)
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func menuRow(title: String, subtitle: String, selection: Binding<String>, options: [(label: String, tag: String)]) -> some View {
        HStack(spacing: 12) {
            rowLabel(title: title, subtitle: subtitle)
            Spacer()
            Picker("", selection: selection) {
                ForEach(options, id: \.tag) { option in
                    Text(option.label).tag(option.tag)
                }
            }
            .frame(width: 150)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private func glassPillButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .frame(height: 25)
                .applyLiquidGlass(
                    in: Capsule(),
                    interactive: true,
                    fallbackFill: glowingCardFill
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Disk Panels (Apps + Export/Import)

    private func exportSettingsToDisk() {
        guard let data = settings.exportSettingsJSON() else {
            uiState.flashStatus("Unable to serialize preferences")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "WindowSwitcher-Settings.json"
        panel.prompt = "Export"
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try data.write(to: url)
                uiState.flashStatus("Exported settings to \(url.lastPathComponent)")
            } catch {
                uiState.flashStatus("Export failed: \(error.localizedDescription)")
            }
        }
    }

    private func importSettingsFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.prompt = "Import"
        if panel.runModal() == .OK, let url = panel.url,
           let data = try? Data(contentsOf: url),
           settings.importSettingsJSON(data) {
            uiState.flashStatus("Imported settings from \(url.lastPathComponent)")
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

// MARK: - macOS Squircle Icon Badge

private struct SquircleBadge: View {
    let symbol: String
    let color: Color
    var size: CGFloat = 20
    var cornerRadius: CGFloat = 5.5
    var symbolSize: CGFloat = 10.5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.92), color],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6)

            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.08), radius: 0.8, y: 0.4)
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

                    Button(action: { keyCombination = .empty }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10.5))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    .help("Clear shortcut")
                }
            }
            .padding(.horizontal, 8)
            .frame(width: 96, height: 25)
            .applyLiquidGlass(
                in: Capsule(),
                tint: isRecordingThis ? Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.18) : nil,
                interactive: true,
                fallbackFill: Color.primary.opacity(0.05)
            )
            .overlay(
                Capsule()
                    .stroke(
                        isRecordingThis
                            ? Color(red: 0.039, green: 0.518, blue: 1.0).opacity(0.85)
                            : Color.clear,
                        lineWidth: 1.2
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

// MARK: - Precision Non-Overflowing Segmented Control

private struct CleanSegmentedPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(String, Value)]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = selection == option.1
                Button(action: {
                    withAnimation(.easeOut(duration: 0.14)) {
                        selection = option.1
                    }
                }) {
                    Text(option.0)
                        .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(isSelected ? .primary : .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: 23)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(
                                    isSelected
                                        ? (colorScheme == .dark ? Color.white.opacity(0.18) : Color.white)
                                        : Color.clear
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.primary.opacity(0.08) : Color.clear,
                                    lineWidth: 0.5
                                )
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2.5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(colorScheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
