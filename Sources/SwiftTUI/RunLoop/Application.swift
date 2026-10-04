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

    private var inputParser = InputParser()
    private var escapeFlushGeneration = 0

    private var invalidatedNodes: [Node] = []
    private var updateScheduled = false
    private var isUpdating = false

    /// The number of update passes run so far, for tests.
    private(set) var updateCount = 0

    public convenience init<I: View>(rootView: I, runLoopType: RunLoopType = .dispatch) {
        self.init(rootView: rootView, runLoopType: runLoopType, output: StandardOutput())
    }

    /// Creates an application that renders to `output` instead of standard output.
    @_spi(Testing)
    public init<I: View>(rootView: I, runLoopType: RunLoopType = .dispatch, output: TerminalOutput) {
        self.runLoopType = runLoopType

        // The action is created before `self`, so it finds the application through a weak box.
        let application = Weak<Application>(value: nil)
        let stopApplication = StopApplicationAction { application.value?.stop() }
        node = Node(view: VStack(content: rootView.environment(\.stopApplication, stopApplication)).view)
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
        application.value = self
    }

    deinit {
        // Controls and layers reference their parents strongly, so break those
        // cycles. If released off the main thread, leak rather than race.
        guard Thread.isMainThread else { return }
        MainActor.assumeIsolated {
            control.detachSubtree()
            window.layer.detachSublayers()
        }
    }

    /// Input and signal sources, kept alive while the application runs.
    private var eventSources: [DispatchSourceProtocol] = []

    public enum RunLoopType: Sendable {
        /// The default option, running the main run loop, which also services
        /// the main dispatch queue.
        case dispatch

        #if os(macOS)
        /// This creates and runs an NSApplication with an associated run loop. This allows you
        /// e.g. to open NSWindows running simultaneously to the terminal app. This requires macOS
        /// and AppKit.
        case cocoa
        #endif
    }

    /// Takes over the terminal and runs the application until it is stopped.
    ///
    /// The terminal is restored when the application stops, is terminated by a
    /// signal, or crashes.
    public func start() {
        guard isatty(STDOUT_FILENO) == 1 else {
            exitWithError("SwiftTUI applications must be run in a terminal: standard output is not a terminal.")
        }
        do {
            try TerminalMode.enable()
        } catch {
            exitWithError("SwiftTUI applications must be run in a terminal: standard input is not a terminal.")
        }

        renderer.setup()
        updateWindowSize()
        control.layout(size: window.layer.frame.size)
        renderer.draw()

        let input = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        addEventSource(input) { $0.readInput() }

        addSignalSource(SIGWINCH) { $0.handleWindowSizeChange() }
        for terminatingSignal in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            addSignalSource(terminatingSignal) { $0.stop() }
        }
        addSignalSource(SIGTSTP) { $0.suspend() }
        addSignalSource(SIGCONT, ignoringDefaultAction: false) { $0.resume() }

        runMainLoop()
    }

    /// Runs the main run loop until the process exits.
    func runMainLoop() -> Never {
        switch runLoopType {
        case .dispatch:
            // Not `dispatchMain()`: it parks the main thread and drains the main
            // queue on another thread, which breaks main-actor isolation.
            // The main run loop drains the main queue on the main thread.
            // The timer only keeps the run loop from returning when all its work
            // comes from dispatch sources.
            let keepAlive = Timer(timeInterval: 60 * 60 * 24 * 365, repeats: true) { _ in }
            RunLoop.main.add(keepAlive, forMode: .default)
            while true {
                RunLoop.main.run()
            }
        #if os(macOS)
        case .cocoa:
            NSApplication.shared.setActivationPolicy(.accessory)
            NSApplication.shared.run()
            exit(0)
        #endif
        }
    }

    /// Starts rendering to the output without taking over a terminal or running
    /// a run loop.
    @_spi(Testing)
    public func start(columns: Int, lines: Int) {
        renderer.setup()
        resize(columns: columns, lines: lines)
    }

    /// Restores the terminal and exits the process.
    public func stop() -> Never {
        renderer.stop()
        TerminalMode.restore(resetScreen: false)
        exit(0)
    }

    private func exitWithError(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    // MARK: - Event sources

    /// Handles `signalNumber` on the main queue instead of with its default action.
    private func addSignalSource(_ signalNumber: Int32, ignoringDefaultAction: Bool = true, _ handler: @escaping @MainActor (Application) -> Void) {
        if ignoringDefaultAction {
            signal(signalNumber, SIG_IGN)
        }
        addEventSource(DispatchSource.makeSignalSource(signal: signalNumber, queue: .main), handler)
    }

    /// Calls `handler` for each event from `source`, which must deliver on the main queue.
    private func addEventSource(_ source: DispatchSourceProtocol, _ handler: @escaping @MainActor (Application) -> Void) {
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                if let self { handler(self) }
            }
        }
        source.resume()
        eventSources.append(source)
    }

    /// Gives the terminal back to the shell and stops the process, as Ctrl-Z expects.
    private func suspend() {
        renderer.stop()
        TerminalMode.suspend()
        // SIGSTOP rather than SIGTSTP, which the signal source would see again after resuming.
        kill(getpid(), SIGSTOP)
    }

    /// Takes the terminal back after the process was continued, redrawing everything.
    private func resume() {
        TerminalMode.reenable()
        renderer.setup()
        updateWindowSize()
        control.layout(size: window.layer.frame.size)
        renderer.draw()
    }

    // MARK: - Input

    func readInput(from fileDescriptor: Int32 = STDIN_FILENO) {
        var buffer = [UInt8](repeating: 0, count: 1024)
        let count = read(fileDescriptor, &buffer, buffer.count)
        if count == 0 {
            // End of input: the terminal was closed.
            stop()
        }
        if count < 0 {
            if errno == EINTR || errno == EAGAIN { return }
            stop()
        }
        handle(inputParser.parse(buffer[..<count]))
    }

    /// Processes `string` as if it had been typed into the terminal.
    @_spi(Testing)
    public func handleInput(_ string: String) {
        handle(inputParser.parse(string))
    }

    private func handle(_ events: [KeyEvent]) {
        for event in events {
            handle(event)
        }
        if inputParser.hasPendingEscape {
            scheduleEscapeFlush()
        }
    }

    private func handle(_ event: KeyEvent) {
        if event == KeyEvent(.character("d"), modifiers: .control) {
            stop()
        }
        if window.firstResponder?.handle(event) == true {
            return
        }
        guard event.modifiers.isEmpty else { return }
        switch event.key {
        case .up: moveFocus(.up)
        case .down: moveFocus(.down)
        case .left: moveFocus(.left)
        case .right: moveFocus(.right)
        case .tab: moveFocusInOrder(by: 1)
        case .backTab: moveFocusInOrder(by: -1)
        default: break
        }
    }

    // MARK: - Focus

    private enum Direction {
        case up, down, left, right
    }

    /// Moves focus to the nearest selectable control in `direction` on screen.
    private func moveFocus(_ direction: Direction) {
        guard let current = window.firstResponder else { return }
        let origin = current.frameInWindow

        // Candidates overlapping the current control across the direction of
        // movement come first (the next item in a column or row); then the closest.
        var best: (control: Control, overlaps: Bool, distance: Extended)?
        for candidate in control.selectableElements where candidate !== current {
            let frame = candidate.frameInWindow
            let gap: Extended
            let crossGap: Extended
            switch direction {
            case .down:
                gap = frame.minLine - origin.maxLine
                crossGap = Self.gap(frame.minColumn, frame.maxColumn, origin.minColumn, origin.maxColumn)
            case .up:
                gap = origin.minLine - frame.maxLine
                crossGap = Self.gap(frame.minColumn, frame.maxColumn, origin.minColumn, origin.maxColumn)
            case .right:
                gap = frame.minColumn - origin.maxColumn
                crossGap = Self.gap(frame.minLine, frame.maxLine, origin.minLine, origin.maxLine)
            case .left:
                gap = origin.minColumn - frame.maxColumn
                crossGap = Self.gap(frame.minLine, frame.maxLine, origin.minLine, origin.maxLine)
            }
            guard gap > 0 else { continue }

            let overlaps = crossGap == 0
            let distance = overlaps ? gap : gap + crossGap
            if let best, (best.overlaps && !overlaps) || (best.overlaps == overlaps && best.distance <= distance) {
                continue
            }
            best = (candidate, overlaps, distance)
        }
        if let next = best?.control {
            focus(next)
        }
    }

    /// Moves focus through selectable controls in tree order, as Tab and Shift-Tab do.
    private func moveFocusInOrder(by offset: Int) {
        let elements = control.selectableElements
        guard !elements.isEmpty else { return }
        let currentIndex = window.firstResponder.flatMap { current in elements.firstIndex { $0 === current } }
        let nextIndex = currentIndex.map { ($0 + offset + elements.count) % elements.count } ?? 0
        focus(elements[nextIndex])
    }

    private func focus(_ next: Control) {
        guard next !== window.firstResponder else { return }
        window.firstResponder?.resignFirstResponder()
        window.firstResponder = next
        next.becomeFirstResponder()
    }

    /// The distance between the spans `aMin...aMax` and `bMin...bMax`, or 0 if they overlap.
    /// Plain bounds rather than ranges, since empty frames have `max < min`.
    private static func gap(_ aMin: Extended, _ aMax: Extended, _ bMin: Extended, _ bMax: Extended) -> Extended {
        if aMax < bMin { return bMin - aMax }
        if bMax < aMin { return aMin - bMax }
        return 0
    }

    /// Treats a lone ESC as the Escape key if no sequence follows it quickly.
    private func scheduleEscapeFlush() {
        escapeFlushGeneration += 1
        let generation = escapeFlushGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) {
            guard generation == self.escapeFlushGeneration else { return }
            self.flushPendingEscape()
        }
    }

    func flushPendingEscape() {
        if let event = inputParser.flushPendingEscape() {
            handle(event)
        }
    }

    func invalidateNode(_ node: Node) {
        invalidatedNodes.append(node)
        scheduleUpdate()
    }

    func scheduleUpdate() {
        // Anything invalidated during an update is handled by that update.
        guard !updateScheduled, !isUpdating else { return }
        updateScheduled = true
        DispatchQueue.main.async {
            // The update may already have run via `flushUpdates()`.
            if self.updateScheduled { self.update() }
        }
    }

    private func update() {
        updateScheduled = false
        isUpdating = true
        updateCount += 1

        // Updating nodes can invalidate other nodes, e.g. through a binding
        // written in `body`, so keep going until nothing is left.
        var passes = 0
        while !invalidatedNodes.isEmpty {
            let pending = invalidatedNodes
            invalidatedNodes = []
            for node in nodesToUpdate(pending) {
                node.update(using: node.view)
            }
            passes += 1
            if passes == 100 {
                assertionFailure("View updates did not settle; is a body writing state unconditionally?")
                break
            }
        }

        control.layout(size: window.layer.frame.size)
        renderer.update()
        isUpdating = false

        // Layout can change state too (e.g. GeometryReader).
        if !invalidatedNodes.isEmpty { scheduleUpdate() }
    }

    /// The nodes in `nodes` that are still in the tree, without duplicates, and
    /// without nodes that will be updated anyway because an ancestor is.
    private func nodesToUpdate(_ nodes: [Node]) -> [Node] {
        let invalidated = Set(nodes.map(ObjectIdentifier.init))
        var seen = Set<ObjectIdentifier>()
        var result: [Node] = []
        for node in nodes where seen.insert(ObjectIdentifier(node)).inserted {
            var top = node
            var hasInvalidatedAncestor = false
            while let parent = top.parent {
                if invalidated.contains(ObjectIdentifier(parent)) { hasInvalidatedAncestor = true }
                top = parent
            }
            if top === self.node, !hasInvalidatedAncestor {
                result.append(node)
            }
        }
        return result
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
        // Terminals reflow their contents on resize, so start from a clean screen.
        updateWindowSize()
        renderer.setup()
        update()
        renderer.draw()
    }

    private func updateWindowSize() {
        // Keep the current size if the terminal can't report one.
        guard let size = Platform.terminalSize(of: STDOUT_FILENO) else {
            if window.layer.frame.size == .zero {
                setWindowSize(Size(width: 80, height: 24))
            }
            return
        }
        setWindowSize(size)
    }

    private func setWindowSize(_ size: Size) {
        window.layer.frame.size = size
        renderer.setCache()
    }

}

// MARK: - Environment

/// Stops the running application, restoring the terminal and exiting the process.
///
/// Read it from the environment and call it as a function:
/// ```swift
/// @Environment(\.stopApplication) var stopApplication
///
/// var body: some View {
///     Button("Quit") { stopApplication() }
/// }
/// ```
public struct StopApplicationAction: Sendable {
    let action: @MainActor () -> Void

    @MainActor
    public func callAsFunction() {
        action()
    }
}

private struct StopApplicationKey: EnvironmentKey {
    static var defaultValue: StopApplicationAction { StopApplicationAction {} }
}

extension EnvironmentValues {
    public var stopApplication: StopApplicationAction {
        get { self[StopApplicationKey.self] }
        set { self[StopApplicationKey.self] = newValue }
    }
}
