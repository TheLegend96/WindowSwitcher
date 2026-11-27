import SwiftUI
import AppKit

@MainActor
public class SwitcherState: ObservableObject {
    public static let shared = SwitcherState()

    @Published public var windows: [SwitcherWindow] = []
    @Published public var selectedIndex: Int = 0 {
        didSet {
            guard isVisible else { return }
            refreshSelectedWindowLive()
            AppDelegate.shared?.updatePreview(for: selectedWindow)
        }
    }
    @Published public var searchText: String = ""
    @Published public var isVisible: Bool = false

    public var selectedWindow: SwitcherWindow? {
        let list = filteredWindows
        guard selectedIndex >= 0 && selectedIndex < list.count else { return nil }
        return list[selectedIndex]
    }

    private init() {}

    public var filteredWindows: [SwitcherWindow] {
        if searchText.isEmpty {
            return windows
        }
        let query = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return windows.filter {
            $0.appName.lowercased().contains(query) ||
            $0.windowTitle.lowercased().contains(query)
        }
    }

    public func show() {
        guard !isVisible else { return }
        EventTapManager.shared.isSwitcherActive = true

        // 1. Establish deterministic stable snapshot of windows
        var initialList = WindowEnumerator.shared.cachedWindows
        if initialList.isEmpty {
            // Synchronously query system Z-order if cache empty
            let scWindows = WindowEnumerator.shared.getSystemZOrder()
            if !scWindows.isEmpty {
                WindowEnumerator.shared.prewarmCache()
                initialList = WindowEnumerator.shared.cachedWindows
            }
        }

        // Attach any cached thumbnails
        for win in initialList {
            if win.thumbnail == nil, let thumb = ThumbnailManager.shared.getCachedThumbnail(for: win.id) {
                win.thumbnail = thumb
            }
        }

        self.windows = initialList
        self.searchText = ""
        // Select index 1 (the previous app) on initial Command+Tab, matching macOS behavior
        self.selectedIndex = initialList.count > 1 ? 1 : 0
        self.isVisible = true

        AppDelegate.shared?.showOverlay()
        AppDelegate.shared?.showPreview(for: self.selectedWindow)

        Task {
            let freshList = await WindowEnumerator.shared.getWindows()
            for win in freshList {
                if win.thumbnail == nil, let thumb = ThumbnailManager.shared.getCachedThumbnail(for: win.id) {
                    win.thumbnail = thumb
                }
            }

            await MainActor.run {
                if self.windows.isEmpty {
                    self.windows = freshList
                    self.selectedIndex = freshList.count > 1 ? 1 : 0
                    AppDelegate.shared?.showOverlay()
                    AppDelegate.shared?.showPreview(for: self.selectedWindow)
                } else {
                    // Switcher is ALREADY active: NEVER reorder or swap card positions!
                    // Merge thumbnails and titles in-place:
                    var freshMap: [CGWindowID: SwitcherWindow] = [:]
                    for w in freshList { freshMap[w.id] = w }
                    for existing in self.windows {
                        if let fresh = freshMap[existing.id] {
                            if existing.thumbnail == nil && fresh.thumbnail != nil {
                                existing.thumbnail = fresh.thumbnail
                            }
                            existing.windowTitle = fresh.windowTitle
                        }
                    }
                    AppDelegate.shared?.showOverlay()
                    AppDelegate.shared?.updatePreview(for: self.selectedWindow)
                }
            }

            // Capture screenshots in priority order: active selection first, then adjacent
            let currentSelected = self.selectedIndex
            var priorityList = self.windows
            if currentSelected < priorityList.count {
                let primary = priorityList.remove(at: currentSelected)
                priorityList.insert(primary, at: 0)
            }

            // Live Screen Capture: update all windows with their current live session (selected window first)
            for window in priorityList {
                Task {
                    if let liveThumb = await ThumbnailManager.shared.captureThumbnail(for: window, forceRefresh: true) {
                        await MainActor.run {
                            window.thumbnail = liveThumb
                            window.isCapturing = false
                            if self.selectedWindow?.id == window.id {
                                AppDelegate.shared?.updatePreview(for: window)
                            }
                        }
                    } else {
                        await MainActor.run {
                            window.isCapturing = false
                        }
                    }
                }
            }
        }
    }

    private func refreshSelectedWindowLive() {
        let list = filteredWindows
        guard selectedIndex >= 0 && selectedIndex < list.count else { return }
        let win = list[selectedIndex]
        Task {
            if let liveThumb = await ThumbnailManager.shared.captureThumbnail(for: win, forceRefresh: true) {
                await MainActor.run {
                    win.thumbnail = liveThumb
                }
            }
        }
    }

    public func cycleForward() {
        let list = filteredWindows
        guard !list.isEmpty else { return }
        selectedIndex = (selectedIndex + 1) % list.count
        SettingsManager.shared.triggerSwitchFeedback(isCommit: false)
    }

    public func cycleBackward() {
        let list = filteredWindows
        guard !list.isEmpty else { return }
        selectedIndex = (selectedIndex - 1 + list.count) % list.count
        SettingsManager.shared.triggerSwitchFeedback(isCommit: false)
    }

    public func moveDown() {
        let list = filteredWindows
        guard !list.isEmpty else { return }
        if SettingsManager.shared.switcherStyle == .titles {
            selectedIndex = (selectedIndex + 1) % list.count
            SettingsManager.shared.triggerSwitchFeedback(isCommit: false)
            return
        }
        let count = list.count
        let perRow: Int
        switch SettingsManager.shared.switcherStyle {
        case .titles: perRow = 1
        case .icons: perRow = max(1, count <= 9 ? count : (count + 1) / 2)
        case .cards: perRow = count <= 2 ? count : (count <= 8 ? 2 : 3)
        case .thumbnails: perRow = count <= 5 ? count : (count + 1) / 2
        }
        if selectedIndex + perRow < count {
            selectedIndex += perRow
            SettingsManager.shared.triggerSwitchFeedback(isCommit: false)
        }
    }

    public func moveUp() {
        let list = filteredWindows
        guard !list.isEmpty else { return }
        if SettingsManager.shared.switcherStyle == .titles {
            selectedIndex = (selectedIndex - 1 + list.count) % list.count
            SettingsManager.shared.triggerSwitchFeedback(isCommit: false)
            return
        }
        let count = list.count
        let perRow: Int
        switch SettingsManager.shared.switcherStyle {
        case .titles: perRow = 1
        case .icons: perRow = max(1, count <= 9 ? count : (count + 1) / 2)
        case .cards: perRow = count <= 2 ? count : (count <= 8 ? 2 : 3)
        case .thumbnails: perRow = count <= 5 ? count : (count + 1) / 2
        }
        if selectedIndex - perRow >= 0 {
            selectedIndex -= perRow
            SettingsManager.shared.triggerSwitchFeedback(isCommit: false)
        }
    }

    public func commitSelection() {
        guard isVisible else { return }
        let list = filteredWindows
        let currentIdx = selectedIndex

        SettingsManager.shared.triggerSwitchFeedback(isCommit: true)
        dismiss()

        if currentIdx >= 0 && currentIdx < list.count {
            let targetWindow = list[currentIdx]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                WindowFocusManager.shared.focusWindow(targetWindow)
            }
        }
    }

    public func commitSelection(for targetWindow: SwitcherWindow) {
        guard isVisible else { return }
        SettingsManager.shared.triggerSwitchFeedback(isCommit: true)
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            WindowFocusManager.shared.focusWindow(targetWindow)
        }
    }

    public func dismiss() {
        searchText = ""
        EventTapManager.shared.isSwitcherActive = false
        isVisible = false
        AppDelegate.shared?.hideOverlay()
        AppDelegate.shared?.hidePreview()
    }

    public func closeWindow(at index: Int) {
        let list = filteredWindows
        guard index >= 0 && index < list.count else { return }
        let target = list[index]
        WindowFocusManager.shared.closeWindow(target)
        windows.removeAll { $0.id == target.id }
        if selectedIndex >= filteredWindows.count {
            selectedIndex = max(0, filteredWindows.count - 1)
        }
        if filteredWindows.isEmpty {
            dismiss()
        }
    }
}
