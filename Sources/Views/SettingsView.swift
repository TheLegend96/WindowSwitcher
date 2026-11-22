import SwiftUI
import AppKit

public enum SettingsTab: String, CaseIterable, Identifiable {
    case appearance = "Appearance"
    case controls = "Controls"
    case general = "General"
    case exceptions = "Exceptions"
    case canvas = "Open Canvas"

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .appearance: return "paintbrush.fill"
        case .controls: return "command"
        case .general: return "gearshape.fill"
        case .exceptions: return "hand.raised.fill"
        case .canvas: return "slider.horizontal.3"
        }
    }
}

public final class SettingsUIState: ObservableObject {
    public static let shared = SettingsUIState()

    @Published public var selectedTab: SettingsTab = .appearance
    @Published public var searchQuery: String = ""

    // Controls sub-tab & selection
    @Published public var selectedShortcutItem: Int = 0
    @Published public var controlsSubTab: String = "Filtering"
    @Published public var showShortcutsSheet: Bool = false
    @Published public var showAnimationsSheet: Bool = false

    // Exceptions selection
    @Published public var selectedExceptionId: String = "com.apple.finder"
    @Published public var showAddExceptionSheet: Bool = false
    @Published public var newAppName: String = ""
    @Published public var newBundleId: String = ""
}

public struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    @ObservedObject var permissions = PermissionsManager.shared
    @ObservedObject private var uiState = SettingsUIState.shared

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // MARK: - Left Sidebar Navigation
            sidebarView
                .frame(width: 215)
                .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // MARK: - Content Pane (Direct Hit Testing & No Nested Scroll Gesture Conflicts)
            Group {
                switch uiState.selectedTab {
                case .appearance:
                    ScrollView(.vertical, showsIndicators: true) {
                        appearancePane
                            .padding(24)
                    }
                case .controls:
                    controlsPane
                        .padding(24)
                case .general:
                    ScrollView(.vertical, showsIndicators: true) {
                        generalPane
                            .padding(24)
                    }
                case .exceptions:
                    exceptionsPane
                        .padding(24)
                case .canvas:
                    ScrollView(.vertical, showsIndicators: true) {
                        canvasPane
                            .padding(24)
                    }
                }
            }
            .frame(minWidth: 605, maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .frame(width: 820, height: 600)
        .sheet(isPresented: $uiState.showShortcutsSheet) {
            shortcutsCheatsheetModal
        }
        .sheet(isPresented: $uiState.showAnimationsSheet) {
            animationsModal
        }
        .sheet(isPresented: $uiState.showAddExceptionSheet) {
            addExceptionModal
        }
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
            // App Branding Header (with Cobalt Azure App Icon)
            HStack(spacing: 10) {
                AppBrandingIcon(size: 34, cornerRadius: 8)

                VStack(alignment: .leading, spacing: 2) {
                    Text("WindowSwitcher")
                        .font(.system(size: 14, weight: .bold))
                    Text("v\(UpdateManager.shared.currentVersion) (Apple Silicon)")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 12)

            // Search Bar
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                TextField("Search", text: $uiState.searchQuery)
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
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
            )
            .padding(.horizontal, 14)
            .padding(.bottom, 14)

            // Navigation Tab Items
            VStack(spacing: 3) {
                sidebarButton(tab: .appearance)
                sidebarButton(tab: .controls)
                sidebarButton(tab: .general)
                sidebarButton(tab: .exceptions)
                sidebarButton(tab: .canvas)
            }
            .padding(.horizontal, 10)

            Spacer()

            Divider()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)

            // Quit Button
            Button(action: { AppDelegate.shared?.quitApp() }) {
                HStack(spacing: 8) {
                    Image(systemName: "power")
                        .font(.system(size: 12))
                    Text("Quit WindowSwitcher")
                        .font(.system(size: 12))
                    Spacer()
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)
        }
    }

    private func sidebarButton(tab: SettingsTab) -> some View {
        let isSelected = uiState.selectedTab == tab
        return Button(action: { uiState.selectedTab = tab }) {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .font(.system(size: 13.5))
                    .frame(width: 18)
                    .foregroundColor(isSelected ? .white : .primary)
                Text(tab.rawValue)
                    .font(.system(size: 12.5, weight: isSelected ? .semibold : .regular))
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

    // MARK: - 2. Appearance Pane (Matches Screenshot 1)
    private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 3) {
                Text("Appearance")
                    .font(.system(size: 20, weight: .bold))
                Text("Switch between 3 different styles. You can customize them.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // 3 Style Cards (Thumbnails, App Icons, Titles)
            HStack(spacing: 12) {
                // Style 1: Thumbnails
                appearanceCard(
                    style: .thumbnails,
                    label: "Thumbnails",
                    badge: nil
                ) {
                    // Realistic miniature thumbnails preview box
                    ZStack {
                        miniDesktopBackground
                        HStack(spacing: 8) {
                            miniWindowThumbnail(title: "Japan itinerary", hasImage: true)
                            miniWindowThumbnail(title: "Weekend recipes", hasImage: false)
                        }
                        .padding(.horizontal, 10)
                    }
                }

                // Style 2: App Icons
                appearanceCard(
                    style: .icons,
                    label: "App Icons",
                    badge: "Pro"
                ) {
                    // Realistic miniature icons preview box
                    ZStack {
                        miniDesktopBackground
                        VStack(spacing: 6) {
                            HStack(spacing: 12) {
                                miniAppIconView(symbol: "safari.fill", color: .blue)
                                miniAppIconView(symbol: "note.text", color: .yellow)
                                miniAppIconView(symbol: "list.bullet.rectangle.portrait", color: .orange)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(Color.white.opacity(0.12))
                            )

                            Text("Japan trip")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.black.opacity(0.4)))
                        }
                    }
                }

                // Style 3: Titles
                appearanceCard(
                    style: .titles,
                    label: "Titles",
                    badge: "Pro"
                ) {
                    // Realistic miniature titles list preview box
                    ZStack {
                        miniDesktopBackground
                        VStack(alignment: .leading, spacing: 3) {
                            miniTitleRow(text: "Japan itinerary", isSelected: false)
                            miniTitleRow(text: "Weekend recipes", isSelected: true)
                            miniTitleRow(text: "Trip checklist", isSelected: false)
                        }
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.black.opacity(0.4))
                        )
                        .padding(.horizontal, 12)
                    }
                }
            }

            Divider()

            // Controls Rows (Size, Theme, After keys released, Preview selected window)
            VStack(spacing: 14) {
                // Row 1: Size
                HStack {
                    Text("Size")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.cardSize) {
                        Text("◐ Small").tag(CardSize.small)
                        Text("◑ Medium").tag(CardSize.medium)
                        Text("◕ Large").tag(CardSize.large)
                        Text("✦ Auto").tag(CardSize.auto)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                // Row 2: Theme
                HStack {
                    Text("Theme")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.themeMode) {
                        Text("☀️ Light").tag(ThemeMode.light)
                        Text("🌙 Dark").tag(ThemeMode.dark)
                        Text("💻 System").tag(ThemeMode.system)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                // Row 3: After keys released
                HStack {
                    Text("After keys are released")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.afterRelease) {
                        Text("✦ Focus").tag("Focus")
                        Text("❚❚ Hold").tag("Hold")
                        Text("🔍 Search").tag("Search")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }


            }

            Divider()

            // MARK: - Native Rendering & Performance
            VStack(alignment: .leading, spacing: 10) {
                Text("HUD Rendering & Optics")
                    .font(.system(size: 14, weight: .bold))

                HStack(spacing: 12) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 16))
                        .foregroundColor(settings.accentColor)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("High-Performance Native Blur")
                            .font(.system(size: 12.5, weight: .semibold))
                        Text("The switcher HUD floats directly over your active windows using hardware-accelerated macOS system materials with zero latency.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                )
            }

            Divider()

            // Multiple Screens Section
            VStack(alignment: .leading, spacing: 12) {
                Text("Multiple screens")
                    .font(.system(size: 14, weight: .bold))

                HStack {
                    Text("Show on")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.screenPlacement) {
                        ForEach(ScreenPlacement.allCases) { placement in
                            Text(placement.rawValue).tag(placement)
                        }
                    }
                    .frame(width: 220)
                }

                HStack {
                    Spacer()
                    Button("Animations...") {
                        uiState.showAnimationsSheet = true
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func appearanceCard<Content: View>(
        style: SwitcherStyle,
        label: String,
        badge: String?,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isSelected = settings.switcherStyle == style
        return Button(action: { settings.switcherStyle = style }) {
            VStack(spacing: 8) {
                content()
                    .frame(height: 104)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(isSelected ? settings.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 2.2 : 0.8)
                    )
                    .shadow(color: isSelected ? settings.accentColor.opacity(0.35) : Color.black.opacity(0.1), radius: isSelected ? 6 : 2, x: 0, y: 2)

                HStack(spacing: 4) {
                    Text(label)
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundColor(isSelected ? settings.accentColor : .primary)

                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(isSelected ? settings.accentColor : .secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(
                                Capsule()
                                    .fill(isSelected ? settings.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                            )
                    }
                }
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private var miniDesktopBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.12, green: 0.16, blue: 0.28), Color(red: 0.05, green: 0.08, blue: 0.18)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private func miniWindowThumbnail(title: String, hasImage: Bool) -> some View {
        VStack(spacing: 0) {
            // Header bar with traffic lights
            HStack(spacing: 3) {
                Circle().fill(Color.red.opacity(0.8)).frame(width: 4, height: 4)
                Circle().fill(Color.yellow.opacity(0.8)).frame(width: 4, height: 4)
                Circle().fill(Color.green.opacity(0.8)).frame(width: 4, height: 4)
                Spacer()
                Text(title)
                    .font(.system(size: 6.5, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .background(Color.white.opacity(0.15))

            // Body
            ZStack {
                Color.black.opacity(0.35)
                if hasImage {
                    Image(systemName: "photo")
                        .font(.system(size: 14))
                        .foregroundColor(.blue.opacity(0.7))
                } else {
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.4)).frame(width: 36, height: 3)
                        RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.25)).frame(width: 28, height: 3)
                    }
                }
            }
        }
        .frame(width: 72, height: 58)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.6)
        )
    }

    private func miniAppIconView(symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(color)
                .frame(width: 22, height: 22)
            Image(systemName: symbol)
                .font(.system(size: 12))
                .foregroundColor(.white)
        }
    }

    private func miniTitleRow(text: String, isSelected: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 7))
                .foregroundColor(isSelected ? settings.accentColor : .white.opacity(0.5))
            Text(text)
                .font(.system(size: 7.5, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.8))
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isSelected ? settings.accentColor.opacity(0.45) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .stroke(isSelected ? settings.accentColor : Color.clear, lineWidth: 0.8)
        )
    }

    // MARK: - 3. Controls Pane (Matches Screenshot 1 bottom & Screenshot 2)
    private var controlsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Controls")
                .font(.system(size: 20, weight: .bold))

            // Two-column Split View for Shortcuts
            HStack(alignment: .top, spacing: 12) {
                // Left Column: Shortcut List
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        shortcutSelectorItem(index: 0, title: "Shortcut 1", subtitle: settings.primaryShortcut.rawValue.components(separatedBy: " ").first ?? "⌥", hasProBadge: false)
                        shortcutSelectorItem(index: 1, title: "Shortcut 2", subtitle: settings.secondaryShortcut, hasProBadge: true)
                        shortcutSelectorItem(index: 2, title: "Gesture", subtitle: "Disabled", hasProBadge: false)
                    }
                    .padding(6)

                    Spacer()

                    Divider()

                    // Add / Remove toolbar
                    HStack(spacing: 12) {
                        Button(action: {}) {
                            Image(systemName: "plus")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)

                        Button(action: {}) {
                            Image(systemName: "minus")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .frame(width: 155, height: 380)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                )

                // Right Column: Configuration & Sub-tabs
                VStack(alignment: .leading, spacing: 14) {
                    // Trigger Keycaps
                    HStack(spacing: 8) {
                        Text("Trigger")
                            .font(.system(size: 12.5, weight: .medium))
                        Spacer()
                        Text("Hold")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                        keycapView(text: settings.primaryShortcut == .commandTab ? "⌘ Command" : "⌥ Option")
                        Text("and press")
                            .font(.system(size: 11.5))
                            .foregroundColor(.secondary)
                        keycapView(text: "⇥ Tab")
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.025))
                    )

                    // Sub-tabs Segmented Picker
                    Picker("", selection: $uiState.controlsSubTab) {
                        Text("Filtering").tag("Filtering")
                        Text("Appearance").tag("Appearance")
                        Text("Ordering & Grouping").tag("Ordering & Grouping")
                    }
                    .pickerStyle(.segmented)

                    // Sub-tab Content
                    if uiState.controlsSubTab == "Filtering" {
                        filteringSubTab
                    } else if uiState.controlsSubTab == "Appearance" {
                        appearanceSubTab
                    } else {
                        orderingSubTab
                    }

                    Spacer()

                    // Bottom Action Buttons
                    HStack {
                        Spacer()
                        Button("Additional controls...") {
                            uiState.showShortcutsSheet = true
                        }
                        .buttonStyle(.bordered)

                        Button("Shortcuts when active...") {
                            uiState.showShortcutsSheet = true
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 380)
            }
        }
    }

    private func shortcutSelectorItem(index: Int, title: String, subtitle: String, hasProBadge: Bool) -> some View {
        let isSelected = uiState.selectedShortcutItem == index
        return Button(action: { uiState.selectedShortcutItem = index }) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(isSelected ? .white : .primary)
                        if hasProBadge {
                            Text("Pro")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(isSelected ? .white : .secondary)
                                .padding(.horizontal, 3)
                                .background(Capsule().fill(isSelected ? Color.white.opacity(0.2) : Color.primary.opacity(0.08)))
                        }
                    }
                    Text(subtitle)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? settings.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func keycapView(text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            .foregroundColor(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(Color.primary.opacity(0.2), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
    }

    // Controls -> Filtering Tab
    private var filteringSubTab: some View {
        VStack(spacing: 10) {
            filterRow(label: "Show windows from applications") {
                Picker("", selection: $settings.appsFilter) {
                    Text("All apps").tag("All apps")
                    Text("Visible apps").tag("Visible apps")
                    Text("Focused app only").tag("Focused app only")
                }
                .frame(width: 160)
            }

            filterRow(label: "Show windows from Spaces") {
                Picker("", selection: $settings.spacesFilter) {
                    Text("All Spaces").tag("All Spaces")
                    Text("Visible Spaces").tag("Visible Spaces")
                    Text("Active Space only").tag("Active Space only")
                }
                .frame(width: 160)
            }

            filterRow(label: "Show windows from screens") {
                Picker("", selection: $settings.screensFilter) {
                    Text("All screens").tag("All screens")
                    Text("Active screen only").tag("Active screen only")
                }
                .frame(width: 160)
            }

            filterRow(label: "Show minimized windows") {
                Picker("", selection: $settings.showMinimizedPolicy) {
                    Text("Show").tag("Show")
                    Text("Hide").tag("Hide")
                    Text("At the end").tag("At the end")
                }
                .frame(width: 160)
            }

            filterRow(label: "Show hidden windows") {
                Picker("", selection: $settings.showHiddenPolicy) {
                    Text("Show").tag("Show")
                    Text("Hide").tag("Hide")
                    Text("At the end").tag("At the end")
                }
                .frame(width: 160)
            }

            filterRow(label: "Show fullscreen windows") {
                Picker("", selection: $settings.showFullscreenPolicy) {
                    Text("Show").tag("Show")
                    Text("Hide").tag("Hide")
                    Text("At the end").tag("At the end")
                }
                .frame(width: 160)
            }

            filterRow(label: "Show apps with no open window") {
                Picker("", selection: $settings.showNoWindowsPolicy) {
                    Text("Show at the end").tag("Show at the end")
                    Text("Hide").tag("Hide")
                    Text("Show").tag("Show")
                }
                .frame(width: 160)
            }
        }
    }

    private func filterRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12.5))
            Spacer()
            content()
        }
    }

    // Controls -> Appearance Sub-tab
    private var appearanceSubTab: some View {
        VStack(spacing: 12) {
            Toggle(isOn: $settings.showWindowBadges) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Show app icon badge on thumbnails")
                        .font(.system(size: 12.5))
                    Text("Renders small app logo in corner of live preview card.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)

            filterRow(label: "Primary trigger shortcut") {
                Picker("", selection: $settings.primaryShortcut) {
                    Text("⌥ Option + Tab").tag(ShortcutTrigger.optionTab)
                    Text("⌘ Command + Tab").tag(ShortcutTrigger.commandTab)
                }
                .frame(width: 180)
            }

            filterRow(label: "Title truncation mode") {
                Picker("", selection: .constant("Tail")) {
                    Text("Truncate tail").tag("Tail")
                    Text("Truncate middle").tag("Middle")
                    Text("Truncate head").tag("Head")
                }
                .frame(width: 160)
            }
        }
    }

    // Controls -> Ordering & Grouping Sub-tab
    private var orderingSubTab: some View {
        VStack(spacing: 12) {
            filterRow(label: "Order windows by") {
                Picker("", selection: $settings.orderWindowsBy) {
                    Text("Most recently used (MRU)").tag("Most recently used (MRU)")
                    Text("Application name").tag("Application name")
                    Text("Space order").tag("Space order")
                }
                .frame(width: 220)
            }

            Toggle(isOn: $settings.groupWindowsByApp) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Group windows by application")
                        .font(.system(size: 12.5))
                    Text("Keeps multi-profile Chrome, Safari, and Terminal windows clustered together.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }
            .toggleStyle(.switch)
        }
    }

    // MARK: - 4. General Pane (Matches Screenshot 2 bottom & Screenshot 3 top)
    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("General")
                .font(.system(size: 20, weight: .bold))

            // Toggles
            VStack(spacing: 12) {
                HStack {
                    Text("Start at login")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Toggle("", isOn: $settings.startAtLogin)
                        .toggleStyle(.switch)
                }

                HStack {
                    Text("Menubar icon")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.menubarIconStyle) {
                        Text("Standard").tag("Standard")
                        Text("Minimal").tag("Minimal")
                        Text("Dot").tag("Dot")
                    }
                    .frame(width: 120)
                    Toggle("", isOn: $settings.showMenubarIcon)
                        .toggleStyle(.switch)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Capture windows in the background")
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                        Toggle("", isOn: $settings.captureInBackground)
                            .toggleStyle(.switch)
                    }
                    Text("When disabled, avoids the macOS purple screen-recording indicator, and avoids flickers when playing DRM video. Thumbnails will be less up-to-date.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Language & Updates Policy
            VStack(spacing: 12) {
                HStack {
                    Text("Language")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.language) {
                        Text("System Default").tag("System Default")
                        Text("English (US)").tag("English (US)")
                        Text("Deutsch").tag("Deutsch")
                        Text("Français").tag("Français")
                        Text("Español").tag("Español")
                        Text("日本語").tag("日本語")
                        Text("简体中文").tag("简体中文")
                    }
                    .frame(width: 180)
                }

                // Software Update & GitHub Releases
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Updates policy")
                                .font(.system(size: 13, weight: .medium))
                            Text("WindowSwitcher automatically queries GitHub Releases for updates.")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Picker("", selection: $settings.updatePolicy) {
                            Text("Check for updates periodically").tag("Check for updates periodically")
                            Text("Check manually").tag("Check manually")
                        }
                        .frame(width: 220)
                    }

                    // Update Status & Action Row
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(settings.accentColor)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text("WindowSwitcher")
                                    .font(.system(size: 12.5, weight: .semibold))
                                Text("v\(UpdateManager.shared.currentVersion)")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundColor(.secondary)

                                switch UpdateManager.shared.status {
                                case .upToDate:
                                    Text("Up to Date")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.green.opacity(0.15))
                                        .clipShape(Capsule())
                                case .available(let ver, _, _, _):
                                    Text("v\(ver) Available")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(settings.accentColor)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(settings.accentColor.opacity(0.15))
                                        .clipShape(Capsule())
                                default:
                                    EmptyView()
                                }
                            }

                            switch UpdateManager.shared.status {
                            case .idle:
                                Text(UpdateManager.shared.lastCheckDate == nil ? "Not checked yet in this session." : "Last checked \(UpdateManager.shared.lastCheckDate!.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            case .checking:
                                HStack(spacing: 4) {
                                    ProgressView().scaleEffect(0.5)
                                    Text("Checking for latest release on GitHub...")
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                            case .upToDate:
                                Text("You are on the latest version.")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            case .available(let ver, let notes, _, _):
                                Text("Version \(ver) is available. \(notes)")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .lineLimit(2)
                            case .downloading(let progress):
                                Text("Downloading DMG update: \(Int(progress * 100))%")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            case .installing:
                                Text("Mounting DMG and replacing /Applications/WindowSwitcher.app...")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            case .readyToRelaunch:
                                Text("Update successfully installed. Relaunch to complete.")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.green)
                            case .error(let message):
                                Text(message)
                                    .font(.system(size: 11))
                                    .foregroundColor(.red)
                                    .lineLimit(1)
                            }
                        }

                        Spacer()

                        switch UpdateManager.shared.status {
                        case .idle, .upToDate, .error:
                            Button("Check for Updates Now...") {
                                UpdateManager.shared.checkForUpdates(userInitiated: true)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                        case .checking:
                            ProgressView()
                                .scaleEffect(0.65)

                        case .available(_, _, let downloadUrl, _):
                            Button("Download & Install Update") {
                                UpdateManager.shared.downloadAndInstall(from: downloadUrl)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)

                        case .downloading(let progress):
                            ProgressView(value: progress)
                                .frame(width: 90)

                        case .installing:
                            ProgressView()
                                .scaleEffect(0.65)

                        case .readyToRelaunch:
                            Button("Relaunch Now") {
                                UpdateManager.shared.relaunch()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }

                HStack {
                    Text("Crash reports policy")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Picker("", selection: $settings.crashReportPolicy) {
                        Text("Ask whether to send crash reports").tag("Ask whether to send crash reports")
                        Text("Always send").tag("Always send")
                        Text("Never send").tag("Never send")
                    }
                    .frame(width: 240)
                }
            }

            Divider()

            // System Permissions Section (100% Offline & Compliant)
            VStack(alignment: .leading, spacing: 10) {
                Text("System Permissions (100% Local & Private)")
                    .font(.system(size: 13, weight: .semibold))

                permissionItemRow(
                    title: "Accessibility",
                    description: "Enables fast global shortcut listening and instant window focusing.",
                    isGranted: permissions.hasAccessibility,
                    onRequest: { permissions.requestAccessibility() }
                )

                permissionItemRow(
                    title: "Screen Recording",
                    description: "Streams crisp 60 FPS live hardware thumbnails via Apple ScreenCaptureKit.",
                    isGranted: permissions.hasScreenRecording,
                    onRequest: { permissions.requestScreenRecording() }
                )
            }

            Divider()

            // Bottom Utility Action Buttons
            HStack(spacing: 10) {
                Button("Export settings...") {
                    exportSettingsDialog()
                }
                .buttonStyle(.bordered)

                Button("Import settings...") {
                    importSettingsDialog()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Reset settings and restart...") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func permissionItemRow(title: String, description: String, isGranted: Bool, onRequest: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundColor(isGranted ? .green : .orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                Text(description)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            if isGranted {
                Text("Active")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.14))
                    .clipShape(Capsule())
            } else {
                Button("Grant Access") {
                    onRequest()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    // MARK: - 5. Exceptions Pane (Matches Screenshot 3)
    private var exceptionsPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Exceptions")
                .font(.system(size: 20, weight: .bold))

            // Master-Detail Exceptions View
            HStack(alignment: .top, spacing: 14) {
                // Left Column: App List
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(settings.exceptionsList) { exc in
                                exceptionListItem(item: exc)
                            }
                        }
                        .padding(6)
                    }

                    Divider()

                    // Add / Remove Bar
                    HStack(spacing: 8) {
                        Button(action: { uiState.showAddExceptionSheet = true }) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Add an application to exceptions")

                        Button(action: {
                            settings.removeException(bundleId: uiState.selectedExceptionId)
                            if let next = settings.exceptionsList.first {
                                uiState.selectedExceptionId = next.bundleId
                            }
                        }) {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(settings.exceptionsList.isEmpty)
                        .help("Remove selected exception")

                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
                .frame(width: 220, height: 380)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                )

                // Right Column: Detail View for Selected Exception
                if let selected = settings.exceptionsList.first(where: { $0.bundleId == uiState.selectedExceptionId }) {
                    exceptionDetailView(item: selected)
                        .frame(maxWidth: .infinity, minHeight: 380, alignment: .topLeading)
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                        Image(systemName: "hand.raised.slash")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No Exception Selected")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, minHeight: 380)
                }
            }
        }
    }

    private func exceptionListItem(item: AppException) -> some View {
        let isSelected = uiState.selectedExceptionId == item.bundleId
        return Button(action: { uiState.selectedExceptionId = item.bundleId }) {
            HStack(spacing: 8) {
                // App Icon
                appIconForBundle(bundleId: item.bundleId, name: item.name)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isSelected ? .white : .primary)
                        .lineLimit(1)
                    Text(item.hideWindows == "Always" ? "Hide" : item.ignoreShortcuts)
                        .font(.system(size: 10))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? settings.accentColor : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func exceptionDetailView(item: AppException) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // App Header Row
            HStack(spacing: 12) {
                appIconForBundle(bundleId: item.bundleId, name: item.name)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.system(size: 16, weight: .bold))
                    Text(item.bundleId)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 6)

            Divider()

            // Detail Fields
            VStack(spacing: 14) {
                HStack {
                    Text("Bundle ID")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 120, alignment: .leading)
                    TextField("", text: Binding(
                        get: { item.bundleId },
                        set: { newId in
                            settings.addException(name: item.name, bundleId: newId, hideWindows: item.hideWindows, ignoreShortcuts: item.ignoreShortcuts)
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                }

                HStack {
                    Text("Hide windows")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { item.hideWindows },
                        set: { newHide in
                            settings.updateException(bundleId: item.bundleId, hideWindows: newHide, ignoreShortcuts: item.ignoreShortcuts)
                        }
                    )) {
                        Text("When no open window").tag("When no open window")
                        Text("Always").tag("Always")
                        Text("Never").tag("Never")
                    }
                    .frame(width: 220)
                    Spacer()
                }

                HStack {
                    Text("Ignore shortcuts")
                        .font(.system(size: 12.5, weight: .medium))
                        .frame(width: 120, alignment: .leading)
                    Picker("", selection: Binding(
                        get: {
                            if ["Never", "When in focus", "Always"].contains(item.ignoreShortcuts) {
                                return item.ignoreShortcuts
                            }
                            return "When in focus"
                        },
                        set: { newIgnore in
                            settings.updateException(bundleId: item.bundleId, hideWindows: item.hideWindows, ignoreShortcuts: newIgnore)
                        }
                    )) {
                        Text("Never").tag("Never")
                        Text("When in focus").tag("When in focus")
                        Text("Always").tag("Always")
                    }
                    .frame(width: 220)
                    Spacer()
                }
            }

            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        )
    }

    private func appIconForBundle(bundleId: String, name: String) -> some View {
        if let appUrl = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            let icon = NSWorkspace.shared.icon(forFile: appUrl.path)
            return AnyView(Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit))
        } else if let icon = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleId || $0.localizedName == name })?.icon {
            return AnyView(Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit))
        } else {
            let symbol: String
            let bgCol: Color
            let lowerName = name.lowercased()
            if lowerName.contains("sharing") || bundleId.contains("ScreenSharing") {
                symbol = "display"
                bgCol = Color.blue
            } else if lowerName.contains("remote") || bundleId.contains("rdc") {
                symbol = "display.2"
                bgCol = Color.orange
            } else if lowerName.contains("teamviewer") {
                symbol = "arrow.triangle.2.circlepath"
                bgCol = Color.blue
            } else if lowerName.contains("parallels") {
                symbol = "macwindow.badge.plus"
                bgCol = Color.red
            } else if lowerName.contains("finder") {
                symbol = "folder.fill"
                bgCol = Color.cyan
            } else {
                symbol = "app.fill"
                bgCol = Color.gray
            }
            return AnyView(
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(bgCol.opacity(0.14))
                    Image(systemName: symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(bgCol)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(bgCol.opacity(0.28), lineWidth: 0.8)
                )
            )
        }
    }

    // MARK: - 6. Open Canvas & Styling Studio Pane
    private var canvasPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Open Canvas & Styling Studio")
                    .font(.system(size: 20, weight: .bold))
                Text("Live sandbox to customize liquid glass, accent colors, curvature, and elevation.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            // Real-time Interactive Switcher Preview
            VStack(alignment: .leading, spacing: 8) {
                Text("LIVE CANVAS PREVIEW")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundColor(.secondary)

                HStack(spacing: 12) {
                    canvasMockCard(title: "Safari", icon: "safari.fill", isSelected: true)
                    canvasMockCard(title: "Notes", icon: "note.text", isSelected: false)
                    canvasMockCard(title: "Terminal", icon: "terminal.fill", isSelected: false)
                }
                .padding(20)
                .background(canvasMockupBackground)
                .overlay(canvasMockupBorder)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )

            Divider()

            // Accent Color Palette
            VStack(alignment: .leading, spacing: 8) {
                Text("Accent Highlight Color")
                    .font(.system(size: 13, weight: .semibold))

                HStack(spacing: 10) {
                    colorPresetButton(hex: "#007AFF", name: "Apple Blue")
                    colorPresetButton(hex: "#8E8E93", name: "Graphite")
                    colorPresetButton(hex: "#5856D6", name: "Indigo")
                    colorPresetButton(hex: "#34C759", name: "Emerald")
                    colorPresetButton(hex: "#FF9500", name: "Amber")
                    colorPresetButton(hex: "#FF3B30", name: "Coral")
                    colorPresetButton(hex: "#AF52DE", name: "Purple")
                }

                HStack(spacing: 8) {
                    Text("Custom Hex:")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    TextField("#007AFF", text: $settings.customAccentColorHex)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            // Geometry Sliders
            VStack(spacing: 12) {
                HStack {
                    Text("Glass Scrim Darkness")
                        .font(.system(size: 12.5))
                    Spacer()
                    Slider(value: $settings.glassOpacity, in: 0.15...0.85, step: 0.05)
                        .frame(width: 200)
                    Text("\(Int(settings.glassOpacity * 100))%")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text("HUD Corner Radius")
                        .font(.system(size: 12.5))
                    Spacer()
                    Slider(value: $settings.hudCornerRadius, in: 14.0...38.0, step: 2.0)
                        .frame(width: 200)
                    Text("\(Int(settings.hudCornerRadius))px")
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text("Specular Border Width")
                        .font(.system(size: 12.5))
                    Spacer()
                    Slider(value: $settings.borderWidth, in: 0.0...3.0, step: 0.5)
                        .frame(width: 200)
                    Text(String(format: "%.1fpx", settings.borderWidth))
                        .font(.system(size: 11, design: .monospaced))
                        .frame(width: 36, alignment: .trailing)
                }

                HStack {
                    Text("Drop Shadow Depth")
                        .font(.system(size: 12.5))
                    Spacer()
                    Picker("", selection: $settings.shadowDepth) {
                        Text("Subtle Contact").tag("Subtle Depth")
                        Text("Apple HIG Balanced").tag("Apple HIG Balanced")
                        Text("Deep Floating").tag("Floating Deep")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 300)
                }
            }

            Divider()

            // Canvas Actions
            HStack {
                Button("Reset to Apple HIG Defaults") {
                    settings.resetToDefaults()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Test Live Switcher (Space)") {
                    SwitcherState.shared.show()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private func canvasMockCard(title: String, icon: String, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white : .white.opacity(0.8))
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? settings.accentColor : .white.opacity(0.6))
            }
            .frame(height: 50)
        }
        .padding(6)
        .frame(width: 105, height: 82)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? settings.accentColor.opacity(0.25) : Color.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSelected ? settings.accentColor : Color.white.opacity(0.1), lineWidth: isSelected ? 2.0 : 0.8)
        )
        .shadow(color: isSelected ? settings.accentColor.opacity(0.3) : Color.clear, radius: 5, x: 0, y: 2)
    }

    private var canvasMockupBackground: some View {
        let shadowRad: CGFloat = settings.shadowDepth == "Subtle Depth" ? 12 : (settings.shadowDepth == "Floating Deep" ? 32 : 22)
        return RoundedRectangle(cornerRadius: CGFloat(settings.hudCornerRadius * 0.7), style: .continuous)
            .fill(Color.black.opacity(settings.glassOpacity))
            .shadow(color: Color.black.opacity(0.5), radius: shadowRad, x: 0, y: 8)
    }

    private var canvasMockupBorder: some View {
        RoundedRectangle(cornerRadius: CGFloat(settings.hudCornerRadius * 0.7), style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [Color.white.opacity(0.4), Color.white.opacity(0.12)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: CGFloat(settings.borderWidth)
            )
    }

    private func colorPresetButton(hex: String, name: String) -> some View {
        let isSelected = settings.customAccentColorHex.uppercased() == hex.uppercased()
        let col = Color(hex: hex) ?? .blue

        return Button(action: { settings.customAccentColorHex = hex }) {
            Circle()
                .fill(col)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 2.2 : 0)
                )
                .shadow(color: col.opacity(isSelected ? 0.45 : 0.15), radius: 3, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .help(name)
    }

    // MARK: - Modals & Dialogs
    private var shortcutsCheatsheetModal: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Window Switcher Navigation Shortcuts")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Done") {
                    uiState.showShortcutsSheet = false
                }
            }

            VStack(spacing: 8) {
                shortcutRow(keys: "⇥ Tab", description: "Select next window")
                shortcutRow(keys: "⇧ + ⇥ Shift + Tab", description: "Select previous window")
                shortcutRow(keys: "←, →, ↑, ↓", description: "Navigate 2D window grid")
                shortcutRow(keys: "W", description: "Close selected window immediately")
                shortcutRow(keys: "Q", description: "Quit selected application")
                shortcutRow(keys: "M", description: "Minimize selected window")
                shortcutRow(keys: "H", description: "Hide selected application")
                shortcutRow(keys: "Space", description: "Quick preview window")
                shortcutRow(keys: "⎋ Escape", description: "Cancel and dismiss switcher")
            }
            .padding(12)
            .background(Color.primary.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(20)
        .frame(width: 440)
    }

    private func shortcutRow(keys: String, description: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            Spacer()
            Text(description)
                .font(.system(size: 11.5))
                .foregroundColor(.secondary)
        }
    }

    private var animationsModal: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Animations & Dynamics")
                    .font(.system(size: 15, weight: .bold))
                Spacer()
                Button("Done") {
                    uiState.showAnimationsSheet = false
                }
            }

            Toggle("Enable smooth HUD animations", isOn: $settings.animationsEnabled)
                .toggleStyle(.switch)

            Text("Uses Apple Spring physics curve (response: 0.22s, damping: 0.86) for snappy, zero-latency feedback.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 380)
    }

    private var addExceptionModal: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Excluded Application")
                .font(.system(size: 15, weight: .bold))

            TextField("Application Name (e.g. CleanShot X)", text: $uiState.newAppName)
                .textFieldStyle(.roundedBorder)

            TextField("Bundle Identifier (optional, e.g. pl.maketheweb.cleanshotx)", text: $uiState.newBundleId)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Cancel") {
                    uiState.showAddExceptionSheet = false
                }

                Spacer()

                Button("Choose from /Applications...") {
                    let panel = NSOpenPanel()
                    panel.allowsMultipleSelection = false
                    panel.canChooseDirectories = false
                    panel.canChooseFiles = true
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")

                    if panel.runModal() == .OK, let url = panel.url {
                        let bundle = Bundle(url: url)
                        let appName = bundle?.infoDictionary?["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent
                        let bundleId = bundle?.bundleIdentifier ?? "com.custom.\(appName.lowercased())"
                        settings.addException(name: appName, bundleId: bundleId)
                        uiState.selectedExceptionId = bundleId
                        uiState.showAddExceptionSheet = false
                    }
                }

                Button("Add") {
                    let bId = uiState.newBundleId.isEmpty ? "com.custom.\(uiState.newAppName.lowercased())" : uiState.newBundleId
                    settings.addException(name: uiState.newAppName, bundleId: bId)
                    uiState.selectedExceptionId = bId
                    uiState.newAppName = ""
                    uiState.newBundleId = ""
                    uiState.showAddExceptionSheet = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(uiState.newAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func exportSettingsDialog() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "WindowSwitcher-Settings.json"
        savePanel.allowedContentTypes = [.json]
        if savePanel.runModal() == .OK, let url = savePanel.url {
            let dict: [String: Any] = [
                "switcherStyle": settings.switcherStyle.rawValue,
                "cardSize": settings.cardSize.rawValue,
                "themeMode": settings.themeMode.rawValue,
                "accentColor": settings.customAccentColorHex,
                "glassOpacity": settings.glassOpacity,
                "hudCornerRadius": settings.hudCornerRadius
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted) {
                try? data.write(to: url)
            }
        }
    }

    private func importSettingsDialog() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        if openPanel.runModal() == .OK, let url = openPanel.url, let data = try? Data(contentsOf: url) {
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let style = dict["switcherStyle"] as? String, let s = SwitcherStyle(rawValue: style) {
                    settings.switcherStyle = s
                }
                if let hex = dict["accentColor"] as? String {
                    settings.customAccentColorHex = hex
                }
            }
        }
    }
}
