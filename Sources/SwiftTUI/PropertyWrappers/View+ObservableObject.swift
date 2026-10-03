#if os(macOS)
import Foundation
import Combine

/// A node's subscription to one `@ObservedObject` property.
struct ObservedObjectSubscription {
    let object: ObjectIdentifier
    let cancellable: AnyCancellable
}

extension View {
    func setupObservedObjectProperties(node: Node) {
        for (label, value) in Mirror(reflecting: self).children {
            guard let label, let observedObject = value as? AnyObservedObject else { continue }
            // Keep the existing subscription while the view observes the same object.
            if node.subscriptions[label]?.object == observedObject.objectIdentifier { continue }
            let cancellable = observedObject.subscribe { [weak node] in
                guard let node else { return }
                node.root.application?.invalidateNode(node)
            }
            node.subscriptions[label] = ObservedObjectSubscription(object: observedObject.objectIdentifier, cancellable: cancellable)
        }
    }
}
#endif
