import Foundation

/// Automatically scrolls to the currently active control. The content needs to contain controls
/// such as buttons to scroll to.
public struct ScrollView<Content: View>: View, PrimitiveView {
    let content: VStack<Content>

    public init(@ViewBuilder _ content: () -> Content) {
        self.content = VStack(content: content())
    }

    static var size: Int? { 1 }

    func buildNode(_ node: Node) {
        node.addNode(at: 0, Node(view: content.view))
        let control = ScrollControl()
        control.contentControl = node.children[0].control(at: 0)
        control.addSubview(control.contentControl, at: 0)
        node.control = control
    }

    func updateNode(_ node: Node) {
        node.view = self
        node.children[0].update(using: content.view)
    }

    private class ScrollControl: Control {
        var contentControl: Control!
        var contentOffset: Extended = 0

        override func layout(size: Size) {
            super.layout(size: size)
            // The content gets the full width, and only as much height as it needs.
            let contentSize = contentControl.size(proposedSize: Size(width: size.width, height: 0))
            contentControl.layout(size: contentSize)
            // Keep the offset in range when the content or the viewport changes size.
            contentOffset = max(0, min(contentOffset, contentSize.height - size.height))
            contentControl.layer.frame.position.line = -contentOffset
        }

        override func scrollIntoView(_ rect: Rect) {
            let viewportHeight = layer.frame.size.height
            guard viewportHeight > 0 else { return }

            // `rect` is in this control's coordinates; find its lines in the content.
            let top = rect.minLine + contentOffset
            let bottom = top + max(rect.size.height, 1) - 1

            var offset = contentOffset
            if bottom > offset + viewportHeight - 1 { offset = bottom - viewportHeight + 1 }
            // If it doesn't fit, prefer showing its top.
            if top < offset { offset = top }
            if offset != contentOffset {
                contentOffset = offset
                layer.invalidate()
            }

            // Let enclosing scroll views show the part that is visible in this one.
            let visibleTop = max(top - offset, 0)
            let visibleBottom = min(bottom - offset, viewportHeight - 1)
            super.scrollIntoView(Rect(
                column: rect.minColumn,
                line: visibleTop,
                width: rect.size.width,
                height: max(visibleBottom - visibleTop + 1, 1)
            ))
        }
    }
}
