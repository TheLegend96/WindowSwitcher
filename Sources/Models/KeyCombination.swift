import AppKit

public struct KeyCombination: Codable, Equatable {
    public var keyCode: UInt16
    public var modifiers: UInt // NSEvent.ModifierFlags rawValue

    public static let defaultOCR = KeyCombination(keyCode: 13, modifiers: NSEvent.ModifierFlags.option.rawValue) // ⌥W
    public static let alternativeOCR = KeyCombination(keyCode: 17, modifiers: NSEvent.ModifierFlags.option.rawValue) // ⌥T

    public init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var modifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: modifiers)
    }

    public var hasCommand: Bool { modifierFlags.contains(.command) }
    public var hasOption: Bool { modifierFlags.contains(.option) }
    public var hasShift: Bool { modifierFlags.contains(.shift) }
    public var hasControl: Bool { modifierFlags.contains(.control) }

    public var keySymbol: String {
        return KeyCombination.keyName(for: keyCode)
    }

    public var keycapTokens: [String] {
        var tokens: [String] = []
        if hasControl { tokens.append("⌃ Control") }
        if hasOption { tokens.append("⌥ Option") }
        if hasShift { tokens.append("⇧ Shift") }
        if hasCommand { tokens.append("⌘ Command") }
        tokens.append(keySymbol)
        return tokens
    }

    public var displayString: String {
        keycapTokens.joined(separator: " + ")
    }

    public func matches(cgFlags: CGEventFlags, keyCode: Int64) -> Bool {
        guard UInt16(keyCode) == self.keyCode else { return false }
        let isCmd = cgFlags.contains(.maskCommand)
        let isAlt = cgFlags.contains(.maskAlternate)
        let isShift = cgFlags.contains(.maskShift)
        let isCtrl = cgFlags.contains(.maskControl)
        return isCmd == hasCommand && isAlt == hasOption && isShift == hasShift && isCtrl == hasControl
    }

    public func matches(nsFlags: NSEvent.ModifierFlags, keyCode: UInt16) -> Bool {
        guard keyCode == self.keyCode else { return false }
        let isCmd = nsFlags.contains(.command)
        let isAlt = nsFlags.contains(.option)
        let isShift = nsFlags.contains(.shift)
        let isCtrl = nsFlags.contains(.control)
        return isCmd == hasCommand && isAlt == hasOption && isShift == hasShift && isCtrl == hasControl
    }

    public static func keyName(for code: UInt16) -> String {
        switch code {
        case 0: return "A"; case 1: return "S"; case 2: return "D"; case 3: return "F"
        case 4: return "H"; case 5: return "G"; case 6: return "Z"; case 7: return "X"
        case 8: return "C"; case 9: return "V"; case 11: return "B"; case 12: return "Q"
        case 13: return "W"; case 14: return "E"; case 15: return "R"; case 16: return "Y"
        case 17: return "T"; case 18: return "1"; case 19: return "2"; case 20: return "3"
        case 21: return "4"; case 22: return "6"; case 23: return "5"; case 24: return "="
        case 25: return "9"; case 26: return "7"; case 27: return "-"; case 28: return "8"
        case 29: return "0"; case 30: return "]"; case 31: return "O"; case 32: return "U"
        case 33: return "["; case 34: return "I"; case 35: return "P"; case 37: return "L"
        case 38: return "J"; case 39: return "'"; case 40: return "K"; case 41: return ";"
        case 42: return "\\"; case 43: return ","; case 44: return "/"; case 45: return "N"
        case 46: return "M"; case 47: return "."; case 49: return "Space"; case 50: return "`"
        case 51: return "⌫"; case 36: return "Return"; case 48: return "Tab"; case 53: return "Esc"
        case 123: return "←"; case 124: return "→"; case 125: return "↓"; case 126: return "↑"
        case 122: return "F1"; case 120: return "F2"; case 99: return "F3"; case 118: return "F4"
        case 96: return "F5"; case 97: return "F6"; case 98: return "F7"; case 100: return "F8"
        default: return "Key #\(code)"
        }
    }
}
