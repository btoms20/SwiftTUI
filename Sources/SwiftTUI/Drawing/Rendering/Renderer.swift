import Foundation

@MainActor
final class Renderer {
    var layer: Layer

    /// Even though we only redraw invalidated parts of the screen, terminal
    /// drawing is currently still slow, as it involves moving the cursor
    /// position and printing a character there.
    /// This cache stores the screen content to see if printing is necessary.
    private var cache: [[Cell?]] = []

    /// The current cursor position, which might need to be updated before
    /// printing.
    private var currentPosition: Position = .zero

    private var currentForegroundColor: Color? = nil
    private var currentBackgroundColor: Color? = nil

    private var currentAttributes = CellAttributes()

    weak var application: Application?

    private let output: TerminalOutput

    init(layer: Layer, output: TerminalOutput = StandardOutput()) {
        self.layer = layer
        self.output = output
        setCache()
    }

    /// Draw only the invalidated part of the layer.
    func update() {
        if let invalidated = layer.invalidated {
            draw(rect: invalidated)
            layer.invalidated = nil
        }
    }

    func setCache() {
        cache = .init(repeating: .init(repeating: nil, count: layer.frame.size.width.intValue), count: layer.frame.size.height.intValue)
    }

    /// Draw a specific area, or the entire layer if the area is nil.
    func draw(rect: Rect? = nil) {
        if rect == nil { layer.invalidated = nil }
        let rect = rect ?? Rect(position: .zero, size: layer.frame.size)

        // Only draw the part of `rect` that is on screen.
        let minLine = max(rect.minLine, 0)
        let minColumn = max(rect.minColumn, 0)
        let maxLine = min(rect.maxLine, layer.frame.size.height - 1)
        let maxColumn = min(rect.maxColumn, layer.frame.size.width - 1)
        guard minLine <= maxLine, minColumn <= maxColumn else { return }

        for line in minLine.intValue ... maxLine.intValue {
            for column in minColumn.intValue ... maxColumn.intValue {
                let position = Position(column: Extended(column), line: Extended(line))
                if let cell = layer.cell(at: position) {
                    drawPixel(cell, at: position)
                }
            }
        }
    }

    /// Undoes what ``setup()`` changed, so the shell looks as it did before.
    func stop() {
        write(EscapeSequence.resetAttributes)
        write(EscapeSequence.showCursor)
        write(EscapeSequence.disableAlternateBuffer)
    }

    private func drawPixel(_ cell: Cell, at position: Position) {
        guard position.column >= 0, position.line >= 0, position.column < layer.frame.size.width, position.line < layer.frame.size.height else {
            return
        }
        if cache[position.line.intValue][position.column.intValue] != cell {
            cache[position.line.intValue][position.column.intValue] = cell
            // The terminal filled this column when it drew the wide character before it.
            if cell.isContinuation { return }

            var cell = cell
            var width = cell.char.displayWidth
            // A wide character that doesn't fit on the line would wrap, so draw a space instead.
            if width > 1, position.column + 1 >= layer.frame.size.width {
                cell.char = " "
                width = 1
            }

            if self.currentPosition != position {
                write(EscapeSequence.moveTo(position))
                self.currentPosition = position
            }
            if self.currentForegroundColor != cell.foregroundColor {
                write(cell.foregroundColor.foregroundEscapeSequence)
                self.currentForegroundColor = cell.foregroundColor
            }
            let backgroundColor = cell.backgroundColor ?? .default
            if self.currentBackgroundColor != backgroundColor {
                write(backgroundColor.backgroundEscapeSequence)
                self.currentBackgroundColor = backgroundColor
            }
            self.updateAttributes(cell.attributes)
            write(String(cell.char))
            self.currentPosition.column += Extended(width)
        }
    }

    /// Switches to a cleared alternate screen with a hidden cursor.
    ///
    /// Also used after the process is resumed, when nothing is known about the
    /// terminal's state, so all tracked state is reset.
    func setup() {
        currentPosition = .zero
        currentForegroundColor = nil
        currentBackgroundColor = nil
        currentAttributes = CellAttributes()
        setCache()

        write(EscapeSequence.enableAlternateBuffer)
        write(EscapeSequence.resetAttributes)
        write(EscapeSequence.clearScreen)
        write(EscapeSequence.moveTo(currentPosition))
        write(EscapeSequence.hideCursor)
    }

    private func updateAttributes(_ attributes: CellAttributes) {
        if currentAttributes.bold != attributes.bold {
            if attributes.bold { write(EscapeSequence.enableBold) }
            else { write(EscapeSequence.disableBold) }
        }
        if currentAttributes.italic != attributes.italic {
            if attributes.italic { write(EscapeSequence.enableItalic) }
            else { write(EscapeSequence.disableItalic) }
        }
        if currentAttributes.underline != attributes.underline {
            if attributes.underline { write(EscapeSequence.enableUnderline) }
            else { write(EscapeSequence.disableUnderline) }
        }
        if currentAttributes.strikethrough != attributes.strikethrough {
            if attributes.strikethrough { write(EscapeSequence.enableStrikethrough) }
            else { write(EscapeSequence.disableStrikethrough) }
        }
        if currentAttributes.inverted != attributes.inverted {
            if attributes.inverted { write(EscapeSequence.enableInverted) }
            else { write(EscapeSequence.disableInverted) }
        }
        currentAttributes = attributes
    }

    private func write(_ string: String) {
        output.write(string)
    }

}
