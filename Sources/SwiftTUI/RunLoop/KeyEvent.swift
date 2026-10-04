/// A key press decoded from terminal input.
struct KeyEvent: Equatable {
    enum Key: Equatable {
        case character(Character)
        case up, down, left, right
        case home, end, pageUp, pageDown
        case insert
        /// Forward delete.
        case delete
        case backspace
        case tab
        /// Shift-Tab.
        case backTab
        case enter
        case escape
        /// F1 through F12.
        case function(Int)
    }

    struct Modifiers: OptionSet, Hashable {
        let rawValue: UInt8

        static let shift = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)

        /// Decodes the modifier parameter of a CSI sequence, e.g. the `5` in `ESC [ 1 ; 5 A`.
        init(csiParameter: Int) {
            self.init(rawValue: UInt8(clamping: max(csiParameter - 1, 0)) & 0b111)
        }

        init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }

    var key: Key
    var modifiers: Modifiers = []

    init(_ key: Key, modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// The printable character this event inserts into text, if any.
    var text: Character? {
        guard case .character(let character) = key, modifiers.isDisjoint(with: [.control, .option]) else {
            return nil
        }
        return character
    }
}
