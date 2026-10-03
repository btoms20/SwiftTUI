import Testing
@testable import SwiftTUI

@MainActor
@Suite struct RenderingTests {
    @Test func text() {
        let host = TestHost { Text("Hello") }
        #expect(host.text == "Hello")
    }

    @Test func entersAlternateBufferAndHidesCursor() {
        let host = TestHost { Text("Hello") }
        #expect(host.terminal.isAlternateBufferEnabled)
        #expect(!host.terminal.isCursorVisible)
        #expect(host.terminal.unhandledSequences.isEmpty)
    }

    @Test func vStackStacksLines() {
        let host = TestHost {
            Text("One")
            Text("Two")
        }
        #expect(host.text == """
            One
            Two
            """)
    }

    @Test func hStackSeparatesWithOneColumnByDefault() {
        let host = TestHost {
            HStack {
                Text("One")
                Text("Two")
            }
        }
        #expect(host.text == "One Two")
    }

    @Test func border() {
        let host = TestHost {
            Text("Hi").border()
        }
        #expect(host.text == """
            ┌──┐
            │Hi│
            └──┘
            """)
    }

    @Test func roundedBorderWithPadding() {
        let host = TestHost {
            Text("Hi").padding(1).border(.rounded)
        }
        #expect(host.text == """
            ╭────╮
            │    │
            │ Hi │
            │    │
            ╰────╯
            """)
    }

    @Test func textAttributes() {
        let host = TestHost {
            Text("B").bold().foregroundColor(.red).background(.blue)
        }
        _ = host.text
        let cell = host.terminal[0, 0]
        #expect(cell.character == "B")
        #expect(cell.style.bold)
        #expect(cell.style.foreground == .ansi(31))
        #expect(cell.style.background == .ansi(34))
    }

    @Test func extendedColors() {
        let host = TestHost {
            HStack(spacing: 0) {
                Text("x").foregroundColor(.xterm(red: 5, green: 0, blue: 0))
                Text("t").foregroundColor(.trueColor(red: 1, green: 2, blue: 3))
            }
        }
        _ = host.text
        #expect(host.terminal[0, 0].style.foreground == .xterm(196))
        #expect(host.terminal[1, 0].style.foreground == .rgb(1, 2, 3))
    }

    @Test func textIsClippedToScreen() {
        let host = TestHost(columns: 5, lines: 1) { Text("Hello, world") }
        #expect(host.text == "Hello")
    }

    @Test func colorComponentBoundsAreInclusive() {
        let host = TestHost {
            HStack(spacing: 0) {
                Text("a").foregroundColor(.xterm(red: 5, green: 5, blue: 5))
                Text("b").foregroundColor(.xterm(white: 23))
                Text("c").foregroundColor(.trueColor(red: 255, green: 0, blue: 255))
            }
        }
        _ = host.text
        #expect(host.terminal[0, 0].style.foreground == .xterm(231))
        #expect(host.terminal[1, 0].style.foreground == .xterm(255))
        #expect(host.terminal[2, 0].style.foreground == .rgb(255, 0, 255))
    }

    @Test func outOfRangeColorComponentsTrap() async {
        await #expect(processExitsWith: .failure) {
            _ = Color.xterm(red: 6, green: 0, blue: 0)
        }
        await #expect(processExitsWith: .failure) {
            _ = Color.xterm(white: 24)
        }
        await #expect(processExitsWith: .failure) {
            _ = Color.trueColor(red: 256, green: 0, blue: 0)
        }
    }
}
