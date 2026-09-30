import Testing
@testable import SwiftTUI

@Suite struct PositionTests {
    @Test func add() {
        let pos1 = Position(column: 1, line: 2)
        let pos2 = Position(column: 5, line: 6)
        #expect(pos1 + pos2 == Position(column: 6, line: 8))
    }

    @Test func subtract() {
        let pos1 = Position(column: 1, line: 2)
        let pos2 = Position(column: 5, line: 6)
        #expect(pos2 - pos1 == Position(column: 4, line: 4))
    }
}

@Suite struct RectTests {
    @Test func union() {
        let rect1 = Rect(position: Position(column: 1, line: 2), size: Size(width: 5, height: 8))
        let rect2 = Rect(position: Position(column: 3, line: 1), size: Size(width: 2, height: 4))
        let expected = Rect(position: Position(column: 1, line: 1), size: Size(width: 5, height: 9))
        #expect(rect1.union(rect2) == expected)
    }

    @Test func containsIsHalfOpen() {
        let rect = Rect(position: Position(column: 1, line: 1), size: Size(width: 2, height: 2))
        #expect(rect.contains(Position(column: 1, line: 1)))
        #expect(rect.contains(Position(column: 2, line: 2)))
        #expect(!rect.contains(Position(column: 3, line: 1)))
        #expect(!rect.contains(Position(column: 0, line: 1)))
    }
}

@Suite struct ExtendedTests {
    @Test func arithmetic() {
        #expect(Extended(2) + Extended(3) == Extended(5))
        #expect(Extended(7) - Extended(3) == Extended(4))
        #expect(Extended(2) * Extended(3) == Extended(6))
        #expect(Extended(7) / Extended(2) == Extended(3))
    }

    @Test func infinityOrdering() {
        #expect(Extended(Int.max) < .infinity)
        #expect(Extended.infinity + 1 == .infinity)
        #expect(max(Extended(3), .infinity) == .infinity)
    }
}
