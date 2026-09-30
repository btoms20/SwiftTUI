import Foundation

/// Views are built and updated on the main actor, like in SwiftUI.
@MainActor @preconcurrency
public protocol View {
    associatedtype Body: View
    @ViewBuilder var body: Body { get }
}

extension Never: View {
    public var body: Never {
        fatalError()
    }

    public typealias Body = Never
}
