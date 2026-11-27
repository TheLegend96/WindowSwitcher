import Cocoa
import SwiftUI

@MainActor
public class AppDelegate: NSObject, NSApplicationDelegate {
    public static var shared: AppDelegate?

    private var statusItem: NSStatusItem?
    private var overlayPanel: NSPanel?
    private var settingsWindow: NSWindow?
    private var settingsWindowDelegate: SettingsWindowDelegate?
    private var onboardingWindow: NSWindow?
    private var permissionPollTimer: Timer?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        // File logging for live diagnosis
        freopen("/tmp/WindowSwitcher.log", "a", stdout)
        freopen("/tmp/WindowSwitcher.log", "a", stderr)
        setbuf(stdout, nil)
        setbuf(stderr, nil)
        print("\n=== WindowSwitcher Launched: \(Date()) ===")

        NSApp.setActivationPolicy(.accessory)

        setupStatusItem()
        setupOverlayPanel()

        // Check permissions and initialize shortcuts
        PermissionsManager.shared.checkPermissions()

        // Auto-poll permissions every 0.5s so when user grants, app immediately activates
        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            Task { @MainActor in
                PermissionsManager.shared.checkPermissions()
            }
        }

        // Show onboarding on first launch or if permissions are missing
        let hasCompleted = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if CommandLine.arguments.contains("--settings") {
            openSettings()
        } else if !hasCompleted || !PermissionsManager.shared.hasAccessibility || !PermissionsManager.shared.hasScreenRecording {
            openOnboarding()
        }

        // Distributed notifications for CLI / Scripting
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.openSettings"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.openSettings()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.openOnboarding"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.openOnboarding()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.triggerScreenshot"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                ScreenshotCoordinator.shared.startAreaCapture()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.triggerActiveWindowScreenshot"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                ScreenshotCoordinator.shared.captureActiveWindow()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.testClickOverlay"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                ScreenshotCoordinator.shared.simulateWindowClickForTesting()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.testEditorWindow"), object: nil, queue: .main) { notif in
            let selectStr = (notif.userInfo?["selectIndex"] as? String) ?? (notif.object as? String) ?? "3"
            let selIdx = Int(selectStr) ?? 3
            let editLive = (notif.userInfo?["editLiveText"] as? String) == "true"
            Task { @MainActor in
                // Generate a sample preview image
                let size = NSSize(width: 800, height: 500)
                let image = NSImage(size: size, flipped: false) { rect in
                    NSColor.windowBackgroundColor.setFill()
                    rect.fill()
                    let text = "WindowSwitcher Designer Studio Preview" as NSString
                    text.draw(at: NSPoint(x: 40, y: 440), withAttributes: [
                        .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                        .foregroundColor: NSColor.labelColor
                    ])
                    let secret = "TOKEN: sk_live_98123_redacted" as NSString
                    secret.draw(at: NSPoint(x: 530, y: 44), withAttributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: NSColor.labelColor
                    ])
                    return true
                }
                ScreenshotEditorWindowController.shared.show(image: image, sourceRect: NSRect(origin: .zero, size: size))
                ScreenshotEditorWindowController.shared.addSampleAnnotationsForTesting(selectedIndex: selIdx)
                if editLive {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        ScreenshotEditorWindowController.shared.openInlineTextForTesting(index: 5)
                    }
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.testEditorLiveText"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                let size = NSSize(width: 800, height: 500)
                let image = NSImage(size: size, flipped: false) { rect in
                    NSColor.windowBackgroundColor.setFill()
                    rect.fill()
                    let text = "WindowSwitcher Designer Studio Preview" as NSString
                    text.draw(at: NSPoint(x: 40, y: 440), withAttributes: [
                        .font: NSFont.systemFont(ofSize: 24, weight: .bold),
                        .foregroundColor: NSColor.labelColor
                    ])
                    let secret = "TOKEN: sk_live_98123_redacted" as NSString
                    secret.draw(at: NSPoint(x: 530, y: 44), withAttributes: [
                        .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                        .foregroundColor: NSColor.labelColor
                    ])
                    return true
                }
                ScreenshotEditorWindowController.shared.show(image: image, sourceRect: NSRect(origin: .zero, size: size))
                ScreenshotEditorWindowController.shared.addSampleAnnotationsForTesting(selectedIndex: 5)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    ScreenshotEditorWindowController.shared.openInlineTextForTesting(index: 5)
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.openSettings"), object: nil, queue: .main) { [weak self] notif in
            let tabName = notif.userInfo?["tab"] as? String ?? (notif.object as? String ?? "")
            Task { @MainActor in
                self?.openSettings()
                if let tab = SettingsTab(rawValue: tabName) {
                    SettingsUIState.shared.selectedTab = tab
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.switchTab"), object: nil, queue: .main) { notif in
            let tabName = notif.userInfo?["tab"] as? String ?? (notif.object as? String ?? "")
            Task { @MainActor in
                if let tab = SettingsTab(rawValue: tabName) {
                    SettingsUIState.shared.selectedTab = tab
                }
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.triggerSwitcher"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.triggerSwitcher()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.testOCRToast"), object: nil, queue: .main) { notif in
            let text = notif.userInfo?["text"] as? String ?? "Active Screen Targeting Only: •\nThe tool detects whichever display your mouse cursor is currently on and operates locally."
            let initialCut = (notif.userInfo?["cut"] as? String) == "true"
            Task { @MainActor in
                ToastHUDController.shared.showOCRToast(text: text, initialCut: initialCut)
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.dismissSwitcher"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                SwitcherState.shared.dismiss()
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.testSwitcherIcons"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.showSampleSwitcherForTesting(style: .icons)
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.testSwitcherTitles"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.showSampleSwitcherForTesting(style: .titles)
            }
        }
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.testSwitcherCards"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.showSampleSwitcherForTesting(style: .cards)
            }
        }
    }

    private func showSampleSwitcherForTesting(style: SwitcherStyle) {
        SettingsManager.shared.switcherStyle = style
        let ws = NSWorkspace.shared
        let samples: [(app: String, title: String, bundle: String, hidden: Bool)] = [
            ("Terminal", "Screenshoty bettercm | web", "com.apple.Terminal", true),
            ("Messages", "Friends - Messages", "com.apple.MobileSMS", true),
            ("Safari", "BetterCmdTab — A Better Cmd+Tab Window Switcher", "com.apple.Safari", true),
            ("Notes", "performance.md (Working Tree)", "com.apple.Notes", true),
            ("Finder", "WindowSwitcher", "com.apple.finder", true),
            ("Mail", "Mail", "com.apple.mail", true),
            ("Music", "Music", "com.apple.Music", false)
        ]

        SwitcherState.shared.windows = samples.enumerated().map { idx, item in
            let icon = ws.urlForApplication(withBundleIdentifier: item.bundle)
                .map { ws.icon(forFile: $0.path) }
                ?? NSImage(systemSymbolName: "app.fill", accessibilityDescription: nil)
            return SwitcherWindow(
                id: CGWindowID(9000 + idx),
                pid: pid_t(9000 + idx),
                appName: item.app,
                windowTitle: item.title,
                appIcon: icon,
                bounds: NSRect(x: 0, y: 0, width: 1000, height: 700),
                isMinimized: false,
                isHidden: item.hidden
            )
        }
        SwitcherState.shared.searchText = ""
        SwitcherState.shared.selectedIndex = 1
        SwitcherState.shared.isVisible = true
        showOverlay()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Window Switcher")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Trigger Switcher", action: #selector(triggerSwitcher), keyEquivalent: ""))
        let ocrItem = NSMenuItem(title: "Capture Text from Screen...", action: #selector(captureTextFromScreen), keyEquivalent: "w")
        ocrItem.keyEquivalentModifierMask = [.option]
        menu.addItem(ocrItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesAction), keyEquivalent: "u"))
        menu.addItem(NSMenuItem(title: "Welcome & Setup Guide...", action: #selector(openOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Window Switcher", action: #selector(quitApp), keyEquivalent: "q"))

        item.menu = menu
        self.statusItem = item
    }

    private func setupOverlayPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 350),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false

        let contentView = SwitcherOverlayView(state: SwitcherState.shared)
        panel.contentView = NSHostingView(rootView: contentView)

        self.overlayPanel = panel
    }

    public func showPreview(for window: SwitcherWindow?) {
        guard SettingsManager.shared.previewSelectedWindow, let win = window else { return }
        PreviewPanel.shared.show(for: win, relativeTo: overlayPanel?.windowNumber ?? 0)
    }

    public func updatePreview(for window: SwitcherWindow?) {
        guard SettingsManager.shared.previewSelectedWindow, let win = window else { return }
        PreviewPanel.shared.update(for: win, relativeTo: overlayPanel?.windowNumber ?? 0)
    }

    public func hidePreview() {
        PreviewPanel.shared.hide()
    }

    public func toggleStatusItem(_ show: Bool) {
        if show {
            if statusItem == nil {
                setupStatusItem()
            }
        } else {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    public func showOverlay() {
        guard let panel = overlayPanel else { return }

        let screen: NSScreen
        switch SettingsManager.shared.screenPlacement {
        case .activeScreen, .allScreens:
            screen = NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        case .cursorScreen:
            let mouseLoc = NSEvent.mouseLocation
            screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens.first ?? NSScreen()
        case .primaryScreen:
            screen = NSScreen.screens.first ?? NSScreen.main ?? NSScreen()
        }

        let screenRect = screen.visibleFrame
        let count = max(1, SwitcherState.shared.filteredWindows.count)
        let cardSize = SettingsManager.shared.cardSize
        let searchExtra: CGFloat = SwitcherState.shared.searchText.isEmpty ? 0 : 44

        let gridW: CGFloat
        let gridH: CGFloat

        switch SettingsManager.shared.switcherStyle {
        case .titles:
            let rows = min(count, 14)
            gridW = 500 + 16
            gridH = CGFloat(rows) * 31 + CGFloat(max(0, rows - 1)) * 2 + 16 + searchExtra + (SwitcherState.shared.searchText.isEmpty ? 0 : 6)

        case .cards:
            let cols = count <= 2 ? max(1, count) : (count <= 8 ? 2 : 3)
            let rows = max(1, Int(ceil(Double(count) / Double(cols))))
            gridW = CGFloat(cols) * 226 + CGFloat(max(0, cols - 1)) * 10 + 36
            gridH = CGFloat(rows) * 64 + CGFloat(max(0, rows - 1)) * 10 + 36 + searchExtra

        case .icons:
            let stepW = cardSize.iconSlotWidth + 10
            let limit = max(5, min(10, Int(1120.0 / stepW)))
            let rows = count <= limit ? 1 : 2
            let perRow = count <= limit ? count : (count + 1) / 2
            gridW = CGFloat(perRow) * cardSize.iconSlotWidth + CGFloat(max(0, perRow - 1)) * 10 + 44
            gridH = CGFloat(rows) * cardSize.iconSlotHeight + CGFloat(max(0, rows - 1)) * 12 + 32 + searchExtra

        case .thumbnails:
            let cardH = cardSize.cardHeight
            let maxCardW = cardH * 1.55 + 16
            let rows = count <= 5 ? 1 : 2
            let perRow = count <= 5 ? count : (count + 1) / 2
            gridW = CGFloat(perRow) * maxCardW + CGFloat(max(0, perRow - 1)) * 12 + 36
            gridH = CGFloat(rows) * cardH + CGFloat(max(0, rows - 1)) * 12 + 36 + searchExtra
        }

        // Outer padding for drop shadows (generous margins so shadow decays completely to zero with zero clipping)
        let outerPaddingW: CGFloat = 90 * 2
        let outerPaddingH: CGFloat = 70 + 110
        let targetW = gridW + outerPaddingW
        let targetH = gridH + outerPaddingH

        let totalW = min(targetW, screenRect.width - 40)
        let totalH = min(targetH, screenRect.height - 40)

        // Set size and center dead-center on the target screen
        panel.setContentSize(NSSize(width: totalW, height: totalH))
        let originX = screenRect.origin.x + (screenRect.width - totalW) / 2
        let originY = screenRect.origin.y + (screenRect.height - totalH) / 2
        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        panel.orderFrontRegardless()

        if PreviewPanel.shared.isVisible {
            PreviewPanel.shared.order(.below, relativeTo: panel.windowNumber)
        }
    }

    public func hideOverlay() {
        overlayPanel?.orderOut(nil)
    }

    @objc public func triggerSwitcher() {
        SwitcherState.shared.show()
    }

    @objc public func captureTextFromScreen() {
        Task { @MainActor in
            ScreenOCRCoordinator.shared.startSelection()
        }
    }

    @objc public func checkForUpdatesAction() {
        openSettings()
        SettingsUIState.shared.selectedTab = .general
        UpdateManager.shared.checkForUpdates(userInitiated: true)
    }

    @objc public func openOnboarding() {
        if onboardingWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Welcome to Window Switcher"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(onComplete: { [weak self] in
                self?.onboardingWindow?.close()
                UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
            }))
            self.onboardingWindow = window
        }

        onboardingWindow?.center()
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func openSettings() {
        NSApp.setActivationPolicy(.regular)

        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 840, height: 620),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 780, height: 560)
            window.center()
            window.title = "Window Switcher Preferences"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none
            window.isOpaque = false
            window.backgroundColor = .clear
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false

            let hostingView = NSHostingView(rootView: SettingsView())
            if #available(macOS 26.0, *) {
                hostingView.safeAreaRegions = []
            }
            window.contentView = hostingView

            let delegate = SettingsWindowDelegate(appDelegate: self)
            self.settingsWindowDelegate = delegate
            window.delegate = delegate
            self.settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc public func quitApp() {
        EventTapManager.shared.stop()
        permissionPollTimer?.invalidate()
        NSApp.terminate(nil)
    }
}

final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
