import Foundation

/// Saves the terminal's settings when SwiftTUI starts and restores them when it stops.
///
/// Restoring also happens when the process exits or crashes, so the shell isn't
/// left with echo disabled, the cursor hidden, or the alternate screen active.
enum TerminalMode {
    enum Error: Swift.Error {
        case notATerminal
    }

    /// Switches `input` to non-canonical mode without echo, remembering its
    /// current settings so they can be restored.
    static func enable(input: Int32 = STDIN_FILENO, output: Int32 = STDOUT_FILENO) throws(Error) {
        var attributes = termios()
        guard isatty(input) == 1, tcgetattr(input, &attributes) == 0 else {
            throw .notATerminal
        }
        installExitHandlers()
        savedState = SavedState(input: input, output: output, attributes: attributes)

        var raw = attributes
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        tcsetattr(input, TCSAFLUSH, &raw)
    }

    /// Temporarily restores the saved settings, e.g. while the process is suspended.
    static func suspend() {
        guard var state = savedState else { return }
        tcsetattr(state.input, TCSAFLUSH, &state.attributes)
    }

    /// Re-applies the mode after ``suspend()``.
    static func reenable() {
        guard let state = savedState else { return }
        var raw = state.attributes
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)
        tcsetattr(state.input, TCSAFLUSH, &raw)
    }

    /// Restores the settings saved by ``enable(input:output:)``.
    ///
    /// - Parameter resetScreen: Whether to also reset text attributes, show the
    ///   cursor and leave the alternate screen.
    static func restore(resetScreen: Bool) {
        restoreSavedState(resetScreen: resetScreen)
    }

    /// Whether settings are saved and waiting to be restored.
    static var isEnabled: Bool { savedState != nil }
}

// MARK: - Restoration

// The state below is read from signal handlers, which can't take locks or hop to
// an actor. It is only written on the main thread, before the handlers can need it.

private struct SavedState {
    let input: Int32
    let output: Int32
    var attributes: termios
}

nonisolated(unsafe) private var savedState: SavedState?
nonisolated(unsafe) private var exitHandlersInstalled = false

/// Signals that end the process abnormally, e.g. `fatalError` or a bad memory access.
private let fatalSignals: [Int32] = [SIGABRT, SIGBUS, SIGFPE, SIGILL, SIGSEGV, SIGTRAP]

private func installExitHandlers() {
    guard !exitHandlersInstalled else { return }
    exitHandlersInstalled = true

    atexit { restoreSavedState(resetScreen: true) }

    for fatalSignal in fatalSignals {
        signal(fatalSignal) { received in
            restoreSavedState(resetScreen: true)
            // Crash with the default behavior, so reports and exit statuses are unchanged.
            signal(received, SIG_DFL)
            raise(received)
        }
    }
}

/// Only calls async-signal-safe functions, so it can run inside a signal handler.
private func restoreSavedState(resetScreen: Bool) {
    guard var state = savedState else { return }
    savedState = nil
    if resetScreen {
        // Reset text attributes, show the cursor, leave the alternate screen.
        let reset: StaticString = "\u{1b}[0m\u{1b}[?25h\u{1b}[?1049l"
        _ = write(state.output, reset.utf8Start, reset.utf8CodeUnitCount)
    }
    tcsetattr(state.input, TCSAFLUSH, &state.attributes)
}
