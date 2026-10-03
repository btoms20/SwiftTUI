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

    /// Creates bindings to the observed object's properties, as in `$model.name`.
    public var projectedValue: Wrapper {
        Wrapper(object: initialValue)
    }

    @dynamicMemberLookup
    public struct Wrapper {
        let object: T

        @MainActor
        public subscript<Subject>(dynamicMember keyPath: ReferenceWritableKeyPath<T, Subject>) -> Binding<Subject> {
            let object = object
            return Binding(get: { object[keyPath: keyPath] }, set: { object[keyPath: keyPath] = $0 })
        }
    }

    var objectIdentifier: ObjectIdentifier { ObjectIdentifier(initialValue) }

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
    var objectIdentifier: ObjectIdentifier { get }
    func subscribe(_ action: @escaping @MainActor () -> Void) -> AnyCancellable
}

#endif
