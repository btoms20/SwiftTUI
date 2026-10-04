import Foundation

/// Runs an executable attached to a pseudo-terminal, as if someone ran it in a
/// terminal window, so tests can type into it and read what it draws.
///
/// Every wait has a deadline and the process is killed when this object goes
/// away, so a misbehaving app fails the test instead of hanging it.
final class PseudoTerminalProcess {
    let terminal: PseudoTerminal
    let columns: Int
    let lines: Int

    /// The terminal settings before the process started.
    let originalAttributes: termios

    private let process = Process()
    private var output: [UInt8] = []

    init(executable: URL, columns: Int = 40, lines: Int = 10) throws {
        guard let terminal = PseudoTerminal() else {
            throw CocoaError(.fileReadUnknown)
        }
        self.terminal = terminal
        self.columns = columns
        self.lines = lines
        terminal.setSize(columns: columns, lines: lines)
        originalAttributes = terminal.attributes

        // Reads from the primary end shouldn't block while waiting for output.
        _ = fcntl(terminal.primary, F_SETFL, fcntl(terminal.primary, F_GETFL) | O_NONBLOCK)

        let handle = FileHandle(fileDescriptor: terminal.secondary, closeOnDealloc: false)
        process.executableURL = executable
        process.standardInput = handle
        process.standardOutput = handle
        process.standardError = handle
        try process.run()
    }

    deinit {
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
        }
        terminal.close()
    }

    /// Everything the process has written, interpreted as a screen.
    var screen: VirtualTerminal {
        readAvailableOutput()
        let screen = VirtualTerminal(columns: columns, lines: lines)
        screen.write(String(decoding: output, as: UTF8.self))
        return screen
    }

    /// Everything the process has written, as raw text.
    var rawOutput: String {
        readAvailableOutput()
        return String(decoding: output, as: UTF8.self)
    }

    var isRunning: Bool { process.isRunning }

    /// Types `input` into the terminal.
    func send(_ input: String) {
        var bytes = Array(input.utf8)
        _ = write(terminal.primary, &bytes, bytes.count)
    }

    func sendSignal(_ signal: Int32) {
        kill(process.processIdentifier, signal)
    }

    /// Waits until `condition` holds for the screen, or `timeout` passes.
    @discardableResult
    func waitForScreen(timeout: Duration = .seconds(10), _ condition: (VirtualTerminal) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition(screen) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition(screen)
    }

    /// Waits for the process to exit and returns its exit status, or `nil` if
    /// it is still running after `timeout` (or was killed by a signal).
    func waitForExit(timeout: Duration = .seconds(10)) async -> Int32? {
        let deadline = ContinuousClock.now + timeout
        while process.isRunning, ContinuousClock.now < deadline {
            // Keep draining output, so the process never blocks writing to us.
            readAvailableOutput()
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !process.isRunning, process.terminationReason == .exit else { return nil }
        readAvailableOutput()
        return process.terminationStatus
    }

    private func readAvailableOutput() {
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(terminal.primary, &buffer, buffer.count)
            guard count > 0 else { return }
            output.append(contentsOf: buffer[..<count])
        }
    }
}

extension PseudoTerminalProcess {
    /// The test app built alongside the tests.
    static var testAppURL: URL {
        get throws {
            // Executables are built into the same directory as the test bundle,
            // both by Xcode and by `swift test`.
            let directories = Bundle.allBundles
                .map(\.bundleURL)
                .filter { $0.pathExtension == "xctest" }
                .map { $0.deletingLastPathComponent() }
            for directory in directories {
                let url = directory.appending(path: "SwiftTUITestApp")
                if FileManager.default.isExecutableFile(atPath: url.path) { return url }
            }
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "SwiftTUITestApp"])
        }
    }
}
