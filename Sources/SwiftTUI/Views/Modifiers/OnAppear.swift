import Foundation

public extension View {
    func onAppear(_ action: @escaping @MainActor () -> Void) -> some View {
        return OnAppear(content: self, action: action)
    }
}

private struct OnAppear<Content: View>: View, PrimitiveView, ModifierView {
    let content: Content
    let action: @MainActor () -> Void

    static var size: Int? { Content.size }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
        for control in node.wrapperControls {
            (control as! OnAppearControl).action = action
        }
    }

    func passControl(_ control: Control, node: Node) -> Control {
        node.wrapper(for: control) { OnAppearControl(action: action) }
    }

    private class OnAppearControl: Control {
        var action: @MainActor () -> Void
        var didAppear = false

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        override func size(proposedSize: Size) -> Size {
            children[0].size(proposedSize: proposedSize)
        }

        override func layout(size: Size) {
            super.layout(size: size)
            children[0].layout(size: size)
            if !didAppear {
                didAppear = true
                DispatchQueue.main.async { [action] in action() }
            }
        }
    }
}
