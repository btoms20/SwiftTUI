import Testing
@testable import SwiftTUI

@MainActor
@Suite struct WideCharacterTests {
    @Test func displayWidths() {
        #expect(Character("a").displayWidth == 1)
        #expect(Character("é").displayWidth == 1)
        #expect(Character("日").displayWidth == 2)
        #expect(Character("한").displayWidth == 2)
        #expect(Character("Ａ").displayWidth == 2)
        #expect(Character("🙂").displayWidth == 2)
        #expect(Character("👨‍👩‍👧").displayWidth == 2)
        #expect(Character("❤️").displayWidth == 2)
        #expect(Character("─").displayWidth == 1)
    }

    @Test func wideTextOccupiesTwoColumnsPerCharacter() {
        let host = TestHost {
            HStack(spacing: 0) {
                Text("日本")
                Text("x")
            }
        }
        #expect(host.text == "日本x")
        #expect(host.terminal[4, 0].character == "x")
    }

    @Test func emojiAreMeasuredAsWide() {
        let host = TestHost {
            Text("🙂").border()
        }
        #expect(host.text == """
            ┌──┐
            │🙂│
            └──┘
            """)
    }

    @Test func replacingWideTextWithNarrowText() {
        struct Swap: View {
            @State var wide = true
            var body: some View {
                Button("Swap") { wide = false }
                HStack(spacing: 0) {
                    Text(wide ? "日本" : "abc")
                    Text("|")
                }
            }
        }

        let host = TestHost(Swap())
        #expect(host.text == "Swap\n日本|")
        host.send(Key.enter)
        #expect(host.text == "Swap\nabc|")
    }

    @Test func wideCharacterAtRightEdgeIsNotWrapped() {
        let host = TestHost(columns: 3, lines: 2) {
            HStack(spacing: 0) {
                Text("ab")
                Text("日")
            }
        }
        // A wrapped character would show up on the second line.
        #expect(host.text == "ab")
    }

    @Test func textFieldCursorFollowsWideCharacters() {
        let host = TestHost {
            TextField { _ in }
        }
        host.send("日a")
        _ = host.text
        #expect(host.terminal.text == "日a")
        #expect(host.terminal[3, 0].style.underline)
    }
}

@MainActor
@Suite struct SmallTerminalTests {
    @Test func nestedPaddingAndBordersInTinyTerminal() {
        let host = TestHost(columns: 2, lines: 1) {
            Text("Hello").padding(2).border().border()
        }
        // Only the outer border's top edge fits.
        #expect(host.text == "┌─")
    }

    @Test func emptyTextChanges() {
        struct Blinking: View {
            @State var visible = false
            var body: some View {
                Button("Toggle") { visible.toggle() }
                Text(visible ? "x" : "")
            }
        }

        let host = TestHost(Blinking())
        host.send(Key.enter)
        #expect(host.text == "Toggle\nx")
        host.send(Key.enter)
        #expect(host.text == "Toggle")
    }

    @Test func stacksInZeroSizedWindow() {
        let host = TestHost(columns: 0, lines: 0) {
            VStack {
                Text("a")
                HStack { Text("b"); Spacer(); Text("c") }
            }
            .padding()
        }
        #expect(host.text == "")
    }
}

@MainActor
@Suite struct ScrollViewTests {
    @Test func contentGetsTheFullWidth() {
        let host = TestHost(columns: 5, lines: 1) {
            ScrollView {
                Text("A").frame(maxWidth: .infinity)
            }
        }
        #expect(host.text == "  A")
    }

    @Test func followsFocusDown() {
        let host = TestHost(columns: 10, lines: 3) {
            ScrollView {
                ForEach(0..<10, id: \.self) { Button("Item \($0)") {} }
            }
        }
        #expect(host.text == "Item 0\nItem 1\nItem 2")
        for _ in 0..<5 { host.send(Key.down) }
        #expect(host.text == "Item 3\nItem 4\nItem 5")
        for _ in 0..<5 { host.send(Key.up) }
        #expect(host.text == "Item 0\nItem 1\nItem 2")
    }

    @Test func showsAllOfATallFocusedControl() {
        let host = TestHost(columns: 10, lines: 4) {
            ScrollView {
                Button("One") {}
                Button("Two") {}
                Button { } label: { Text("Tall").border() }
            }
        }
        host.send(Key.down)
        host.send(Key.down)
        #expect(host.text == """
            Two
            ┌────┐
            │Tall│
            └────┘
            """)
    }

    @Test func offsetIsClampedWhenContentShrinks() {
        struct Shrinking: View {
            @State var count = 10
            var body: some View {
                ScrollView {
                    ForEach(0..<count, id: \.self) { index in
                        Button("Item \(index)") { count = 2 }
                    }
                }
            }
        }

        let host = TestHost(columns: 10, lines: 3, Shrinking())
        for _ in 0..<9 { host.send(Key.down) }
        #expect(host.text == "Item 7\nItem 8\nItem 9")
        host.send(Key.enter)
        #expect(host.text == "Item 0\nItem 1")
    }
}

@MainActor
@Suite struct GeometryReaderTests {
    @Test func firstFrameUsesTheRealSize() {
        let host = TestHost(columns: 12, lines: 2) {
            GeometryReader { size in
                Text("\(size.width)x\(size.height)")
            }
        }
        // Read the screen without applying pending updates.
        #expect(host.terminal.text == "12x2")
    }

    @Test func updatesOnResize() {
        let host = TestHost(columns: 12, lines: 2) {
            GeometryReader { size in
                Text("\(size.width)x\(size.height)")
            }
        }
        host.resize(columns: 8, lines: 3)
        #expect(host.text == "8x3")
    }
}

@MainActor
@Suite struct SpatialFocusTests {
    final class Log {
        var pressed: [String] = []
    }

    private func grid(_ log: Log) -> TestHost {
        TestHost {
            HStack {
                Button("A") { log.pressed.append("A") }
                Button("B") { log.pressed.append("B") }
            }
            HStack {
                Button("C") { log.pressed.append("C") }
                Button("D") { log.pressed.append("D") }
            }
        }
    }

    @Test func downKeepsTheColumn() {
        let log = Log()
        let host = grid(log)
        host.send(Key.right + Key.down + Key.enter)
        #expect(log.pressed == ["D"])
    }

    @Test func leftAndUpNavigateBack() {
        let log = Log()
        let host = grid(log)
        host.send(Key.right + Key.down + Key.left + Key.up + Key.enter)
        #expect(log.pressed == ["A"])
    }

    @Test func tabCyclesInOrder() {
        let log = Log()
        let host = grid(log)
        for _ in 0..<5 {
            host.send(Key.enter + Key.tab)
        }
        #expect(log.pressed == ["A", "B", "C", "D", "A"])
    }

    @Test func shiftTabGoesBackwards() {
        let log = Log()
        let host = grid(log)
        host.send(Key.shiftTab + Key.enter + Key.shiftTab + Key.enter)
        #expect(log.pressed == ["D", "C"])
    }

    @Test func downFromARowPicksTheOverlappingControl() {
        let log = Log()
        let host = TestHost(columns: 20, lines: 5) {
            HStack {
                Button("Left") { log.pressed.append("Left") }
                Spacer()
                Button("Right") { log.pressed.append("Right") }
            }
            HStack {
                Spacer()
                Button("Below right") { log.pressed.append("Below right") }
            }
        }
        host.send(Key.right + Key.down + Key.enter)
        #expect(log.pressed == ["Below right"])
    }
}
