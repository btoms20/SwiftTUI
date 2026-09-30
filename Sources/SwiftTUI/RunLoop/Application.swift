import Foundation
#if os(macOS)
import AppKit
#endif

@MainActor
public class Application {
    private let node: Node
    private let window: Window
    private let control: Control
    var rootControl: Control { control }
    private let renderer: Renderer

    private let runLoopType: RunLoopType

    private var arrowKeyParser = ArrowKeyParser()

    private var invalidatedNodes: [Node] = []
    private var updateScheduled = false

    public convenience init<I: View>(rootView: I, runLoopType: RunLoopType = .dispatch) {
        self.init(rootView: rootView, runLoopType: runLoopType, output: StandardOutput())
    }

    /// Creates an application that renders to `output` instead of standard output.
    @_spi(Testing)
    public init<I: View>(rootView: I, runLoopType: RunLoopType = .dispatch, output: TerminalOutput) {
        self.runLoopType = runLoopType

        node = Node(view: VStack(content: rootView).view)
        node.build()

        control = node.control!

        window = Window()
        window.addControl(control)

        window.firstResponder = control.firstSelectableElement
        window.firstResponder?.becomeFirstResponder()

        renderer = Renderer(layer: window.layer, output: output)
        window.layer.renderer = renderer

        node.application = self
        renderer.application = self
    }

    var stdInSource: DispatchSourceRead?

    public enum RunLoopType: Sendable {
        /// The default option, using Dispatch for the main run loop.
        case dispatch

        #if os(macOS)
        /// This creates and runs an NSApplication with an associated run loop. This allows you
        /// e.g. to open NSWindows running simultaneously to the terminal app. This requires macOS
        /// and AppKit.
        case cocoa
        #endif
    }

    public func start() {
        setInputMode()
        updateWindowSize()
        control.layout(size: window.layer.frame.size)
        renderer.draw()

        let stdInSource = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        setMainEventHandler(stdInSource) { $0.handleInput() }
        stdInSource.resume()
        self.stdInSource = stdInSource

        let sigWinChSource = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: .main)
        setMainEventHandler(sigWinChSource) { $0.handleWindowSizeChange() }
        sigWinChSource.resume()

        signal(SIGINT, SIG_IGN)
        let sigIntSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        setMainEventHandler(sigIntSource) { $0.stop() }
        sigIntSource.resume()

        switch runLoopType {
        case .dispatch:
            dispatchMain()
        #if os(macOS)
        case .cocoa:
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.run()
        #endif
        }
    }

    /// Calls `handler` for each event from `source`, which must deliver on the main queue.
    private func setMainEventHandler(_ source: DispatchSourceProtocol, _ handler: @escaping @MainActor (Application) -> Void) {
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                if let self { handler(self) }
            }
        }
    }

    private func setInputMode() {
        var tattr = termios()
        tcgetattr(STDIN_FILENO, &tattr)
        tattr.c_lflag &= ~tcflag_t(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &tattr);
    }

    private func handleInput() {
        let data = FileHandle.standardInput.availableData

        guard let string = String(data: data, encoding: .utf8) else {
            return
        }

        handleInput(string)
    }

    /// Processes `string` as if it had been typed into the terminal.
    @_spi(Testing)
    public func handleInput(_ string: String) {
        for char in string {
            if arrowKeyParser.parse(character: char) {
                guard let key = arrowKeyParser.arrowKey else { continue }
                arrowKeyParser.arrowKey = nil
                if key == .down {
                    if let next = window.firstResponder?.selectableElement(below: 0) {
                        window.firstResponder?.resignFirstResponder()
                        window.firstResponder = next
                        window.firstResponder?.becomeFirstResponder()
                    }
                } else if key == .up {
                    if let next = window.firstResponder?.selectableElement(above: 0) {
                        window.firstResponder?.resignFirstResponder()
                        window.firstResponder = next
                        window.firstResponder?.becomeFirstResponder()
                    }
                } else if key == .right {
                    if let next = window.firstResponder?.selectableElement(rightOf: 0) {
                        window.firstResponder?.resignFirstResponder()
                        window.firstResponder = next
                        window.firstResponder?.becomeFirstResponder()
                    }
                } else if key == .left {
                    if let next = window.firstResponder?.selectableElement(leftOf: 0) {
                        window.firstResponder?.resignFirstResponder()
                        window.firstResponder = next
                        window.firstResponder?.becomeFirstResponder()
                    }
                }
            } else if char == ASCII.EOT {
                stop()
            } else {
                window.firstResponder?.handleEvent(char)
            }
        }
    }

    func invalidateNode(_ node: Node) {
        invalidatedNodes.append(node)
        scheduleUpdate()
    }

    func scheduleUpdate() {
        if !updateScheduled {
            DispatchQueue.main.async { self.update() }
            updateScheduled = true
        }
    }

    private func update() {
        updateScheduled = false

        for node in invalidatedNodes {
            node.update(using: node.view)
        }
        invalidatedNodes = []

        control.layout(size: window.layer.frame.size)
        renderer.update()
    }

    /// Applies pending state changes and redraws what they invalidated,
    /// without waiting for the run loop.
    @_spi(Testing)
    public func flushUpdates() {
        update()
    }

    /// Sets the window size, then lays out and fully redraws the view hierarchy.
    @_spi(Testing)
    public func resize(columns: Int, lines: Int) {
        setWindowSize(Size(width: Extended(columns), height: Extended(lines)))
        control.layout(size: window.layer.frame.size)
        renderer.draw()
    }

    private func handleWindowSizeChange() {
        updateWindowSize()
        control.layer.invalidate()
        update()
    }

    private func updateWindowSize() {
        guard let size = Platform.terminalSize(of: STDOUT_FILENO) else {
            assertionFailure("Could not get window size")
            return
        }
        setWindowSize(size)
    }

    private func setWindowSize(_ size: Size) {
        window.layer.frame.size = size
        renderer.setCache()
    }

    private func stop() {
        renderer.stop()
        resetInputMode() // Fix for: https://github.com/rensbreur/SwiftTUI/issues/25
        exit(0)
    }

    /// Fix for: https://github.com/rensbreur/SwiftTUI/issues/25
    private func resetInputMode() {
        // Reset ECHO and ICANON values:
        var tattr = termios()
        tcgetattr(STDIN_FILENO, &tattr)
        tattr.c_lflag |= tcflag_t(ECHO | ICANON)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &tattr);
    }

}
