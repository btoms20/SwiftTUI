import Testing
@testable import SwiftTUI

@MainActor
@Suite struct ForEachTests {
    struct Item: Identifiable {
        let id: Int
        var name: String
    }

    struct List: View {
        @State var items: [Item]
        var body: some View {
            HStack {
                Button("Add") { items.append(Item(id: (items.map(\.id).max() ?? 0) + 1, name: "new")) }
                Button("Drop") { items.removeFirst() }
                Button("Rename") { items[0].name = "renamed" }
            }
            ForEach(items) { item in
                Text("\(item.id) \(item.name)")
            }
        }
    }

    @Test func rendersIdentifiableElements() {
        let host = TestHost(List(items: [Item(id: 1, name: "a"), Item(id: 2, name: "b")]))
        #expect(host.text == """
            Add Drop Rename
            1 a
            2 b
            """)
    }

    @Test func insertion() {
        let host = TestHost(List(items: [Item(id: 1, name: "a")]))
        host.send(Key.enter)
        #expect(host.text == """
            Add Drop Rename
            1 a
            2 new
            """)
    }

    @Test func removal() {
        let host = TestHost(List(items: [Item(id: 1, name: "a"), Item(id: 2, name: "b")]))
        host.send(Key.right)
        host.send(Key.enter)
        #expect(host.text == """
            Add Drop Rename
            2 b
            """)
    }

    @Test func updateInPlace() {
        let host = TestHost(List(items: [Item(id: 1, name: "a"), Item(id: 2, name: "b")]))
        host.send(Key.right)
        host.send(Key.right)
        host.send(Key.enter)
        #expect(host.text == """
            Add Drop Rename
            1 renamed
            2 b
            """)
    }

    @Test func keyPathIdentifiers() {
        let host = TestHost {
            ForEach(["x", "y", "z"], id: \.self) { Text($0) }
        }
        #expect(host.text == "x\ny\nz")
    }
}
