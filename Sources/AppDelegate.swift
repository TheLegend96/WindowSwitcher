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
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.custom.windowswitcher.dismissSwitcher"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                SwitcherState.shared.dismiss()
            }
        }
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "macwindow.on.rectangle", accessibilityDescription: "Window Switcher")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Trigger Switcher", action: #selector(triggerSwitcher), keyEquivalent: ""))
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
        let cardH = SettingsManager.shared.cardSize.cardHeight
        let maxCardW = SettingsManager.shared.switcherStyle == .titles ? 280 : (SettingsManager.shared.switcherStyle == .icons ? cardH * 0.95 : cardH * 1.55 + 16)

        let rows: Int
        let perRow: Int
        if SettingsManager.shared.switcherStyle == .titles {
            rows = min(count, 8)
            perRow = 1
        } else {
            rows = count <= 5 ? 1 : 2
            perRow = count <= 5 ? count : (count + 1) / 2
        }

        let gridW = CGFloat(perRow) * maxCardW + CGFloat(max(0, perRow - 1)) * 12 + 36
        let gridH = CGFloat(rows) * cardH + CGFloat(max(0, rows - 1)) * 12 + 36 + (SwitcherState.shared.searchText.isEmpty ? 0 : 44)

        // Outer padding for drop shadows (generous margins so shadow decays completely to zero with zero clipping)
        let outerPaddingW: CGFloat = 90 * 2
        let outerPaddingH: CGFloat = 70 + 110
        let fitting = panel.contentView?.fittingSize ?? NSSize.zero
        let targetW = max(fitting.width, gridW + outerPaddingW)
        let targetH = max(fitting.height, gridH + outerPaddingH)

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
                contentRect: NSRect(x: 0, y: 0, width: 820, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.center()
            window.title = "Window Switcher Preferences"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView())

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
