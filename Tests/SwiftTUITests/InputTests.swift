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
        host.send("a" + Key.left + Key.up + "b")
        #expect(host.text == "ab")
    }

    @Test func unknownEscapeSequencesAreNotTyped() {
        let host = textField()
        // Forward delete, as sent by most terminals.
        host.send("a\u{1b}[3~")
        withKnownIssue("The arrow key parser only understands ESC [ A-D") {
            #expect(host.text == "a")
        }
    }

    @Test func controlCharactersAreNotTyped() {
        let host = textField()
        host.send("a\tb")
        withKnownIssue("TextField inserts any character it receives") {
            #expect(host.text == "ab")
        }
    }
}
