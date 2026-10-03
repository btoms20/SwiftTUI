import Foundation

public struct TextField: View, PrimitiveView {
    public let placeholder: String?
    public let action: @MainActor (String) -> Void

    @Environment(\.placeholderColor) private var placeholderColor: Color

    public init(placeholder: String? = nil, action: @escaping @MainActor (String) -> Void) {
        self.placeholder = placeholder
        self.action = action
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.control = TextFieldControl(placeholder: placeholder ?? "", placeholderColor: placeholderColor, action: action)
    }

    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.control as! TextFieldControl
        control.action = action
        let placeholder = placeholder ?? ""
        if control.placeholder != placeholder || control.placeholderColor != placeholderColor {
            control.placeholder = placeholder
            control.placeholderColor = placeholderColor
            control.layer.invalidate()
        }
    }

    private class TextFieldControl: Control {
        var placeholderColor: Color
        var action: @MainActor (String) -> Void

        var placeholder: String {
            didSet { placeholderColumns = Self.columns(for: placeholder) }
        }
        private var placeholderColumns: [Character?]

        private var text: [Character] = [] {
            didSet { textColumns = Self.columns(for: text) }
        }
        private var textColumns: [Character?] = []

        /// The index in `text` that typed characters are inserted at.
        private var cursor = 0 {
            didSet { cursorColumn = text[..<cursor].reduce(0) { $0 + $1.displayWidth } }
        }

        /// The terminal column the cursor is drawn in.
        private var cursorColumn = 0

        init(placeholder: String, placeholderColor: Color, action: @escaping @MainActor (String) -> Void) {
            self.placeholder = placeholder
            self.placeholderColumns = Self.columns(for: placeholder)
            self.placeholderColor = placeholderColor
            self.action = action
        }

        /// Characters laid out one per terminal column; `nil` marks the column
        /// covered by the right half of a wide character.
        private static func columns(for characters: some Sequence<Character>) -> [Character?] {
            var columns: [Character?] = []
            for character in characters {
                columns.append(character)
                if character.displayWidth > 1 { columns.append(nil) }
            }
            return columns
        }

        override func size(proposedSize: Size) -> Size {
            // One extra column for the cursor after the last character.
            return Size(width: Extended(max(textColumns.count, placeholderColumns.count)) + 1, height: 1)
        }

        override func handle(_ event: KeyEvent) -> Bool {
            if let character = event.text {
                text.insert(character, at: cursor)
                cursor += 1
                layer.invalidate()
                return true
            }

            guard event.modifiers.isEmpty else { return false }
            switch event.key {
            case .enter:
                action(String(text))
                text = []
                cursor = 0
            case .backspace:
                guard cursor > 0 else { return true }
                cursor -= 1
                text.remove(at: cursor)
            case .delete:
                guard cursor < text.count else { return true }
                text.remove(at: cursor)
            case .left:
                // At the edges, let the arrow keys move focus instead.
                guard cursor > 0 else { return false }
                cursor -= 1
            case .right:
                guard cursor < text.count else { return false }
                cursor += 1
            case .home:
                cursor = 0
            case .end:
                cursor = text.count
            default:
                return false
            }
            layer.invalidate()
            return true
        }

        override func cell(at position: Position) -> Cell? {
            guard position.line == 0 else { return nil }
            let column = position.column.intValue
            let isCursor = isFirstResponder && column == cursorColumn
            let attributes = CellAttributes(underline: isCursor)

            let columns = text.isEmpty ? placeholderColumns : textColumns
            let color = text.isEmpty ? placeholderColor : .default
            guard column >= 0, column < columns.count else {
                return Cell(char: " ", attributes: attributes)
            }
            guard let character = columns[column] else {
                return Cell(char: " ", foregroundColor: color).continuation()
            }
            return Cell(char: character, foregroundColor: color, attributes: attributes)
        }

        override var selectable: Bool { true }

        override func becomeFirstResponder() {
            super.becomeFirstResponder()
            layer.invalidate()
        }

        override func resignFirstResponder() {
            super.resignFirstResponder()
            layer.invalidate()
        }
    }
}

extension EnvironmentValues {
    public var placeholderColor: Color {
        get { self[PlaceholderColorEnvironmentKey.self] }
        set { self[PlaceholderColorEnvironmentKey.self] = newValue }
    }
}

private struct PlaceholderColorEnvironmentKey: EnvironmentKey {
    static var defaultValue: Color { .default }
}
