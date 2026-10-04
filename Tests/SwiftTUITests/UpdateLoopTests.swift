import Testing
@_spi(Testing) @testable import SwiftTUI

@MainActor
@Suite struct UpdateLoopTests {
    @Test func invalidationDuringUpdateIsApplied() {
        // Writing state from `body` is discouraged, but must not be lost.
        struct Mirror: View {
            @Binding var mirror: Int
            let value: Int
            var body: some View {
                if mirror != value { mirror = value }
                return EmptyView()
            }
        }
        struct Parent: View {
            @State var count = 0
            @State var mirror = 0
            var body: some View {
                Button("Increment") { count += 1 }
                Text("mirror \(mirror)")
                Mirror(mirror: $mirror, value: count)
            }
        }

        let host = TestHost(Parent())
        host.send(Key.enter)
        #expect(host.text == "Increment\nmirror 1")
    }

    @Test func oneUpdatePassPerStateChange() async {
        struct Counter: View {
            @State var count = 0
            var body: some View {
                Button("Increment \(count)") { count += 1 }
            }
        }

        let host = TestHost(Counter())
        await drainMainQueue()
        let before = host.application.updateCount

        host.application.handleInput(Key.enter)
        await drainMainQueue()
        await drainMainQueue()

        #expect(host.terminal.text == "Increment 1")
        #expect(host.application.updateCount == before + 1)
    }

    @Test func applicationIsReleasedWithItsViews() async {
        weak var application: Application?
        weak var rootControl: Control?
        do {
            let host = TestHost {
                Button("A") {}
                Text("B").padding(1).border().background(.red)
                ForEach(0..<3, id: \.self) { Text("\($0)").frame(width: 2) }
            }
            application = host.application
            rootControl = host.application.rootControl
        }
        // Scheduled updates hold the application until they run.
        await drainMainQueue()
        #expect(application == nil)
        #expect(rootControl == nil)
    }

    @Test func removedControlsAreReleased() async {
        struct Rows: View {
            @State var count = 2
            var body: some View {
                Button("Remove") { count = 1 }
                ForEach(0..<count, id: \.self) { Text("\($0)").padding(.left, 1).border() }
            }
        }

        let host = TestHost(columns: 20, lines: 10, Rows())
        weak var removedRow = host.application.rootControl.children.last
        weak var removedText = removedRow?.children.first?.children.first
        #expect(removedText != nil)

        host.send(Key.enter)
        await drainMainQueue()
        #expect(removedRow == nil)
        #expect(removedText == nil)
    }

    @Test func modifiersWrapEachControlOnce() {
        struct Rows: View {
            @State var count = 1
            var body: some View {
                Button("Add") { count += 1 }
                ForEach(0..<count, id: \.self) { Text("\($0)").padding(.left, 1).border() }
            }
        }

        let host = TestHost(columns: 20, lines: 10, Rows())
        host.send(Key.enter)
        host.send(Key.enter)
        #expect(host.controlTree == """
            → ButtonControl
              → VStackControl
                → TextControl
            → BorderControl
              → PaddingControl
                → TextControl
            → BorderControl
              → PaddingControl
                → TextControl
            → BorderControl
              → PaddingControl
                → TextControl
            """)
    }
}
