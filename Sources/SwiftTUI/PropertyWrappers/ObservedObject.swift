#if os(macOS)
import Foundation
import Combine

@propertyWrapper
public struct ObservedObject<T: ObservableObject>: AnyObservedObject {
    public let initialValue: T

    public init(initialValue: T) {
        self.initialValue = initialValue
    }

    public init(wrappedValue: T) {
        self.initialValue = wrappedValue
    }

    public var wrappedValue: T {
        get { initialValue }
    }

    func subscribe(_ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        initialValue.objectWillChange.sink { _ in
            // Objects may publish changes from any thread.
            if Thread.isMainThread {
                MainActor.assumeIsolated(action)
            } else {
                Task { @MainActor in action() }
            }
        }
    }
}

protocol AnyObservedObject {
    func subscribe(_ action: @escaping @MainActor () -> Void) -> AnyCancellable
}

#endif
