#if canImport(Combine)
import Combine
import Foundation
import Testing
@testable import SwiftTUI

@MainActor
@Suite struct ConcurrencyTests {
    // Only mutated from one task at a time in these tests.
    final class Model: ObservableObject, @unchecked Sendable {
        @Published var value = 0
    }

    struct ModelView: View {
        @ObservedObject var model: Model
        var body: some View {
            Text("\(model.value)")
        }
    }

    @Test func observedObjectChangeOnMainThreadRerenders() {
        let model = Model()
        let host = TestHost(ModelView(model: model))
        #expect(host.text == "0")
        model.value = 1
        #expect(host.text == "1")
    }

    @Test func observedObjectChangeFromBackgroundThreadRerenders() async {
        let model = Model()
        let host = TestHost(ModelView(model: model))
        #expect(host.text == "0")

        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                model.value = 2
                continuation.resume()
            }
        }

        // The invalidation hops to the main actor before being applied.
        await drainMainQueue()
        #expect(host.text == "2")
    }
}
#endif
