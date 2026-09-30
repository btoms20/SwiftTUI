import Testing
@testable import SwiftTUI

@MainActor
@Suite struct FocusTests {
    final class Log {
        var entries: [String] = []
    }

    /// Whether the first cell of `line` is drawn highlighted, which is how a
    /// focused button is rendered.
    private func isHighlighted(_ host: TestHost, column: Int = 0, line: Int) -> Bool {
        _ = host.text
        return host.terminal[column, line].style.inverted
    }

    @Test func firstButtonIsFocusedInitially() {
        let host = TestHost {
            Button("One") {}
            Button("Two") {}
        }
        #expect(isHighlighted(host, line: 0))
        #expect(!isHighlighted(host, line: 1))
    }

    @Test func arrowDownMovesFocus() {
        let log = Log()
        let host = TestHost {
            Button("One") { log.entries.append("one") }
            Button("Two") { log.entries.append("two") }
        }
        host.send(Key.down)
        #expect(!isHighlighted(host, line: 0))
        #expect(isHighlighted(host, line: 1))
        host.send(Key.enter)
        #expect(log.entries == ["two"])
    }

    @Test func arrowUpAtTopKeepsFocus() {
        let host = TestHost {
            Button("One") {}
            Button("Two") {}
        }
        host.send(Key.up)
        #expect(isHighlighted(host, line: 0))
    }

    @Test func arrowRightMovesFocusInHStack() {
        let log = Log()
        let host = TestHost {
            HStack {
                Button("A") { log.entries.append("a") }
                Button("B") { log.entries.append("b") }
            }
        }
        host.send(Key.right)
        host.send(Key.enter)
        #expect(log.entries == ["b"])
        #expect(isHighlighted(host, column: 2, line: 0))
    }

    @Test func focusSkipsNonSelectableViews() {
        let log = Log()
        let host = TestHost {
            Button("One") { log.entries.append("one") }
            Text("Label")
            Button("Two") { log.entries.append("two") }
        }
        host.send(Key.down)
        host.send(Key.enter)
        #expect(log.entries == ["two"])
    }

    @Test func hoverCallbackFiresOnFocus() {
        let log = Log()
        let host = TestHost {
            Button("One", hover: { log.entries.append("hover one") }) {}
            Button("Two", hover: { log.entries.append("hover two") }) {}
        }
        host.send(Key.down)
        #expect(log.entries.last == "hover two")
    }
}
