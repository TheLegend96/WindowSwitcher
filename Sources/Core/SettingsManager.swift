import SwiftUI
import AppKit
import ServiceManagement

public enum SwitcherStyle: String, CaseIterable, Identifiable {
    case thumbnails = "Thumbnails"
    case icons = "App Icons"
    case titles = "Titles"

    public var id: String { rawValue }
}

public enum CardSize: String, CaseIterable, Identifiable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"

    public var id: String { rawValue }

    public var cardHeight: CGFloat {
        switch self {
        case .small: return 110
        case .medium: return 148
        case .large: return 188
        }
    }

    public var previewHeight: CGFloat {
        switch self {
        case .small: return 75
        case .medium: return 110
        case .large: return 145
        }
    }

    public var iconSize: CGFloat {
        switch self {
        case .small: return 56
        case .medium: return 72
        case .large: return 88
        }
    }

    public var iconSlotWidth: CGFloat {
        iconSize + 28
    }

    public var iconSlotHeight: CGFloat {
        iconSize + 52
    }
}

public enum ThemeMode: String, CaseIterable, Identifiable {
    case light = "Light"
    case dark = "Dark"
    case system = "System"

    public var id: String { rawValue }
}

public enum ScreenPlacement: String, CaseIterable, Identifiable {
    case activeScreen = "Active screen"
    case cursorScreen = "Screen with mouse pointer"
    case primaryScreen = "Screen showing menu bar"
    case allScreens = "All screens"

    public var id: String { rawValue }
}

public enum ShortcutTrigger: String, CaseIterable, Identifiable {
    case optionTab = "⌥ Option + Tab"
    case commandTab = "⌘ Command + Tab"

    public var id: String { rawValue }
}

public struct AppException: Codable, Identifiable, Hashable {
    public var id: String { bundleId }
    public var name: String
    public var bundleId: String
    public var hideWindows: String // "When no open window", "Always", "Never"
    public var ignoreShortcuts: String // "Never", "Always", "When active"

    public init(name: String, bundleId: String, hideWindows: String = "When no open window", ignoreShortcuts: String = "Never") {
        self.name = name
        self.bundleId = bundleId
        self.hideWindows = hideWindows
        self.ignoreShortcuts = ignoreShortcuts
    }
}

@MainActor
public class SettingsManager: ObservableObject {
    public static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    // MARK: - Appearance
    @Published public var switcherStyle: SwitcherStyle {
        didSet { defaults.set(switcherStyle.rawValue, forKey: "switcherStyle") }
    }
    @Published public var cardSize: CardSize {
        didSet { defaults.set(cardSize.rawValue, forKey: "cardSize") }
    }
    @Published public var themeMode: ThemeMode {
        didSet { defaults.set(themeMode.rawValue, forKey: "themeMode") }
    }
    @Published public var afterRelease: String {
        didSet { defaults.set(afterRelease, forKey: "afterRelease") }
    }
    @Published public var previewSelectedWindow: Bool {
        didSet { defaults.set(previewSelectedWindow, forKey: "previewSelectedWindow") }
    }
    @Published public var screenPlacement: ScreenPlacement {
        didSet { defaults.set(screenPlacement.rawValue, forKey: "screenPlacement") }
    }
    @Published public var animationsEnabled: Bool {
        didSet { defaults.set(animationsEnabled, forKey: "animationsEnabled") }
    }

    // MARK: - Screenshots & Designer Tools
    @Published public var screenshotKeyCombination: KeyCombination {
        didSet {
            if let data = try? JSONEncoder().encode(screenshotKeyCombination) {
                defaults.set(data, forKey: "screenshotKeyCombination")
            }
        }
    }
    @Published public var activeWindowKeyCombination: KeyCombination {
        didSet {
            if let data = try? JSONEncoder().encode(activeWindowKeyCombination) {
                defaults.set(data, forKey: "activeWindowKeyCombination")
            }
        }
    }
    @Published public var autoOpenEditor: Bool {
        didSet { defaults.set(autoOpenEditor, forKey: "autoOpenEditor") }
    }
    @Published public var playShutterSound: Bool {
        didSet { defaults.set(playShutterSound, forKey: "playShutterSound") }
    }
    @Published public var enableSmartDistance: Bool {
        didSet { defaults.set(enableSmartDistance, forKey: "enableSmartDistance") }
    }
    @Published public var gridAuditUnit: Int {
        didSet { defaults.set(gridAuditUnit, forKey: "gridAuditUnit") }
    }

    // MARK: - Controls & Filtering
    @Published public var primaryShortcut: ShortcutTrigger {
        didSet { defaults.set(primaryShortcut.rawValue, forKey: "primaryShortcut") }
    }
    @Published public var ocrKeyCombination: KeyCombination {
        didSet {
            if let data = try? JSONEncoder().encode(ocrKeyCombination) {
                defaults.set(data, forKey: "ocrKeyCombination")
            }
            defaults.set(Int(ocrKeyCombination.keyCode), forKey: "ocrKeyCode")
            defaults.set(Int(ocrKeyCombination.modifiers), forKey: "ocrModifiers")
        }
    }
    @Published public var secondaryShortcut: String {
        didSet { defaults.set(secondaryShortcut, forKey: "secondaryShortcut") }
    }
    @Published public var appsFilter: String {
        didSet { defaults.set(appsFilter, forKey: "appsFilter") }
    }
    @Published public var spacesFilter: String {
        didSet { defaults.set(spacesFilter, forKey: "spacesFilter") }
    }
    @Published public var screensFilter: String {
        didSet { defaults.set(screensFilter, forKey: "screensFilter") }
    }
    @Published public var showMinimizedWindows: Bool {
        didSet { defaults.set(showMinimizedWindows, forKey: "showMinimizedWindows") }
    }
    @Published public var showHiddenWindows: Bool {
        didSet { defaults.set(showHiddenWindows, forKey: "showHiddenWindows") }
    }
    @Published public var showFullscreenWindows: Bool {
        didSet { defaults.set(showFullscreenWindows, forKey: "showFullscreenWindows") }
    }
    @Published public var showAppsWithNoWindows: Bool {
        didSet { defaults.set(showAppsWithNoWindows, forKey: "showAppsWithNoWindows") }
    }
    @Published public var showMinimizedPolicy: String {
        didSet { defaults.set(showMinimizedPolicy, forKey: "showMinimizedPolicy") }
    }
    @Published public var showHiddenPolicy: String {
        didSet { defaults.set(showHiddenPolicy, forKey: "showHiddenPolicy") }
    }
    @Published public var showFullscreenPolicy: String {
        didSet { defaults.set(showFullscreenPolicy, forKey: "showFullscreenPolicy") }
    }
    @Published public var showNoWindowsPolicy: String {
        didSet { defaults.set(showNoWindowsPolicy, forKey: "showNoWindowsPolicy") }
    }
    @Published public var orderWindowsBy: String {
        didSet { defaults.set(orderWindowsBy, forKey: "orderWindowsBy") }
    }
    @Published public var groupWindowsByApp: Bool {
        didSet { defaults.set(groupWindowsByApp, forKey: "groupWindowsByApp") }
    }

    // MARK: - General
    @Published public var startAtLogin: Bool {
        didSet {
            defaults.set(startAtLogin, forKey: "startAtLogin")
            updateLoginItem()
        }
    }
    @Published public var showMenubarIcon: Bool {
        didSet {
            defaults.set(showMenubarIcon, forKey: "showMenubarIcon")
            AppDelegate.shared?.toggleStatusItem(showMenubarIcon)
        }
    }
    @Published public var menubarIconStyle: String {
        didSet { defaults.set(menubarIconStyle, forKey: "menubarIconStyle") }
    }
    @Published public var captureInBackground: Bool {
        didSet { defaults.set(captureInBackground, forKey: "captureInBackground") }
    }
    @Published public var language: String {
        didSet { defaults.set(language, forKey: "language") }
    }
    @Published public var updatePolicy: String {
        didSet { defaults.set(updatePolicy, forKey: "updatePolicy") }
    }
    @Published public var crashReportPolicy: String {
        didSet { defaults.set(crashReportPolicy, forKey: "crashReportPolicy") }
    }

    // MARK: - Exceptions
    @Published public var exceptionsList: [AppException] {
        didSet { saveExceptions() }
    }

    // Backwards-compatible excludedAppNames
    public var excludedAppNames: [String] {
        exceptionsList.map { $0.name }
    }

    // MARK: - Canvas & Custom Styling
    @Published public var customAccentColorHex: String {
        didSet { defaults.set(customAccentColorHex, forKey: "customAccentColorHex") }
    }
    @Published public var glassOpacity: Double {
        didSet { defaults.set(glassOpacity, forKey: "glassOpacity") }
    }
    @Published public var hudCornerRadius: Double {
        didSet { defaults.set(hudCornerRadius, forKey: "hudCornerRadius") }
    }
    @Published public var borderWidth: Double {
        didSet { defaults.set(borderWidth, forKey: "borderWidth") }
    }
    @Published public var shadowDepth: String {
        didSet { defaults.set(shadowDepth, forKey: "shadowDepth") }
    }
    @Published public var showWindowBadges: Bool {
        didSet { defaults.set(showWindowBadges, forKey: "showWindowBadges") }
    }

    // MARK: - Preview State & Liquid Glass Physics
    @Published public var enableLiquidGlass: Bool {
        didSet { defaults.set(enableLiquidGlass, forKey: "enableLiquidGlass") }
    }
    @Published public var previewGlassOpacity: Double {
        didSet { defaults.set(previewGlassOpacity, forKey: "previewGlassOpacity") }
    }
    @Published public var previewGlassBlurRadius: Double {
        didSet { defaults.set(previewGlassBlurRadius, forKey: "previewGlassBlurRadius") }
    }
    @Published public var liquidDistortionIntensity: Double {
        didSet { defaults.set(liquidDistortionIntensity, forKey: "liquidDistortionIntensity") }
    }
    @Published public var chromaticDispersion: Double {
        didSet { defaults.set(chromaticDispersion, forKey: "chromaticDispersion") }
    }
    @Published public var meniscusCurvature: Double {
        didSet { defaults.set(meniscusCurvature, forKey: "meniscusCurvature") }
    }

    public var accentColor: Color {
        Color(hex: customAccentColorHex) ?? Color(red: 0.05, green: 0.50, blue: 1.0)
    }

    private init() {
        let styleStr = defaults.string(forKey: "switcherStyle") ?? SwitcherStyle.thumbnails.rawValue
        self.switcherStyle = SwitcherStyle(rawValue: styleStr) ?? .thumbnails

        let sizeStr = defaults.string(forKey: "cardSize") ?? CardSize.medium.rawValue
        self.cardSize = CardSize(rawValue: sizeStr) ?? .medium

        let themeStr = defaults.string(forKey: "themeMode") ?? ThemeMode.system.rawValue
        self.themeMode = ThemeMode(rawValue: themeStr) ?? .system

        self.afterRelease = defaults.string(forKey: "afterRelease") ?? "Focus"
        self.previewSelectedWindow = defaults.object(forKey: "previewSelectedWindow") == nil ? true : defaults.bool(forKey: "previewSelectedWindow")

        let screenStr = defaults.string(forKey: "screenPlacement") ?? ScreenPlacement.activeScreen.rawValue
        self.screenPlacement = ScreenPlacement(rawValue: screenStr) ?? .activeScreen
        self.animationsEnabled = defaults.object(forKey: "animationsEnabled") == nil ? true : defaults.bool(forKey: "animationsEnabled")

        let shortcutStr = defaults.string(forKey: "primaryShortcut") ?? ShortcutTrigger.commandTab.rawValue
        self.primaryShortcut = ShortcutTrigger(rawValue: shortcutStr) ?? .commandTab
        self.secondaryShortcut = defaults.string(forKey: "secondaryShortcut") ?? "⌥ + `"

        if let data = defaults.data(forKey: "screenshotKeyCombination"),
           let combo = try? JSONDecoder().decode(KeyCombination.self, from: data) {
            self.screenshotKeyCombination = combo
        } else {
            self.screenshotKeyCombination = KeyCombination.defaultScreenshot
        }

        if let data = defaults.data(forKey: "activeWindowKeyCombination"),
           let combo = try? JSONDecoder().decode(KeyCombination.self, from: data) {
            self.activeWindowKeyCombination = combo
        } else {
            self.activeWindowKeyCombination = KeyCombination.defaultActiveWindow
        }

        self.autoOpenEditor = defaults.object(forKey: "autoOpenEditor") == nil ? true : defaults.bool(forKey: "autoOpenEditor")
        self.playShutterSound = defaults.object(forKey: "playShutterSound") == nil ? true : defaults.bool(forKey: "playShutterSound")
        self.enableSmartDistance = defaults.object(forKey: "enableSmartDistance") == nil ? true : defaults.bool(forKey: "enableSmartDistance")
        self.gridAuditUnit = defaults.object(forKey: "gridAuditUnit") == nil ? 4 : defaults.integer(forKey: "gridAuditUnit")

        if let data = defaults.data(forKey: "ocrKeyCombination"),
           let combo = try? JSONDecoder().decode(KeyCombination.self, from: data) {
            self.ocrKeyCombination = combo
        } else {
            let code = defaults.object(forKey: "ocrKeyCode") != nil ? UInt16(defaults.integer(forKey: "ocrKeyCode")) : KeyCombination.defaultOCR.keyCode
            let mods = defaults.object(forKey: "ocrModifiers") != nil ? UInt(defaults.integer(forKey: "ocrModifiers")) : KeyCombination.defaultOCR.modifiers
            self.ocrKeyCombination = KeyCombination(keyCode: code, modifiers: mods)
        }

        self.appsFilter = defaults.string(forKey: "appsFilter") ?? "All apps"
        self.spacesFilter = defaults.string(forKey: "spacesFilter") ?? "All Spaces"
        self.screensFilter = defaults.string(forKey: "screensFilter") ?? "All screens"

        self.showMinimizedWindows = defaults.object(forKey: "showMinimizedWindows") == nil ? true : defaults.bool(forKey: "showMinimizedWindows")
        self.showHiddenWindows = defaults.object(forKey: "showHiddenWindows") == nil ? true : defaults.bool(forKey: "showHiddenWindows")
        self.showFullscreenWindows = defaults.object(forKey: "showFullscreenWindows") == nil ? true : defaults.bool(forKey: "showFullscreenWindows")
        self.showAppsWithNoWindows = defaults.bool(forKey: "showAppsWithNoWindows")

        self.showMinimizedPolicy = defaults.string(forKey: "showMinimizedPolicy") ?? "Show"
        self.showHiddenPolicy = defaults.string(forKey: "showHiddenPolicy") ?? "Show"
        self.showFullscreenPolicy = defaults.string(forKey: "showFullscreenPolicy") ?? "Show"
        self.showNoWindowsPolicy = defaults.string(forKey: "showNoWindowsPolicy") ?? "Show at the end"

        self.orderWindowsBy = defaults.string(forKey: "orderWindowsBy") ?? "Most recently used (MRU)"
        self.groupWindowsByApp = defaults.bool(forKey: "groupWindowsByApp")

        self.startAtLogin = SMAppService.mainApp.status == .enabled
        self.showMenubarIcon = defaults.object(forKey: "showMenubarIcon") == nil ? true : defaults.bool(forKey: "showMenubarIcon")
        self.menubarIconStyle = defaults.string(forKey: "menubarIconStyle") ?? "Standard"
        self.captureInBackground = defaults.object(forKey: "captureInBackground") == nil ? true : defaults.bool(forKey: "captureInBackground")
        self.language = defaults.string(forKey: "language") ?? "System Default"
        self.updatePolicy = defaults.string(forKey: "updatePolicy") ?? "Check for updates periodically"
        self.crashReportPolicy = defaults.string(forKey: "crashReportPolicy") ?? "Ask whether to send crash reports"

        // Canvas & Styling defaults
        self.customAccentColorHex = defaults.string(forKey: "customAccentColorHex") ?? "#007AFF"
        self.glassOpacity = defaults.object(forKey: "glassOpacity") == nil ? 0.35 : defaults.double(forKey: "glassOpacity")
        self.hudCornerRadius = defaults.object(forKey: "hudCornerRadius") == nil ? 28.0 : defaults.double(forKey: "hudCornerRadius")
        self.borderWidth = defaults.object(forKey: "borderWidth") == nil ? 1.0 : defaults.double(forKey: "borderWidth")
        self.shadowDepth = defaults.string(forKey: "shadowDepth") ?? "Apple HIG Balanced"
        self.showWindowBadges = defaults.object(forKey: "showWindowBadges") == nil ? true : defaults.bool(forKey: "showWindowBadges")

        // Liquid Glass Physics defaults (off by default for clean frosted glass preview)
        self.enableLiquidGlass = defaults.object(forKey: "enableLiquidGlass") == nil ? false : defaults.bool(forKey: "enableLiquidGlass")
        self.previewGlassOpacity = defaults.object(forKey: "previewGlassOpacity") == nil ? 0.72 : defaults.double(forKey: "previewGlassOpacity")
        self.previewGlassBlurRadius = defaults.object(forKey: "previewGlassBlurRadius") == nil ? 48.0 : defaults.double(forKey: "previewGlassBlurRadius")
        self.liquidDistortionIntensity = defaults.object(forKey: "liquidDistortionIntensity") == nil ? 0.65 : defaults.double(forKey: "liquidDistortionIntensity")
        self.chromaticDispersion = defaults.object(forKey: "chromaticDispersion") == nil ? 0.75 : defaults.double(forKey: "chromaticDispersion")
        self.meniscusCurvature = defaults.object(forKey: "meniscusCurvature") == nil ? 0.60 : defaults.double(forKey: "meniscusCurvature")

        // Load Exceptions with sanitized tags
        if let data = defaults.data(forKey: "exceptionsList"),
           let decoded = try? JSONDecoder().decode([AppException].self, from: data) {
            self.exceptionsList = decoded.map { item in
                var cleaned = item
                if cleaned.ignoreShortcuts == "Ignore shortcuts" || !["Never", "When in focus", "Always"].contains(cleaned.ignoreShortcuts) {
                    cleaned.ignoreShortcuts = "When in focus"
                }
                return cleaned
            }
        } else {
            // Seed defaults matching macOS switcher conventions
            self.exceptionsList = [
                AppException(name: "Finder", bundleId: "com.apple.finder", hideWindows: "When no open window", ignoreShortcuts: "Never"),
                AppException(name: "Screen Sharing", bundleId: "com.apple.ScreenSharing", hideWindows: "When no open window", ignoreShortcuts: "When in focus"),
                AppException(name: "Microsoft Remote Desktop", bundleId: "com.microsoft.rdc.macos", hideWindows: "When no open window", ignoreShortcuts: "When in focus"),
                AppException(name: "TeamViewer", bundleId: "com.teamviewer.TeamViewer", hideWindows: "When no open window", ignoreShortcuts: "When in focus"),
                AppException(name: "Parallels Desktop", bundleId: "com.parallels.desktop.console", hideWindows: "When no open window", ignoreShortcuts: "Never")
            ]
        }
    }

    private func saveExceptions() {
        if let encoded = try? JSONEncoder().encode(exceptionsList) {
            defaults.set(encoded, forKey: "exceptionsList")
        }
        // Also sync old key for backwards-compatibility
        defaults.set(exceptionsList.map { $0.name }, forKey: "excludedAppNames")
    }

    private func updateLoginItem() {
        do {
            if startAtLogin {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                    print("✅ Registered launch at login")
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                    print("✅ Unregistered launch at login")
                }
            }
        } catch {
            print("⚠️ SMAppService error: \(error)")
        }
    }

    public func resetToDefaults() {
        switcherStyle = .thumbnails
        cardSize = .medium
        themeMode = .system
        afterRelease = "Focus"
        previewSelectedWindow = true
        screenPlacement = .activeScreen
        animationsEnabled = true

        primaryShortcut = .commandTab
        secondaryShortcut = "⌥ + `"
        appsFilter = "All apps"
        spacesFilter = "All Spaces"
        screensFilter = "All screens"

        showMinimizedWindows = true
        showHiddenWindows = true
        showFullscreenWindows = true
        showAppsWithNoWindows = false

        showMinimizedPolicy = "Show"
        showHiddenPolicy = "Show"
        showFullscreenPolicy = "Show"
        showNoWindowsPolicy = "Show at the end"

        orderWindowsBy = "Most recently used (MRU)"
        groupWindowsByApp = false

        startAtLogin = SMAppService.mainApp.status == .enabled
        showMenubarIcon = true
        menubarIconStyle = "Standard"
        captureInBackground = true
        language = "System Default"
        updatePolicy = "Check for updates periodically"
        crashReportPolicy = "Ask whether to send crash reports"

        customAccentColorHex = "#007AFF"
        glassOpacity = 0.35
        hudCornerRadius = 28.0
        borderWidth = 1.0
        shadowDepth = "Apple HIG Balanced"
        showWindowBadges = true

        previewGlassOpacity = 0.72
        previewGlassBlurRadius = 48.0
        liquidDistortionIntensity = 0.65
        chromaticDispersion = 0.75
        meniscusCurvature = 0.60
        enableLiquidGlass = false
    }

    public func updateException(bundleId: String, hideWindows: String, ignoreShortcuts: String) {
        if let index = exceptionsList.firstIndex(where: { $0.bundleId == bundleId }) {
            exceptionsList[index].hideWindows = hideWindows
            exceptionsList[index].ignoreShortcuts = ignoreShortcuts
        }
    }

    public func addException(name: String, bundleId: String, hideWindows: String = "When no open window", ignoreShortcuts: String = "Never") {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBundle = bundleId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if let index = exceptionsList.firstIndex(where: { $0.bundleId.lowercased() == trimmedBundle.lowercased() || $0.name.lowercased() == trimmedName.lowercased() }) {
            exceptionsList[index].hideWindows = hideWindows
            exceptionsList[index].ignoreShortcuts = ignoreShortcuts
        } else {
            exceptionsList.append(AppException(name: trimmedName, bundleId: trimmedBundle.isEmpty ? "com.custom.\(trimmedName.lowercased())" : trimmedBundle, hideWindows: hideWindows, ignoreShortcuts: ignoreShortcuts))
        }
    }

    public func removeException(bundleId: String) {
        exceptionsList.removeAll { $0.bundleId == bundleId }
    }

    public func removeException(appName: String) {
        exceptionsList.removeAll { $0.name == appName || $0.bundleId == appName }
    }
}

// MARK: - Color Hex Helpers
public extension Color {
    init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let rgbValue = UInt64(cleanHex, radix: 16) else { return nil }

        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

public extension NSColor {
    convenience init?(hex: String) {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if cleanHex.hasPrefix("#") { cleanHex.removeFirst() }
        guard cleanHex.count == 6, let rgbValue = UInt64(cleanHex, radix: 16) else { return nil }

        let r = CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
