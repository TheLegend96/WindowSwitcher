import AppKit
import CoreGraphics
import ScreenCaptureKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

public class WindowEnumerator {
    public static let shared = WindowEnumerator()

    public private(set) var cachedWindows: [SwitcherWindow] = []
    private var isRefreshing = false
    public private(set) var mruHistory: [CGWindowID] = []

    private init() {
        setupWorkspaceObservers()
        Task(priority: .utility) { [weak self] in
            _ = await self?.getWindows()
        }
    }

    public func recordWindowFocus(_ id: CGWindowID) {
        mruHistory.removeAll { $0 == id }
        mruHistory.insert(id, at: 0)
        if mruHistory.count > 100 {
            mruHistory.removeLast()
        }
    }

    public func getSystemZOrder() -> [CGWindowID] {
        guard let infoList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var zOrder: [CGWindowID] = []
        for dict in infoList {
            if let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
               let wid = dict[kCGWindowNumber as String] as? CGWindowID {
                zOrder.append(wid)
            }
        }
        return zOrder
    }

    private func setupWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let notifications: [NSNotification.Name] = [
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification
        ]
        for note in notifications {
            center.addObserver(forName: note, object: nil, queue: .main) { [weak self] _ in
                self?.prewarmCache()
            }
        }
    }

    public func prewarmCache() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task(priority: .utility) { [weak self] in
            defer { self?.isRefreshing = false }
            _ = await self?.getWindows()
        }
    }

    private let utilityBlacklist: Set<String> = [
        "shottr", "monosnap", "dropzone", "hidden bar", "hiddenbar", 
        "raycast", "alfred", "linearmouse", "mac mouse fix", "monitorcontrol", 
        "pentablet", "aura", "cap", "rectangle", "magnet", "bartender", 
        "snagit", "cleanshot", "stats", "istat", "amphetamine", "alttab", 
        "windowswitcher", "autofill", "loginwindow", "panel service", 
        "coreservices", "textinput", "universalcontrol", "windowmanager", 
        "statusindicator", "dock", "spotlight", "control center", 
        "notification center", "universalaccessauthwarn", "securityagent",
        "quicklook", "screen sharing", "systemuiserver", "cursoruiviewservice",
        "themewidgetcontrolviewservice", "sparkle", "updater", "neardrop",
        "near drop", "hand mirror", "handmirror", "linkednotesuiservice"
    ]

    private let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.Spotlight",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.WindowManager",
        "com.apple.loginwindow",
        "com.custom.windowswitcher",
        "me.grishka.NearDrop",
        "net.rafaelconde.Hand-Mirror"
    ]

    public func getWindows() async -> [SwitcherWindow] {
        // Only return key, user-interactive workspace windows
        let windows: [SwitcherWindow]
        if let scWindows = try? await getWindowsViaSCK(), !scWindows.isEmpty {
            windows = scWindows
        } else {
            windows = getWindowsViaCoreGraphics()
        }
        await MainActor.run {
            self.cachedWindows = windows
        }
        return windows
    }

    private func getWindowsViaSCK() async throws -> [SwitcherWindow] {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        var candidateWindows: [SCWindow] = []
        let myPID = ProcessInfo.processInfo.processIdentifier

        let userExceptions = await SettingsManager.shared.excludedAppNames
        let showMinimized = await SettingsManager.shared.showMinimizedWindows
        let showHidden = await SettingsManager.shared.showHiddenWindows
        let orderWindowsBy = await SettingsManager.shared.orderWindowsBy
        let groupWindowsByApp = await SettingsManager.shared.groupWindowsByApp

        for scWin in content.windows {
            guard let app = scWin.owningApplication else { continue }
            if app.processID == myPID { continue }
            if excludedBundleIDs.contains(app.bundleIdentifier) { continue }

            let appName = app.applicationName
            let title = (scWin.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let lowerApp = appName.lowercased()
            let lowerTitle = title.lowercased()

            if utilityBlacklist.contains(where: { lowerApp.contains($0) || lowerTitle.contains($0) }) {
                continue
            }

            // User-configured Exceptions / Blacklist
            if userExceptions.contains(where: { lowerApp == $0.lowercased() || lowerApp.contains($0.lowercased()) }) {
                continue
            }

            // Must be regular app window at layer 0 with realistic workspace size
            guard scWin.windowLayer == 0 else { continue }
            let frame = scWin.frame
            if frame.width < 320 || frame.height < 200 { continue }

            // Filter out phantom background helper windows (e.g. 500x500 off-screen Electron/Chromium dummy windows)
            if !scWin.isOnScreen && title.isEmpty {
                continue
            }
            if !scWin.isOnScreen && frame.width == 500 && frame.height == 500 {
                continue
            }

            let runningApp = NSRunningApplication(processIdentifier: app.processID)
            guard runningApp?.activationPolicy == .regular else { continue }

            // User-configured Minimized / Hidden Filtering
            if !showMinimized && !scWin.isOnScreen {
                continue
            }
            if !showHidden && (runningApp?.isHidden ?? false) {
                continue
            }

            candidateWindows.append(scWin)
        }

        // Sort candidates deterministically by system front-to-back Z-order and MRU history
        let zOrder = getSystemZOrder()
        let zOrderMap = Dictionary(uniqueKeysWithValues: zOrder.enumerated().map { ($0.element, $0.offset) })
        let mruMap = Dictionary(uniqueKeysWithValues: mruHistory.enumerated().map { ($0.element, $0.offset) })

        candidateWindows.sort { a, b in
            let aZ = zOrderMap[a.windowID] ?? 9999
            let bZ = zOrderMap[b.windowID] ?? 9999
            if aZ != bZ {
                return aZ < bZ
            }
            let aMru = mruMap[a.windowID] ?? 9999
            let bMru = mruMap[b.windowID] ?? 9999
            if aMru != bMru {
                return aMru < bMru
            }
            return a.windowID < b.windowID
        }

        var result: [SwitcherWindow] = []
        for scWin in candidateWindows {
            guard let app = scWin.owningApplication else { continue }
            let runningApp = NSRunningApplication(processIdentifier: app.processID)
            let icon = runningApp?.icon
            var title = (scWin.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            // If title is empty, attempt fast Accessibility lookup with strict 30ms timeout
            if title.isEmpty {
                let appElem = AXUIElementCreateApplication(app.processID)
                AXUIElementSetMessagingTimeout(appElem, 0.03)
                var windowsRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                   let axWindows = windowsRef as? [AXUIElement] {
                    for axWin in axWindows {
                        var wid: CGWindowID = 0
                        if _AXUIElementGetWindow(axWin, &wid) == .success, wid == scWin.windowID {
                            var axTitleRef: CFTypeRef?
                            if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &axTitleRef) == .success,
                               let axTitle = axTitleRef as? String, !axTitle.isEmpty {
                                title = axTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            break
                        }
                    }
                }
            }

            let displayTitle = title.isEmpty ? app.applicationName : title
            let window = SwitcherWindow(
                id: scWin.windowID,
                pid: app.processID,
                appName: app.applicationName,
                windowTitle: displayTitle,
                appIcon: icon,
                bounds: scWin.frame,
                isMinimized: !scWin.isOnScreen,
                isHidden: runningApp?.isHidden ?? false,
                scWindow: scWin
            )
            if let cached = ThumbnailManager.shared.getCachedThumbnail(for: scWin.windowID) {
                window.thumbnail = cached
            }
            result.append(window)
        }

        // Disambiguate duplicate titles for the same app (e.g. multiple "New tab" Chrome windows)
        var titleCount: [String: Int] = [:]
        for w in result {
            let key = "\(w.appName):::\(w.windowTitle)"
            titleCount[key, default: 0] += 1
        }

        var titleIndex: [String: Int] = [:]
        for w in result {
            let key = "\(w.appName):::\(w.windowTitle)"
            if let total = titleCount[key], total > 1 {
                let current = titleIndex[key, default: 0] + 1
                titleIndex[key] = current
                w.windowTitle = "\(w.windowTitle) (\(current))"
            }
        }

        return sortWindowsByRecency(result, order: orderWindowsBy, group: groupWindowsByApp)
    }

    private func getWindowsViaCoreGraphics() -> [SwitcherWindow] {
        guard let list = CGWindowListCopyWindowInfo([.excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let myPID = ProcessInfo.processInfo.processIdentifier
        var result: [SwitcherWindow] = []

        for dict in list {
            guard let layer = dict[kCGWindowLayer as String] as? Int, layer == 0,
                  let id = dict[kCGWindowNumber as String] as? CGWindowID,
                  let pid = dict[kCGWindowOwnerPID as String] as? pid_t,
                  pid != myPID,
                  let boundsDict = dict[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
            else { continue }

            let alpha = dict[kCGWindowAlpha as String] as? Double ?? 1.0
            if alpha <= 0.05 { continue }

            let appName = dict[kCGWindowOwnerName as String] as? String ?? ""
            let title = (dict[kCGWindowName as String] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            let lowerApp = appName.lowercased()
            let lowerTitle = title.lowercased()
            if utilityBlacklist.contains(where: { lowerApp.contains($0) || lowerTitle.contains($0) }) {
                continue
            }

            if bounds.width < 300 || bounds.height < 200 { continue }

            let runningApp = NSRunningApplication(processIdentifier: pid)
            guard runningApp?.activationPolicy == .regular else { continue }
            if let bundle = runningApp?.bundleIdentifier, excludedBundleIDs.contains(bundle) { continue }

            let isOnscreen = dict[kCGWindowIsOnscreen as String] as? Bool ?? true
            let icon = runningApp?.icon

            let window = SwitcherWindow(
                id: id,
                pid: pid,
                appName: appName.isEmpty ? (runningApp?.localizedName ?? "App") : appName,
                windowTitle: title.isEmpty ? appName : title,
                appIcon: icon,
                bounds: bounds,
                isMinimized: !isOnscreen,
                isHidden: runningApp?.isHidden ?? false,
                scWindow: nil
            )
            if let cached = ThumbnailManager.shared.getCachedThumbnail(for: id) {
                window.thumbnail = cached
            }
            result.append(window)
        }

        return sortWindowsByRecency(result)
    }

    private func sortWindowsByRecency(_ windows: [SwitcherWindow], order: String = "Most recently used (MRU)", group: Bool = false) -> [SwitcherWindow] {
        var seenIDs = Set<CGWindowID>()
        var unique: [SwitcherWindow] = []
        for w in windows {
            if !seenIDs.contains(w.id) {
                seenIDs.insert(w.id)
                unique.append(w)
            }
        }

        if order == "Application name" {
            unique.sort { $0.appName.localizedCompare($1.appName) == .orderedAscending }
        } else if group {
            var groups: [String: [SwitcherWindow]] = [:]
            var appOrder: [String] = []
            for w in unique {
                if groups[w.appName] == nil {
                    appOrder.append(w.appName)
                }
                groups[w.appName, default: []].append(w)
            }
            var groupedResult: [SwitcherWindow] = []
            for app in appOrder {
                if let wins = groups[app] {
                    groupedResult.append(contentsOf: wins)
                }
            }
            return groupedResult
        }

        return unique
    }
}
