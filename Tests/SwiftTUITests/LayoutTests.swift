import Testing
@testable import SwiftTUI

@MainActor
@Suite struct LayoutTests {
    @Test func fixedFrameDefaultsToTopLeading() {
        let host = TestHost {
            Text("A").frame(width: 3, height: 2).border()
        }
        #expect(host.text == """
            ┌───┐
            │A  │
            │   │
            └───┘
            """)
    }

    @Test func fixedFrameAlignment() {
        let host = TestHost {
            Text("A").frame(width: 3, height: 3, alignment: .bottomTrailing).border()
        }
        #expect(host.text == """
            ┌───┐
            │   │
            │   │
            │  A│
            └───┘
            """)
    }

    @Test func flexibleFrameFillsAndCenters() {
        let host = TestHost(columns: 5, lines: 1) {
            Text("A").frame(maxWidth: .infinity)
        }
        #expect(host.text == "  A")
    }

    @Test func vStackAlignment() {
        let host = TestHost {
            VStack(alignment: .trailing) {
                Text("A")
                Text("BBB")
            }
        }
        #expect(host.text == """
              A
            BBB
            """)
    }

    @Test func vStackSpacing() {
        let host = TestHost {
            VStack(spacing: 1) {
                Text("A")
                Text("B")
            }
        }
        #expect(host.text == """
            A

            B
            """)
    }

    @Test func spacerPushesApart() {
        let host = TestHost(columns: 10, lines: 1) {
            HStack {
                Text("A")
                Spacer()
                Text("B")
            }
        }
        #expect(host.text == "A        B")
    }

    @Test func zStackOverlaysLaterChildren() {
        let host = TestHost {
            ZStack {
                Text("abc")
                Text("X")
            }
        }
        #expect(host.text == "Xbc")
    }

    @Test func dividerSpansStackWidth() {
        let host = TestHost(columns: 5, lines: 3) {
            VStack {
                Text("A")
                Divider()
                Text("B")
            }
            .frame(maxWidth: .infinity)
        }
        #expect(host.text == """
            A
            ─────
            B
            """)
    }

    @Test func geometryReaderReportsProposedSize() {
        let host = TestHost(columns: 12, lines: 2) {
            GeometryReader { size in
                Text("\(size.width)x\(size.height)")
            }
        }
        #expect(host.text == "12x2")
    }

    @Test func resizeRelaysOut() {
        let host = TestHost(columns: 5, lines: 1) {
            Text("A").frame(maxWidth: .infinity)
        }
        #expect(host.text == "  A")
        host.resize(columns: 9, lines: 1)
        #expect(host.text == "    A")
    }
}
