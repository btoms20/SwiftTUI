import Foundation
import Testing
@_spi(Testing) @testable import SwiftTUI

@Suite struct TerminalLifecycleTests {
    private static let screenReset = "\u{1b}[0m\u{1b}[?25h\u{1b}[?1049l"

    @Test func setupEntersAlternateScreenOnlyWhenStarted() async {
        await MainActor.run {
            let terminal = VirtualTerminal(columns: 5, lines: 1)
            let application = Application(rootView: Text("Hi"), output: terminal)
            #expect(!terminal.isAlternateBufferEnabled)
            application.start(columns: 5, lines: 1)
            #expect(terminal.isAlternateBufferEnabled)
            #expect(!terminal.isCursorVisible)
        }
    }

    @Test func stopResetsScreenAndExits() async {
        let result = await #expect(processExitsWith: .success, observing: [\.standardOutputContent]) {
            await MainActor.run {
                let application = Application(rootView: Text("Hi").bold(), output: StandardOutput())
                application.start(columns: 5, lines: 1)
                application.stop()
            }
        }
        let output = String(decoding: result?.standardOutputContent ?? [], as: UTF8.self)
        #expect(output.hasSuffix(Self.screenReset))
    }

    @Test func stopApplicationEnvironmentActionExits() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                struct Quit: View {
                    @Environment(\.stopApplication) var stopApplication
                    var body: some View {
                        Button("Quit") { stopApplication() }
                    }
                }
                let host = TestHost(Quit())
                host.send(Key.enter)
            }
            Issue.record("The application should have exited")
        }
    }

    @Test func endOfInputStops() async {
        await #expect(processExitsWith: .success) {
            await MainActor.run {
                var pipeDescriptors: [Int32] = [0, 0]
                pipe(&pipeDescriptors)
                close(pipeDescriptors[1])
                let host = TestHost { Text("Hi") }
                host.application.readInput(from: pipeDescriptors[0])
            }
            Issue.record("The application should have exited")
        }
    }

    @Test func startOutsideTerminalFailsWithMessage() async {
        // Exit test output is captured through pipes, so neither stream is a terminal.
        let result = await #expect(processExitsWith: .exitCode(1), observing: [\.standardErrorContent]) {
            await MainActor.run {
                Application(rootView: Text("Hi")).start()
            }
        }
        let message = String(decoding: result?.standardErrorContent ?? [], as: UTF8.self)
        #expect(message.contains("must be run in a terminal"))
    }

    @Test func enableAndRestoreRoundTripTerminalSettings() throws {
        let terminal = try #require(PseudoTerminal())
        let original = terminal.attributes
        #expect(original.c_lflag & tcflag_t(ECHO) != 0)

        try TerminalMode.enable(input: terminal.secondary, output: terminal.secondary)
        #expect(terminal.attributes.c_lflag & tcflag_t(ECHO | ICANON) == 0)

        TerminalMode.suspend()
        #expect(terminal.attributes.c_lflag == original.c_lflag)
        TerminalMode.reenable()
        #expect(terminal.attributes.c_lflag & tcflag_t(ECHO | ICANON) == 0)

        TerminalMode.restore(resetScreen: false)
        #expect(!TerminalMode.isEnabled)
        #expect(terminal.attributes.c_lflag == original.c_lflag)
        #expect(terminal.attributes.c_iflag == original.c_iflag)
        #expect(terminal.attributes.c_oflag == original.c_oflag)
    }

    @Test func enableFailsWhenInputIsNotATerminal() {
        var pipeDescriptors: [Int32] = [0, 0]
        pipe(&pipeDescriptors)
        defer { pipeDescriptors.forEach { close($0) } }
        #expect(throws: TerminalMode.Error.notATerminal) {
            try TerminalMode.enable(input: pipeDescriptors[0], output: pipeDescriptors[1])
        }
    }

    @Test func crashRestoresTerminal() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardOutputContent]) {
            let terminal = PseudoTerminal()!
            try TerminalMode.enable(input: terminal.secondary, output: STDOUT_FILENO)
            fatalError("Simulated crash")
        }
        let output = String(decoding: result?.standardOutputContent ?? [], as: UTF8.self)
        #expect(output == Self.screenReset)
    }
}
