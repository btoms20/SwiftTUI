import Foundation

/// The basic layout object that can be created by a node. Not every node will
/// create a control (e.g. ForEach won't).
@MainActor
class Control: LayerDrawing {
    private(set) var children: [Control] = []
    // Weak references make every retain and release of the object slower, and
    // controls are retained constantly while drawing.
    // The resulting cycles are broken by `detachSubtree()`.
    private(set) var parent: Control?

    private var index: Int = 0

    weak var window: Window?
    private(set) lazy var layer: Layer = makeLayer()

    var root: Control { parent?.root ?? self }

    func addSubview(_ view: Control, at index: Int) {
        self.children.insert(view, at: index)
        layer.addLayer(view.layer, at: index)
        view.parent = self
        view.window = window
        for i in index ..< children.count {
            children[i].index = i
        }
        if let window = root.window, window.firstResponder == nil {
            if let responder = view.firstSelectableElement {
                window.firstResponder = responder
                responder.becomeFirstResponder()
            }
        }
    }

    func removeSubview(at index: Int) {
        if children[index].isFirstResponder || root.window?.firstResponder?.isDescendant(of: children[index]) == true {
            root.window?.firstResponder?.resignFirstResponder()
            root.window?.firstResponder = selectableElement(above: index) ?? selectableElement(below: index)
            root.window?.firstResponder?.becomeFirstResponder()
        }
        let removed = children[index]
        removed.window = nil
        removed.parent = nil
        self.children.remove(at: index)
        layer.removeLayer(at: index)
        // Removed controls aren't reused, so let the whole subtree be deallocated.
        removed.detachSubtree()
        for i in index ..< children.count {
            children[i].index = i
        }
    }

    /// Clears the parent references in this subtree, so it can be deallocated
    /// once it is no longer used.
    func detachSubtree() {
        for child in children {
            child.detachSubtree()
            child.parent = nil
        }
        layer.detachSublayers()
    }

    func isDescendant(of control: Control) -> Bool {
        guard let parent else { return false }
        return control === parent || parent.isDescendant(of: control)
    }

    func makeLayer() -> Layer {
        let layer = Layer()
        layer.content = self
        return layer
    }

    // MARK: - Layout

    func size(proposedSize: Size) -> Size {
        proposedSize
    }

    func layout(size: Size) {
        layer.frame.size = size
    }

    func horizontalFlexibility(height: Extended) -> Extended {
        let minSize = size(proposedSize: Size(width: 0, height: height))
        let maxSize = size(proposedSize: Size(width: .infinity, height: height))
        return maxSize.width - minSize.width
    }

    func verticalFlexibility(width: Extended) -> Extended {
        let minSize = size(proposedSize: Size(width: width, height: 0))
        let maxSize = size(proposedSize: Size(width: width, height: .infinity))
        return maxSize.height - minSize.height
    }

    // MARK: - Drawing

    func cell(at position: Position) -> Cell? { nil }

    // MARK: - Event handling

    /// Handles a key press sent to this control while it is the first responder.
    ///
    /// - Returns: Whether the key was used. Unused keys, such as arrows, can
    ///   then move focus instead.
    func handle(_ event: KeyEvent) -> Bool {
        false
    }

    func becomeFirstResponder() {
        scrollIntoView(Rect(position: .zero, size: layer.frame.size))
    }

    func resignFirstResponder() {}

    var isFirstResponder: Bool { root.window?.firstResponder === self }

    // MARK: - Selection

    var selectable: Bool { false }

    /// This control's frame in window coordinates.
    final var frameInWindow: Rect {
        var position = layer.frame.position
        var ancestor = parent
        while let current = ancestor {
            position = position + current.layer.frame.position
            ancestor = current.parent
        }
        return Rect(position: position, size: layer.frame.size)
    }

    /// The selectable controls in this subtree, in tree order.
    final var selectableElements: [Control] {
        if selectable { return [self] }
        return children.flatMap(\.selectableElements)
    }

    final var firstSelectableElement: Control? {
        if selectable { return self }
        for control in children {
            if let element = control.firstSelectableElement { return element }
        }
        return nil
    }

    func selectableElement(below index: Int) -> Control? { parent?.selectableElement(below: self.index) }
    func selectableElement(above index: Int) -> Control? { parent?.selectableElement(above: self.index) }
    func selectableElement(rightOf index: Int) -> Control? { parent?.selectableElement(rightOf: self.index) }
    func selectableElement(leftOf index: Int) -> Control? { parent?.selectableElement(leftOf: self.index) }

    // MARK: - Scrolling

    /// Asks enclosing scroll views to make `rect`, in this control's coordinates, visible.
    func scrollIntoView(_ rect: Rect) {
        parent?.scrollIntoView(Rect(position: rect.position + layer.frame.position, size: rect.size))
    }

}
