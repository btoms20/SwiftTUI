import Testing
@testable import SwiftTUI

@MainActor
@Suite struct StateTests {
    @Test func buttonActionUpdatesState() {
        struct Counter: View {
            @State var count = 0
            var body: some View {
                Text("Count: \(count)")
                Button("Increment") { count += 1 }
            }
        }

        let host = TestHost(Counter())
        #expect(host.text.hasPrefix("Count: 0"))
        host.send(Key.enter)
        host.send(Key.space)
        #expect(host.text.hasPrefix("Count: 2"))
    }

    @Test func shrinkingTextClearsStaleCharacters() {
        struct Toggler: View {
            @State var long = true
            var body: some View {
                Text(long ? "Long text" : "Hi")
                Button("Toggle") { long.toggle() }
            }
        }

        let host = TestHost(Toggler())
        #expect(host.text == "Long text\nToggle")
        host.send(Key.enter)
        #expect(host.text == "Hi\nToggle")
    }

    @Test func conditionalContentAppearsAndDisappears() {
        struct Conditional: View {
            @State var show = false
            var body: some View {
                Button("Toggle") { show.toggle() }
                if show {
                    Text("Shown")
                } else {
                    Text("Hidden")
                }
            }
        }

        let host = TestHost(Conditional())
        #expect(host.text == "Toggle\nHidden")
        host.send(Key.enter)
        #expect(host.text == "Toggle\nShown")
        host.send(Key.enter)
        #expect(host.text == "Toggle\nHidden")
    }

    @Test func bindingWritesThroughToParent() {
        struct Child: View {
            @Binding var value: Int
            var body: some View {
                Button("Set") { value = 42 }
            }
        }
        struct Parent: View {
            @State var value = 0
            var body: some View {
                Child(value: $value)
                Text("\(value)")
            }
        }

        let host = TestHost(Parent())
        #expect(host.text == "Set\n0")
        host.send(Key.enter)
        #expect(host.text == "Set\n42")
    }

    @Test func environmentValuePropagates() {
        struct Reader: View {
            @Environment(\.testValue) var value
            var body: some View { Text(value) }
        }

        let host = TestHost {
            Reader()
            Reader().environment(\.testValue, "custom")
        }
        #expect(host.text == "default\ncustom")
    }

    @Test func flexibleFrameUpdatesMinimumSize() {
        struct Resizing: View {
            @State var wide = false
            var body: some View {
                // The outer frame proposes a width of 1 to the flexible frame, so
                // only `minWidth` can make it wider. Anything past 3 columns is clipped.
                Text("A")
                    .frame(minWidth: wide ? 5 : 1, maxWidth: 5, alignment: .leading)
                    .border()
                    .frame(width: 3)
                Button("Widen") { wide = true }
            }
        }

        let host = TestHost(Resizing())
        #expect(host.text.hasPrefix("┌─┐"))
        host.send(Key.enter)
        #expect(host.text.hasPrefix("┌──\n"))
    }

    @Test func buttonActionSeesLatestBodyValues() {
        final class Log { var values: [Int] = [] }
        struct Capturing: View {
            let log: Log
            @State var count = 0
            var body: some View {
                // `current` is a plain value, captured fresh on each body evaluation.
                let current = count
                Button("Record") { log.values.append(current) }
                Button("Increment") { count += 1 }
            }
        }

        let log = Log()
        let host = TestHost(Capturing(log: log))
        host.send(Key.down)
        host.send(Key.enter)
        host.send(Key.up)
        host.send(Key.enter)
        #expect(log.values == [1])
    }

    @Test func textFieldPlaceholderUpdates() {
        struct Placeholder: View {
            @State var alternate = false
            var body: some View {
                Button("Swap") { alternate = true }
                TextField(placeholder: alternate ? "Second" : "First") { _ in }
            }
        }

        let host = TestHost(Placeholder())
        #expect(host.text == "Swap\nFirst")
        host.send(Key.enter)
        #expect(host.text == "Swap\nSecond")
    }

    @Test func dividerStyleUpdates() {
        struct Styled: View {
            @State var double = false
            var body: some View {
                Button("Style") { double = true }
                Divider().style(double ? .double : .default)
            }
        }

        let host = TestHost(columns: 5, lines: 2, Styled())
        #expect(host.text == "Style\n─────")
        host.send(Key.enter)
        #expect(host.text == "Style\n═════")
    }
}

private struct TestValueKey: EnvironmentKey {
    static var defaultValue: String { "default" }
}

extension EnvironmentValues {
    fileprivate var testValue: String {
        get { self[TestValueKey.self] }
        set { self[TestValueKey.self] = newValue }
    }
}
