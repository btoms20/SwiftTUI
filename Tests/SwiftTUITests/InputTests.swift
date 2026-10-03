import Foundation
import Testing
@testable import SwiftTUI

@MainActor
@Suite struct InputTests {
    final class Submissions {
        var values: [String] = []
    }

    private func textField(_ submissions: Submissions = Submissions()) -> TestHost {
        TestHost {
            TextField(placeholder: "Name") { submissions.values.append($0) }
        }
    }

    @Test func placeholderShownWhenEmpty() {
        #expect(textField().text == "Name")
    }

    @Test func typing() {
        let host = textField()
        host.send("abc")
        #expect(host.text == "abc")
    }

    @Test func deleteRemovesLastCharacter() {
        let host = textField()
        host.send("abc")
        host.send(Key.delete)
        #expect(host.text == "ab")
    }

    @Test func enterSubmitsAndClears() {
        let submissions = Submissions()
        let host = textField(submissions)
        host.send("hello")
        host.send(Key.enter)
        #expect(submissions.values == ["hello"])
        #expect(host.text == "Name")
    }

    @Test func arrowKeysAreNotTyped() {
        let host = textField()
        // Left moves the cursor before "a"; up has nowhere to move focus.
        host.send("a" + Key.left + Key.up + "b")
        #expect(host.text == "ba")
    }

    @Test func unknownEscapeSequencesAreNotTyped() {
        let host = textField()
        // Insert, F5, Ctrl-Up, a mouse report and a private-mode reply.
        host.send("a\u{1b}[2~\u{1b}[15~\u{1b}[1;5A\u{1b}[<0;3;4M\u{1b}[?1;2cb")
        #expect(host.text == "ab")
    }

    @Test func controlCharactersAreNotTyped() {
        let host = textField()
        host.send("a\tb\u{1b}\u{01}c")
        #expect(host.text == "abc")
    }

    @Test func cursorEditing() {
        let host = textField()
        host.send("helo")
        host.send(Key.left + "l")
        #expect(host.text == "hello")

        host.send(Key.home + Key.forwardDelete)
        #expect(host.text == "ello")

        host.send(Key.end + Key.delete + "a")
        #expect(host.text == "ella")
    }

    @Test func cursorIsDrawnAtInsertionPoint() {
        let host = textField()
        host.send("abc" + Key.left + Key.left)
        _ = host.text
        #expect(host.terminal[1, 0].style.underline)
        #expect(!host.terminal[3, 0].style.underline)
    }

    @Test func multibyteCharactersSplitAcrossReads() {
        let host = textField()
        let bytes = Array("é🙂".utf8)
        // Feed the raw bytes one at a time, as a slow connection might.
        for byte in bytes {
            var pipeDescriptors: [Int32] = [0, 0]
            pipe(&pipeDescriptors)
            var byte = byte
            write(pipeDescriptors[1], &byte, 1)
            host.application.readInput(from: pipeDescriptors[0])
            close(pipeDescriptors[0])
            close(pipeDescriptors[1])
        }
        host.flush()
        #expect(host.text == "é🙂")
    }

    @Test func loneEscapeIsDeliveredAfterTimeout() async throws {
        // Escape isn't used by any control yet, so check it doesn't linger as a
        // prefix that swallows the next key.
        let host = textField()
        host.send(Key.escape)
        try await Task.sleep(for: .milliseconds(60))
        host.send("x")
        #expect(host.text == "x")
    }

    @Test func leftAtStartOfTextMovesFocus() {
        final class Log { var pressed = false }
        let log = Log()
        let host = TestHost {
            HStack {
                Button("B") { log.pressed = true }
                TextField(placeholder: "T") { _ in }
            }
        }
        host.send(Key.right)
        host.send("x" + Key.left + Key.left + Key.enter)
        #expect(log.pressed)
    }
}
