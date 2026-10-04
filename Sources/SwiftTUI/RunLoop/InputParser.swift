/// Turns the bytes a terminal sends into key events.
///
/// Understands UTF-8 text, control characters, and the common CSI (`ESC [`) and
/// SS3 (`ESC O`) sequences for arrows, navigation and function keys, including
/// modifiers. Unrecognized sequences are dropped rather than typed.
struct InputParser {
    private enum State {
        case ground
        /// After ESC, waiting to see whether a sequence follows.
        case escape
        case csi(parameters: String)
        case ss3
    }

    private var state = State.ground

    /// Bytes at the end of the last chunk that don't form a complete UTF-8 character yet.
    private var incompleteUTF8: [UInt8] = []

    /// Whether a lone ESC is waiting to be resolved: it may start a sequence
    /// whose remainder hasn't arrived, or be the Escape key itself.
    var hasPendingEscape: Bool {
        if case .escape = state { return true }
        return false
    }

    /// Parses raw bytes read from the terminal.
    mutating func parse(_ bytes: some Collection<UInt8>) -> [KeyEvent] {
        var bytes = incompleteUTF8 + bytes
        incompleteUTF8 = Self.removeIncompleteSuffix(from: &bytes)
        return parse(String(decoding: bytes, as: UTF8.self))
    }

    /// Parses already-decoded input.
    mutating func parse(_ string: String) -> [KeyEvent] {
        var events: [KeyEvent] = []
        var text = String.UnicodeScalarView()

        // Printable scalars are collected and split into characters together,
        // so multi-scalar characters such as emoji stay intact.
        func flushText() {
            for character in String(text) {
                events.append(KeyEvent(.character(character)))
            }
            text.removeAll()
        }

        for scalar in string.unicodeScalars {
            if case .ground = state, !Self.isControl(scalar) {
                text.append(scalar)
                continue
            }
            flushText()
            if let event = consume(scalar) {
                events.append(event)
            }
        }
        flushText()
        return events
    }

    /// Resolves a pending ESC as the Escape key, once no more input has arrived for a moment.
    mutating func flushPendingEscape() -> KeyEvent? {
        guard hasPendingEscape else { return nil }
        state = .ground
        return KeyEvent(.escape)
    }

    // MARK: - State machine

    private mutating func consume(_ scalar: Unicode.Scalar) -> KeyEvent? {
        switch state {
        case .ground:
            return consumeControl(scalar)

        case .escape:
            switch scalar {
            case "[":
                state = .csi(parameters: "")
                return nil
            case "O":
                state = .ss3
                return nil
            case "\u{1b}":
                // A second ESC: the first was the Escape key.
                return KeyEvent(.escape)
            default:
                // ESC followed by a key is how terminals send Option/Alt.
                state = .ground
                var event = consumeControl(scalar) ?? KeyEvent(.character(Character(scalar)))
                event.modifiers.insert(.option)
                return event
            }

        case .csi(let parameters):
            // Parameter and intermediate bytes, then a final byte in @...~.
            if (0x20...0x3f).contains(scalar.value) {
                state = .csi(parameters: parameters + String(scalar))
                return nil
            }
            state = .ground
            guard (0x40...0x7e).contains(scalar.value) else { return nil }
            return Self.csiEvent(parameters: parameters, final: scalar)

        case .ss3:
            state = .ground
            return Self.ss3Event(final: scalar)
        }
    }

    /// Handles a scalar in the ground state that isn't printable text.
    private mutating func consumeControl(_ scalar: Unicode.Scalar) -> KeyEvent? {
        switch scalar.value {
        case 0x1b:
            state = .escape
            return nil
        case 0x0d, 0x0a:
            return KeyEvent(.enter)
        case 0x09:
            return KeyEvent(.tab)
        case 0x7f, 0x08:
            return KeyEvent(.backspace)
        case 0x00:
            return KeyEvent(.character(" "), modifiers: .control)
        case 0x01...0x1a:
            // Ctrl-A through Ctrl-Z.
            let letter = Character(Unicode.Scalar(scalar.value + 0x60)!)
            return KeyEvent(.character(letter), modifiers: .control)
        case 0x1c...0x1f, 0x80...0x9f:
            return nil
        default:
            return KeyEvent(.character(Character(scalar)))
        }
    }

    private static func csiEvent(parameters: String, final: Unicode.Scalar) -> KeyEvent? {
        // Private sequences (e.g. mouse reports, `ESC [ < ...`) aren't key presses.
        guard parameters.first.map({ $0.isNumber || $0 == ";" }) ?? true else { return nil }

        let numbers = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }
        let first = numbers.first.flatMap { $0 }
        let modifiers = KeyEvent.Modifiers(csiParameter: numbers.dropFirst().first.flatMap { $0 } ?? 1)

        let key: KeyEvent.Key
        switch final {
        case "A": key = .up
        case "B": key = .down
        case "C": key = .right
        case "D": key = .left
        case "H": key = .home
        case "F": key = .end
        case "Z": return KeyEvent(.backTab)
        case "~":
            guard let first, let tildeKey = tildeKeys[first] else { return nil }
            key = tildeKey
        default:
            return nil
        }
        return KeyEvent(key, modifiers: modifiers)
    }

    private static func ss3Event(final: Unicode.Scalar) -> KeyEvent? {
        switch final {
        case "A": KeyEvent(.up)
        case "B": KeyEvent(.down)
        case "C": KeyEvent(.right)
        case "D": KeyEvent(.left)
        case "H": KeyEvent(.home)
        case "F": KeyEvent(.end)
        case "P": KeyEvent(.function(1))
        case "Q": KeyEvent(.function(2))
        case "R": KeyEvent(.function(3))
        case "S": KeyEvent(.function(4))
        default: nil
        }
    }

    /// Keys sent as `ESC [ <number> ~`.
    private static let tildeKeys: [Int: KeyEvent.Key] = [
        1: .home, 7: .home,
        4: .end, 8: .end,
        2: .insert,
        3: .delete,
        5: .pageUp,
        6: .pageDown,
        11: .function(1), 12: .function(2), 13: .function(3), 14: .function(4),
        15: .function(5), 17: .function(6), 18: .function(7), 19: .function(8),
        20: .function(9), 21: .function(10), 23: .function(11), 24: .function(12),
    ]

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value < 0x20 || (0x7f...0x9f).contains(scalar.value)
    }

    // MARK: - UTF-8

    /// Removes and returns trailing bytes that start a UTF-8 sequence without finishing it.
    private static func removeIncompleteSuffix(from bytes: inout [UInt8]) -> [UInt8] {
        // A sequence is at most 4 bytes, so only the last 3 can be an unfinished one.
        for length in stride(from: 1, through: min(3, bytes.count), by: 1) {
            let byte = bytes[bytes.count - length]
            // Continuation bytes (10xxxxxx) belong to an earlier lead byte.
            if byte & 0b1100_0000 == 0b1000_0000 { continue }
            let expected: Int
            switch byte {
            case 0b1100_0000...0b1101_1111: expected = 2
            case 0b1110_0000...0b1110_1111: expected = 3
            case 0b1111_0000...0b1111_0111: expected = 4
            default: expected = 1
            }
            guard expected > length else { return [] }
            let suffix = Array(bytes.suffix(length))
            bytes.removeLast(length)
            return suffix
        }
        return []
    }
}
