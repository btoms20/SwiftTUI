import Dispatch
import Testing
@testable import SwiftTUI

@MainActor
@Suite struct ModifierTests {
    @Test func textStyleAttributes() {
        let host = TestHost {
            HStack(spacing: 0) {
                Text("i").italic()
                Text("u").underline()
                Text("s").strikethrough()
                Text("n")
            }
        }
        _ = host.text
        #expect(host.terminal[0, 0].style.italic)
        #expect(host.terminal[1, 0].style.underline)
        #expect(host.terminal[2, 0].style.strikethrough)
        #expect(host.terminal[3, 0].style == VirtualTerminal.Style())
    }

    @Test func attributesInheritThroughContainers() {
        let host = TestHost {
            VStack {
                Text("a")
                Text("b").bold(false)
            }
            .bold()
        }
        _ = host.text
        #expect(host.terminal[0, 0].style.bold)
        #expect(!host.terminal[0, 1].style.bold)
    }

    @Test func backgroundFillsPaddedArea() {
        let host = TestHost {
            Text("x").padding(1).background(.green)
        }
        #expect(host.text == "\n x")
        for line in 0..<3 {
            for column in 0..<3 {
                #expect(host.terminal[column, line].style.background == .ansi(32))
            }
        }
        #expect(host.terminal[3, 0].style.background == .default)
    }

    @Test func paddingEdges() {
        let host = TestHost {
            Text("x").padding(.left, 3).border()
        }
        #expect(host.text == """
            ┌────┐
            │   x│
            └────┘
            """)
    }

    @Test func borderColor() {
        let host = TestHost {
            Text("x").border(.red)
        }
        _ = host.text
        #expect(host.terminal[0, 0].style.foreground == .ansi(31))
        #expect(host.terminal[1, 1].style.foreground == .default)
    }

    @Test func dividerStyle() {
        let host = TestHost(columns: 3, lines: 1) {
            VStack {
                Divider().style(.double)
            }
            .frame(maxWidth: .infinity)
        }
        #expect(host.text == "═══")
    }

    @Test func onAppearRunsAfterBuild() async {
        final class Flag { var appeared = false }
        let flag = Flag()
        _ = TestHost {
            Text("x").onAppear { flag.appeared = true }
        }
        await drainMainQueue()
        #expect(flag.appeared)
    }

    @Test func placeholderColorFromEnvironment() {
        let host = TestHost {
            TextField(placeholder: "p") { _ in }
                .environment(\.placeholderColor, .blue)
        }
        _ = host.text
        #expect(host.terminal[0, 0].style.foreground == .ansi(34))
    }
}

/// Waits until work already enqueued on the main dispatch queue has run.
@MainActor
func drainMainQueue() async {
    await withCheckedContinuation { continuation in
        DispatchQueue.main.async { continuation.resume() }
    }
}
