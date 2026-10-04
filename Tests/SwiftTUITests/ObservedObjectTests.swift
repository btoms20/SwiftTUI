#if canImport(Combine)
import Combine
import Testing
@testable import SwiftTUI

@MainActor
@Suite struct ObservedObjectTests {
    final class Model: ObservableObject {
        @Published var value: Int
        init(_ value: Int) { self.value = value }
    }

    struct ModelView: View {
        @ObservedObject var model: Model
        var body: some View {
            Text("\(model.value)")
        }
    }

    @Test func resubscribesWhenObjectChanges() {
        struct Parent: View {
            let first: Model
            let second: Model
            @State var useSecond = false
            var body: some View {
                Button("Swap") { useSecond = true }
                ModelView(model: useSecond ? second : first)
            }
        }

        let first = Model(1)
        let second = Model(20)
        let host = TestHost(Parent(first: first, second: second))
        #expect(host.text == "Swap\n1")

        host.send(Key.enter)
        #expect(host.text == "Swap\n20")

        second.value = 21
        #expect(host.text == "Swap\n21")
    }

    @Test func projectedValueBindsToProperties() {
        struct Setter: View {
            @Binding var value: Int
            var body: some View {
                Button("Set") { value = 7 }
            }
        }
        struct Parent: View {
            @ObservedObject var model: Model
            var body: some View {
                Setter(value: $model.value)
                Text("\(model.value)")
            }
        }

        let model = Model(0)
        let host = TestHost(Parent(model: model))
        host.send(Key.enter)
        #expect(model.value == 7)
        #expect(host.text == "Set\n7")
    }
}
#endif
