@_spi(Testing) @testable import SwiftTUI

/// A minimal terminal emulator that interprets the output of the renderer.
///
/// Only the escape sequences SwiftTUI emits are understood: cursor movement,
/// screen clearing, SGR colors/attributes, and the alternate-buffer and
/// cursor-visibility modes. Anything else is recorded in `unhandledSequences`.
final class VirtualTerminal: TerminalOutput {
    enum TerminalColor: Hashable {
        case `default`
        /// An SGR color code, e.g. 31 for red or 91 for bright red.
        case ansi(Int)
        case xterm(Int)
        case rgb(Int, Int, Int)
    }

    struct Style: Hashable {
        var foreground: TerminalColor = .default
        var background: TerminalColor = .default
        var bold = false
        var italic = false
        var underline = false
        var strikethrough = false
        var inverted = false
    }

    struct Cell: Hashable {
        var character: Character = " "
        var style = Style()
        /// Whether this column is covered by the wide character to its left.
        var isWideContinuation = false
    }

    private(set) var columns: Int
    private(set) var lines: Int
    private(set) var grid: [[Cell]]

    private(set) var cursor = (column: 0, line: 0)
    private(set) var style = Style()
    private(set) var isAlternateBufferEnabled = false
    private(set) var isCursorVisible = true

    /// Every string passed to `write`, in order.
    private(set) var writes: [String] = []
    private(set) var unhandledSequences: [String] = []

    private var parser = Parser.ground

    private enum Parser {
        case ground
        case escape
        case csi(String)
    }

    init(columns: Int, lines: Int) {
        self.columns = columns
        self.lines = lines
        self.grid = Self.blankGrid(columns: columns, lines: lines)
    }

    /// The screen contents with trailing spaces and trailing empty lines removed.
    var text: String {
        var rows = grid.map { row in
            var characters = row.filter { !$0.isWideContinuation }.map(\.character)
            while characters.last == " " { characters.removeLast() }
            return String(characters)
        }
        while rows.last?.isEmpty == true { rows.removeLast() }
        return rows.joined(separator: "\n")
    }

    subscript(column: Int, line: Int) -> Cell {
        grid[line][column]
    }

    /// All bytes written so far, concatenated.
    var output: String { writes.joined() }

    func resize(columns: Int, lines: Int) {
        self.columns = columns
        self.lines = lines
        grid = Self.blankGrid(columns: columns, lines: lines)
        cursor = (0, 0)
    }

    func clearWriteLog() {
        writes.removeAll()
    }

    // MARK: TerminalOutput

    func write(_ string: String) {
        writes.append(string)
        for character in string {
            consume(character)
        }
    }

    // MARK: Parsing

    private func consume(_ character: Character) {
        switch parser {
        case .ground:
            if character == "\u{1b}" {
                parser = .escape
            } else {
                put(character)
            }
        case .escape:
            if character == "[" {
                parser = .csi("")
            } else {
                unhandledSequences.append("ESC \(character)")
                parser = .ground
            }
        case .csi(let parameters):
            // Final bytes of a CSI sequence are in the range @ to ~.
            if let ascii = character.asciiValue, (0x40...0x7e).contains(ascii) {
                parser = .ground
                performCSI(parameters: parameters, final: character)
            } else {
                parser = .csi(parameters + String(character))
            }
        }
    }

    private func put(_ character: Character) {
        guard cursor.line >= 0, cursor.line < lines, cursor.column >= 0, cursor.column < columns else {
            cursor.column += 1
            return
        }
        let (line, column) = (cursor.line, cursor.column)
        // Overwriting either half of a wide character erases the other half, as terminals do.
        if grid[line][column].isWideContinuation, column > 0 {
            grid[line][column - 1] = Cell(style: grid[line][column - 1].style)
        }
        if column + 1 < columns, grid[line][column + 1].isWideContinuation {
            grid[line][column + 1] = Cell(style: grid[line][column + 1].style)
        }

        grid[line][column] = Cell(character: character, style: style)
        cursor.column += 1
        if character.displayWidth > 1, column + 1 < columns {
            grid[line][column + 1] = Cell(character: " ", style: style, isWideContinuation: true)
            cursor.column += 1
        }
    }

    private func performCSI(parameters: String, final: Character) {
        let isPrivate = parameters.hasPrefix("?")
        let numbers = parameters
            .drop(while: { $0 == "?" })
            .split(separator: ";", omittingEmptySubsequences: false)
            .map { Int($0) ?? 0 }

        switch (isPrivate, final) {
        case (false, "H"), (false, "f"):
            let line = numbers.first.map { max($0, 1) } ?? 1
            let column = numbers.dropFirst().first.map { max($0, 1) } ?? 1
            cursor = (column - 1, line - 1)
        case (false, "J") where numbers.first == 2:
            grid = Self.blankGrid(columns: columns, lines: lines)
        case (false, "m"):
            applySGR(numbers.isEmpty ? [0] : numbers)
        case (true, "h"), (true, "l"):
            let enabled = final == "h"
            for mode in numbers {
                switch mode {
                case 1049: isAlternateBufferEnabled = enabled
                case 25: isCursorVisible = enabled
                default: unhandledSequences.append("CSI \(parameters)\(final)")
                }
            }
        default:
            unhandledSequences.append("CSI \(parameters)\(final)")
        }
    }

    private func applySGR(_ codes: [Int]) {
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0: style = Style()
            case 1: style.bold = true
            case 22: style.bold = false
            case 3: style.italic = true
            case 23: style.italic = false
            case 4: style.underline = true
            case 24: style.underline = false
            case 9: style.strikethrough = true
            case 29: style.strikethrough = false
            case 7: style.inverted = true
            case 27: style.inverted = false
            case 30...37, 90...97: style.foreground = .ansi(code)
            case 39: style.foreground = .default
            case 40...47, 100...107: style.background = .ansi(code - 10)
            case 49: style.background = .default
            case 38, 48:
                // Extended colors: 38;5;n / 38;2;r;g;b (and 48 for background).
                let color: TerminalColor?
                switch codes[safe: index + 1] {
                case 5:
                    color = codes[safe: index + 2].map { .xterm($0) }
                    index += 2
                case 2:
                    if let r = codes[safe: index + 2], let g = codes[safe: index + 3], let b = codes[safe: index + 4] {
                        color = .rgb(r, g, b)
                    } else {
                        color = nil
                    }
                    index += 4
                default:
                    color = nil
                }
                if let color {
                    if code == 38 { style.foreground = color } else { style.background = color }
                }
            default:
                unhandledSequences.append("SGR \(code)")
            }
            index += 1
        }
    }

    private static func blankGrid(columns: Int, lines: Int) -> [[Cell]] {
        Array(repeating: Array(repeating: Cell(), count: max(columns, 0)), count: max(lines, 0))
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
