import Foundation

public struct GeometryReader<Content: View>: View, PrimitiveView {
    let content: (Size) -> Content

    public init(@ViewBuilder content: @escaping (Size) -> Content) {
        self.content = content
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        let control = GeometryReaderControl(node: node, content: content)
        node.addNode(at: 0, Node(view: VStack(content: content(control.contentSize)).view))
        control.addSubview(node.children[0].control(at: 0), at: 0)
        node.control = control
    }

    func updateNode(_ node: Node) {
        node.view = self
        let control = node.control as! GeometryReaderControl
        control.content = content
        node.children[0].update(using: VStack(content: content(control.contentSize)).view)
    }

    private class GeometryReaderControl: Control {
        weak var node: Node?
        var content: (Size) -> Content

        /// The size the content was last built for.
        private(set) var contentSize: Size = .zero

        init(node: Node, content: @escaping (Size) -> Content) {
            self.node = node
            self.content = content
        }

        override func size(proposedSize: Size) -> Size {
            return proposedSize
        }

        override func layout(size: Size) {
            super.layout(size: size)
            // Rebuild the content for the size it actually gets, before laying it out.
            if contentSize != size, let node {
                contentSize = size
                node.children[0].update(using: VStack(content: content(size)).view)
            }
            children[0].layout(size: size)
        }
    }
}
