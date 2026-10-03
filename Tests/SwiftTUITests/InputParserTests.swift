import Testing
@testable import SwiftTUI

@Suite struct InputParserTests {
    private func parse(_ input: String) -> [KeyEvent] {
        var parser = InputParser()
        return parser.parse(input)
    }

    @Test(arguments: [
        ("\u{1b}[A", KeyEvent(.up)),
        ("\u{1b}[B", KeyEvent(.down)),
        ("\u{1b}[C", KeyEvent(.right)),
        ("\u{1b}[D", KeyEvent(.left)),
        ("\u{1b}OA", KeyEvent(.up)),
        ("\u{1b}[H", KeyEvent(.home)),
        ("\u{1b}[F", KeyEvent(.end)),
        ("\u{1b}[1~", KeyEvent(.home)),
        ("\u{1b}[4~", KeyEvent(.end)),
        ("\u{1b}[3~", KeyEvent(.delete)),
        ("\u{1b}[5~", KeyEvent(.pageUp)),
        ("\u{1b}[6~", KeyEvent(.pageDown)),
        ("\u{1b}[Z", KeyEvent(.backTab)),
        ("\u{1b}OP", KeyEvent(.function(1))),
        ("\u{1b}[24~", KeyEvent(.function(12))),
        ("\u{1b}[1;2A", KeyEvent(.up, modifiers: .shift)),
        ("\u{1b}[1;5C", KeyEvent(.right, modifiers: .control)),
        ("\u{1b}[3;3~", KeyEvent(.delete, modifiers: .option)),
        ("\u{7f}", KeyEvent(.backspace)),
        ("\u{08}", KeyEvent(.backspace)),
        ("\r", KeyEvent(.enter)),
        ("\n", KeyEvent(.enter)),
        ("\t", KeyEvent(.tab)),
        ("\u{01}", KeyEvent(.character("a"), modifiers: .control)),
        ("\u{1b}b", KeyEvent(.character("b"), modifiers: .option)),
        ("é", KeyEvent(.character("é"))),
    ])
    func singleKey(input: String, expected: KeyEvent) {
        #expect(parse(input) == [expected])
    }

    @Test func textAndSequencesInOneChunk() {
        #expect(parse("ab\u{1b}[Dc") == [
            KeyEvent(.character("a")),
            KeyEvent(.character("b")),
            KeyEvent(.left),
            KeyEvent(.character("c")),
        ])
    }

    @Test func graphemeClustersStayTogether() {
        let family = "👨‍👩‍👧"
        #expect(parse(family + "e\u{301}") == [
            KeyEvent(.character(Character(family))),
            KeyEvent(.character("e\u{301}")),
        ])
    }

    @Test func unknownSequencesAreDropped() {
        #expect(parse("\u{1b}[99~\u{1b}[<0;1;1M\u{1b}[?1;2c\u{1b}[200~x") == [KeyEvent(.character("x"))])
    }

    @Test func doubleEscapeResolvesFirstAsEscape() {
        #expect(parse("\u{1b}\u{1b}[A") == [KeyEvent(.escape), KeyEvent(.up)])
    }

    @Test func loneEscapeWaitsForMoreInput() {
        var parser = InputParser()
        #expect(parser.parse("\u{1b}").isEmpty)
        #expect(parser.hasPendingEscape)
        #expect(parser.flushPendingEscape() == KeyEvent(.escape))
        #expect(!parser.hasPendingEscape)
    }

    @Test func sequenceSplitAcrossChunks() {
        var parser = InputParser()
        #expect(parser.parse("\u{1b}[").isEmpty)
        #expect(parser.parse("1;5").isEmpty)
        #expect(parser.parse("B") == [KeyEvent(.down, modifiers: .control)])
    }

    @Test func utf8SplitAcrossChunks() {
        var parser = InputParser()
        let bytes = Array("€".utf8)
        #expect(parser.parse(bytes[..<1]).isEmpty)
        #expect(parser.parse(bytes[1..<2]).isEmpty)
        #expect(parser.parse(bytes[2...]) == [KeyEvent(.character("€"))])
    }

    @Test func invalidUTF8IsReplaced() {
        var parser = InputParser()
        #expect(parser.parse([0x61, 0xff, 0x62]) == [
            KeyEvent(.character("a")),
            KeyEvent(.character("\u{fffd}")),
            KeyEvent(.character("b")),
        ])
    }
}
