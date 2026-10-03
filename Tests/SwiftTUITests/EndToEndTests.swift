import Foundation
import Testing

/// Runs a real SwiftTUI app in a pseudo-terminal, covering what the headless
/// tests can't: the run loop, reading stdin, signals, and terminal restoration.
@Suite(.serialized, .timeLimit(.minutes(1)))
struct EndToEndTests {
    private static let screenReset = "\u{1b}[0m\u{1b}[?25h\u{1b}[?1049l"

    private func launch() async throws -> PseudoTerminalProcess {
        let app = try PseudoTerminalProcess(executable: try PseudoTerminalProcess.testAppURL)
        let started = await app.waitForScreen { $0.text.contains("ready") }
        try #require(started, "The app didn't draw its first frame")
        return app
    }

    @Test func typedInputReachesViews() async throws {
        let app = try await launch()
        app.send("abc\r")
        let echoed = await app.waitForScreen { $0.text.contains("echo: abc") }
        #expect(echoed, "Screen was:\n\(app.screen.text)")
        #expect(app.isRunning)
    }

    @Test func controlDExitsAndRestoresTerminal() async throws {
        let app = try await launch()
        #expect(app.terminal.attributes.c_lflag & tcflag_t(ECHO | ICANON) == 0)

        app.send("\u{04}")
        #expect(await app.waitForExit() == EXIT_SUCCESS)
        #expect(app.rawOutput.hasSuffix(Self.screenReset))
        #expect(!app.screen.isAlternateBufferEnabled)
        #expect(app.terminal.attributes.c_lflag == app.originalAttributes.c_lflag)
    }

    @Test func terminationSignalExitsAndRestoresTerminal() async throws {
        let app = try await launch()
        app.sendSignal(SIGTERM)
        #expect(await app.waitForExit() == EXIT_SUCCESS)
        #expect(app.rawOutput.hasSuffix(Self.screenReset))
        #expect(app.terminal.attributes.c_lflag == app.originalAttributes.c_lflag)
    }
}
