import AppKit
import CoreGraphics

public class EventTapManager {
    public static let shared = EventTapManager()

    private enum ModifierType {
        case none
        case command
        case option
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var activeModifier: ModifierType = .none
    public var isSwitcherActive: Bool = false

    public var isListening: Bool {
        return eventTap != nil || globalMonitor != nil
    }

    private init() {}

    public func start() {
        stop()

        guard AXIsProcessTrusted() else {
            print("⚠️ EventTapManager: Accessibility permission not granted yet.")
            return
        }

        print("🚀 EventTapManager: Starting keyboard listeners...")

        // 1. Active CGEventTap
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.keyUp.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)

        let observer = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        let callback: CGEventTapCallBack = { proxy, type, event, refcon -> Unmanaged<CGEvent>? in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handleEvent(proxy: proxy, type: type, event: event)
        }

        var tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: observer
        )

        if tap == nil {
            print("cghidEventTap unavailable, using cgSessionEventTap")
            tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(eventMask),
                callback: callback,
                userInfo: observer
            )
        }

        if let tap = tap {
            self.eventTap = tap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("✅ EventTapManager: CGEventTap connected.")
        }

        // 2. Global NSEvent monitor
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            self?.handleGlobalNSEvent(event)
        }
        print("✅ EventTapManager: Global monitor connected.")
    }

    public func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
            eventTap = nil
            runLoopSource = nil
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        activeModifier = .none
        isSwitcherActive = false
    }

    private func handleGlobalNSEvent(_ event: NSEvent) {
        let isCmdHeld = event.modifierFlags.contains(.command)
        let isAltHeld = event.modifierFlags.contains(.option)

        if !isSwitcherActive {
            if event.type == .keyDown && event.keyCode == 48 {
                if isCmdHeld {
                    activeModifier = .command
                    isSwitcherActive = true
                    DispatchQueue.main.async {
                        SwitcherState.shared.show()
                    }
                } else if isAltHeld {
                    activeModifier = .option
                    isSwitcherActive = true
                    DispatchQueue.main.async {
                        SwitcherState.shared.show()
                    }
                }
            }
        } else {
            if event.type == .flagsChanged {
                let released: Bool
                switch activeModifier {
                case .command: released = !isCmdHeld
                case .option:  released = !isAltHeld
                case .none:    released = false
                }
                if released {
                    activeModifier = .none
                    isSwitcherActive = false
                    DispatchQueue.main.async {
                        SwitcherState.shared.commitSelection()
                    }
                }
            }
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isCmdHeld = flags.contains(.maskCommand)
        let isAltHeld = flags.contains(.maskAlternate)
        let isShiftHeld = flags.contains(.maskShift)

        // When Switcher is VISIBLE
        if isSwitcherActive {
            if type == .flagsChanged {
                let released: Bool
                switch activeModifier {
                case .command: released = !isCmdHeld
                case .option:  released = !isAltHeld
                case .none:    released = false
                }

                if released {
                    activeModifier = .none
                    isSwitcherActive = false
                    DispatchQueue.main.async {
                        SwitcherState.shared.commitSelection()
                    }
                    return nil
                }
            }

            if type == .keyDown {
                switch keyCode {
                case 48: // Tab
                    DispatchQueue.main.async {
                        if isShiftHeld {
                            SwitcherState.shared.cycleBackward()
                        } else {
                            SwitcherState.shared.cycleForward()
                        }
                    }
                    return nil

                case 123: // Left Arrow
                    DispatchQueue.main.async {
                        SwitcherState.shared.cycleBackward()
                    }
                    return nil

                case 124: // Right Arrow
                    DispatchQueue.main.async {
                        SwitcherState.shared.cycleForward()
                    }
                    return nil

                case 126: // Up Arrow
                    DispatchQueue.main.async {
                        SwitcherState.shared.moveUp()
                    }
                    return nil

                case 125: // Down Arrow
                    DispatchQueue.main.async {
                        SwitcherState.shared.moveDown()
                    }
                    return nil

                case 13: // W (Close window)
                    DispatchQueue.main.async {
                        SwitcherState.shared.closeWindow(at: SwitcherState.shared.selectedIndex)
                    }
                    return nil

                case 51: // Backspace
                    DispatchQueue.main.async {
                        if !SwitcherState.shared.searchText.isEmpty {
                            SwitcherState.shared.searchText.removeLast()
                        }
                    }
                    return nil

                case 53: // Escape (Cancel)
                    activeModifier = .none
                    isSwitcherActive = false
                    DispatchQueue.main.async {
                        SwitcherState.shared.dismiss()
                    }
                    return nil

                case 36: // Enter / Return
                    activeModifier = .none
                    isSwitcherActive = false
                    DispatchQueue.main.async {
                        SwitcherState.shared.commitSelection()
                    }
                    return nil

                default:
                    // Instant type-to-filter
                    if let characters = event.characters, !characters.isEmpty {
                        let str = characters.trimmingCharacters(in: .controlCharacters)
                        if !str.isEmpty {
                            DispatchQueue.main.async {
                                SwitcherState.shared.searchText += str
                                let filtered = SwitcherState.shared.filteredWindows
                                if SwitcherState.shared.selectedIndex >= filtered.count {
                                    SwitcherState.shared.selectedIndex = max(0, filtered.count - 1)
                                }
                            }
                            return nil
                        }
                    }
                }
            }
        } else {
            // When Switcher is NOT visible:
            if type == .keyDown && keyCode == 48 {
                if isCmdHeld {
                    activeModifier = .command
                    isSwitcherActive = true
                    DispatchQueue.main.async {
                        SwitcherState.shared.show()
                    }
                    return nil
                } else if isAltHeld {
                    activeModifier = .option
                    isSwitcherActive = true
                    DispatchQueue.main.async {
                        SwitcherState.shared.show()
                    }
                    return nil
                }
            }
        }

        return Unmanaged.passRetained(event)
    }
}

private extension CGEvent {
    var characters: String? {
        var length = 0
        keyboardGetUnicodeString(maxStringLength: 0, actualStringLength: &length, unicodeString: nil)
        guard length > 0 else { return nil }
        var chars = [UniChar](repeating: 0, count: length)
        keyboardGetUnicodeString(maxStringLength: length, actualStringLength: &length, unicodeString: &chars)
        return String(utf16CodeUnits: chars, count: length)
    }
}
