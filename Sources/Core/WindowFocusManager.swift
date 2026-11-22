import AppKit
import ApplicationServices

@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

public class WindowFocusManager {
    public static let shared = WindowFocusManager()

    public func focusWindow(_ window: SwitcherWindow) {
        let pid = window.pid
        print("🎯 WindowFocusManager: Switching to \(window.appName) (PID: \(pid), WinID: \(window.id), Title: \"\(window.windowTitle)\")")

        // Record into MRU history immediately
        WindowEnumerator.shared.recordWindowFocus(window.id)

        guard let app = NSRunningApplication(processIdentifier: pid) else {
            print("⚠️ App not found for PID: \(pid)")
            return
        }

        // 1. Unhide app if hidden
        if app.isHidden {
            app.unhide()
        }

        // 2. Activate application WITHOUT .activateAllWindows so other accounts/profiles aren't dragged forward!
        app.activate()

        // 3. Precision Accessibility Targeting
        let appElem = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(appElem, kAXFrontmostAttribute as CFString, kCFBooleanTrue)

        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef)

        if result == .success, let axWindows = windowsRef as? [AXUIElement] {
            var targetAXWin: AXUIElement?

            // Pass 1: Exact CGWindowID match via _AXUIElementGetWindow (100% precision for multi-profile Chrome)
            for axWin in axWindows {
                var wid: CGWindowID = 0
                if _AXUIElementGetWindow(axWin, &wid) == .success, wid == window.id {
                    targetAXWin = axWin
                    print("🎯 Found exact CGWindowID match: \(wid) for \(window.appName)")
                    break
                }
            }

            // Pass 2: Title equality or substring match
            if targetAXWin == nil {
                for axWin in axWindows {
                    var titleRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef) == .success,
                       let title = titleRef as? String, !title.isEmpty {
                        if title == window.windowTitle ||
                           title.contains(window.windowTitle) ||
                           window.windowTitle.contains(title) {
                            targetAXWin = axWin
                            print("🎯 Found title match: \"\(title)\"")
                            break
                        }
                    }
                }
            }

            // Pass 3: Geometry bounds match
            if targetAXWin == nil {
                for axWin in axWindows {
                    var posRef: CFTypeRef?
                    var sizeRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axWin, kAXPositionAttribute as CFString, &posRef) == .success,
                       AXUIElementCopyAttributeValue(axWin, kAXSizeAttribute as CFString, &sizeRef) == .success,
                       let posVal = posRef, let sizeVal = sizeRef {
                        var pt = CGPoint.zero
                        var sz = CGSize.zero
                        AXValueGetValue(posVal as! AXValue, .cgPoint, &pt)
                        AXValueGetValue(sizeVal as! AXValue, .cgSize, &sz)
                        if abs(pt.x - window.bounds.origin.x) < 30 &&
                           abs(sz.width - window.bounds.width) < 30 &&
                           abs(sz.height - window.bounds.height) < 30 {
                            targetAXWin = axWin
                            print("🎯 Found geometry match: \(pt) \(sz)")
                            break
                        }
                    }
                }
            }

            // Fallback: If only 1 window exists
            if targetAXWin == nil && axWindows.count == 1 {
                targetAXWin = axWindows.first
            }

            if let target = targetAXWin {
                // Unminimize if minimized in Dock
                AXUIElementSetAttributeValue(target, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
                // Set as main window
                AXUIElementSetAttributeValue(target, kAXMainAttribute as CFString, kCFBooleanTrue)
                // Set as focused window
                AXUIElementSetAttributeValue(target, kAXFocusedAttribute as CFString, kCFBooleanTrue)
                // Raise to front
                AXUIElementPerformAction(target, kAXRaiseAction as CFString)
                // Make frontmost window of the app
                AXUIElementSetAttributeValue(appElem, kAXFocusedWindowAttribute as CFString, target)
                print("✅ Exact window raised successfully via Accessibility!")
            } else {
                print("⚠️ Could not locate specific AXWindow, activated app globally.")
            }
        }
    }

    public func closeWindow(_ window: SwitcherWindow) {
        let appElem = AXUIElementCreateApplication(window.pid)
        var windowsRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElem, kAXWindowsAttribute as CFString, &windowsRef)

        if result == .success, let axWindows = windowsRef as? [AXUIElement] {
            for axWin in axWindows {
                var wid: CGWindowID = 0
                let idMatch = _AXUIElementGetWindow(axWin, &wid) == .success && wid == window.id

                var titleMatch = false
                if !idMatch {
                    var titleRef: CFTypeRef?
                    AXUIElementCopyAttributeValue(axWin, kAXTitleAttribute as CFString, &titleRef)
                    let title = titleRef as? String ?? ""
                    titleMatch = (title == window.windowTitle || axWindows.count == 1)
                }

                if idMatch || titleMatch {
                    var closeBtnRef: CFTypeRef?
                    if AXUIElementCopyAttributeValue(axWin, kAXCloseButtonAttribute as CFString, &closeBtnRef) == .success,
                       let closeBtn = closeBtnRef as! AXUIElement? {
                        AXUIElementPerformAction(closeBtn, kAXPressAction as CFString)
                        print("✅ Closed exact window ID \(window.id) via Accessibility button press")
                    }
                    break
                }
            }
        }
    }
}
