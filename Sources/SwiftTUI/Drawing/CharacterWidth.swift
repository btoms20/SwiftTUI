extension Character {
    /// The number of terminal columns this character occupies: 2 for wide
    /// characters such as CJK ideographs and emoji, 1 otherwise.
    ///
    /// This follows the East Asian Width property and emoji presentation, which
    /// is what most terminals use. Ambiguous-width characters count as 1.
    var displayWidth: Int {
        // Fast path for the common case.
        if let ascii = asciiValue, ascii >= 0x20 { return 1 }

        let scalars = unicodeScalars
        guard let first = scalars.first else { return 1 }
        if first.isWide { return 2 }
        // Emoji presentation can come from the scalar itself or a variation selector (U+FE0F).
        if first.properties.isEmojiPresentation { return 2 }
        if first.properties.isEmoji, scalars.contains("\u{FE0F}") { return 2 }
        return 1
    }
}

extension StringProtocol {
    /// The number of terminal columns the string occupies.
    var displayWidth: Int {
        reduce(0) { $0 + $1.displayWidth }
    }
}

private extension Unicode.Scalar {
    var isWide: Bool {
        let value = value
        // Everything below U+1100 is narrow.
        guard value >= 0x1100 else { return false }
        return wideRanges.contains { $0.contains(value) }
    }
}

/// Wide (W) and fullwidth (F) ranges from Unicode's East Asian Width data,
/// merged into blocks. Emoji are handled separately through their properties.
private let wideRanges: [ClosedRange<UInt32>] = [
    0x1100...0x115F,   // Hangul Jamo initial consonants
    0x231A...0x231B,   // Watch, hourglass
    0x2329...0x232A,   // Angle brackets
    0x2E80...0x303E,   // CJK radicals, Kangxi radicals, CJK symbols and punctuation
    0x3041...0x33FF,   // Hiragana, Katakana, Bopomofo, Hangul compatibility Jamo, CJK compatibility
    0x3400...0x4DBF,   // CJK unified ideographs extension A
    0x4E00...0x9FFF,   // CJK unified ideographs
    0xA000...0xA4CF,   // Yi syllables and radicals
    0xA960...0xA97F,   // Hangul Jamo extended A
    0xAC00...0xD7A3,   // Hangul syllables
    0xF900...0xFAFF,   // CJK compatibility ideographs
    0xFE10...0xFE19,   // Vertical forms
    0xFE30...0xFE6F,   // CJK compatibility forms, small form variants
    0xFF00...0xFF60,   // Fullwidth forms
    0xFFE0...0xFFE6,   // Fullwidth signs
    0x16FE0...0x18CFF, // Tangut, Khitan
    0x1B000...0x1B2FF, // Kana supplement and extended
    0x1F200...0x1F2FF, // Enclosed ideographic supplement
    0x20000...0x2FFFD, // CJK unified ideographs extensions B–F
    0x30000...0x3FFFD, // CJK unified ideographs extensions G–H
]
