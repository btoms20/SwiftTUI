import Foundation

public struct Text: View, PrimitiveView {
    private var text: String?
    
    private var _attributedText: Any?
    
    @available(macOS 12, *)
    private var attributedText: AttributedString? { _attributedText as? AttributedString }
    
    @Environment(\.foregroundColor) private var foregroundColor: Color
    @Environment(\.bold) private var bold: Bool
    @Environment(\.italic) private var italic: Bool
    @Environment(\.underline) private var underline: Bool
    @Environment(\.strikethrough) private var strikethrough: Bool
    
    public init(_ text: String) {
        self.text = text
    }
    
    @available(macOS 12, *)
    public init(_ attributedText: AttributedString) {
        self._attributedText = attributedText
    }
    
    static var size: Int? { 1 }
    
    func buildNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.control = TextControl(
            text: text,
            attributedText: _attributedText,
            foregroundColor: foregroundColor,
            bold: bold,
            italic: italic,
            underline: underline,
            strikethrough: strikethrough
        )
    }
    
    func updateNode(_ node: Node) {
        setupEnvironmentProperties(node: node)
        node.view = self
        let control = node.control as! TextControl
        let cells = TextControl.cells(
            text: text,
            attributedText: _attributedText,
            foregroundColor: foregroundColor,
            attributes: CellAttributes(bold: bold, italic: italic, underline: underline, strikethrough: strikethrough)
        )
        if control.cells != cells {
            control.cells = cells
            control.layer.invalidate()
        }
    }

    private class TextControl: Control {
        /// One cell per terminal column, so drawing any column is a lookup.
        var cells: [Cell]

        init(
            text: String?,
            attributedText: Any?,
            foregroundColor: Color,
            bold: Bool,
            italic: Bool,
            underline: Bool,
            strikethrough: Bool
        ) {
            cells = Self.cells(
                text: text,
                attributedText: attributedText,
                foregroundColor: foregroundColor,
                attributes: CellAttributes(bold: bold, italic: italic, underline: underline, strikethrough: strikethrough)
            )
        }

        override func size(proposedSize: Size) -> Size {
            return Size(width: Extended(cells.count), height: 1)
        }

        override func cell(at position: Position) -> Cell? {
            guard position.line == 0 else { return nil }
            let column = position.column.intValue
            guard column >= 0, column < cells.count else { return .init(char: " ") }
            return cells[column]
        }

        static func cells(text: String?, attributedText: Any?, foregroundColor: Color, attributes: CellAttributes) -> [Cell] {
            var cells: [Cell] = []

            func append(_ cell: Cell) {
                cells.append(cell)
                // Wide characters also cover the next column.
                if cell.char.displayWidth > 1 {
                    cells.append(cell.continuation())
                }
            }

            if #available(macOS 12, *), let attributedText = attributedText as? AttributedString {
                for run in attributedText.runs {
                    let runAttributes = CellAttributes(
                        bold: run.bold ?? attributes.bold,
                        italic: run.italic ?? attributes.italic,
                        underline: run.underline ?? attributes.underline,
                        strikethrough: run.strikethrough ?? attributes.strikethrough,
                        inverted: run.inverted ?? false
                    )
                    for character in attributedText[run.range].characters {
                        append(Cell(
                            char: character,
                            foregroundColor: run.foregroundColor ?? foregroundColor,
                            backgroundColor: run.backgroundColor,
                            attributes: runAttributes
                        ))
                    }
                }
            } else if let text {
                for character in text {
                    append(Cell(char: character, foregroundColor: foregroundColor, attributes: attributes))
                }
            }
            return cells
        }
    }
}
