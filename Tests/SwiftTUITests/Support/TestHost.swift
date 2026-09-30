@_spi(Testing) @testable import SwiftTUI

/// Runs a view hierarchy against a ``VirtualTerminal`` so tests can inspect
/// what would appear on screen and drive it with synthetic input.
///
/// Updates are processed synchronously: call ``send(_:)`` or ``flush()`` and
/// then read ``text`` or ``terminal``.
@MainActor
final class TestHost {
    let terminal: VirtualTerminal
    let application: Application

    init<V: View>(columns: Int = 20, lines: Int = 5, _ view: V) {
        terminal = VirtualTerminal(columns: columns, lines: lines)
        application = Application(rootView: view, output: terminal)
        application.resize(columns: columns, lines: lines)
    }

    convenience init<V: View>(columns: Int = 20, lines: Int = 5, @ViewBuilder content: () -> V) {
        self.init(columns: columns, lines: lines, content())
    }

    /// The current screen contents, after applying any pending updates.
    var text: String {
        flush()
        return terminal.text
    }

    /// Feeds `input` to the application as keyboard input, then applies the
    /// resulting updates.
    func send(_ input: String) {
        application.handleInput(input)
        flush()
    }

    func flush() {
        application.flushUpdates()
    }

    func resize(columns: Int, lines: Int) {
        terminal.resize(columns: columns, lines: lines)
        application.resize(columns: columns, lines: lines)
    }

    /// The control tree below the root stack, for structural assertions.
    var controlTree: String {
        application.rootControl.children.map(\.treeDescription).joined(separator: "\n")
    }
}

/// Key sequences as a terminal would send them.
enum Key {
    static let up = "\u{1b}[A"
    static let down = "\u{1b}[B"
    static let right = "\u{1b}[C"
    static let left = "\u{1b}[D"
    static let enter = "\n"
    static let space = " "
    static let delete = "\u{7f}"
}
