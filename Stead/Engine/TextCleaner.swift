import Foundation

/// Normalises notification text before the rules look at it.
enum TextCleaner {
    /// Zero-width characters that scammers slip inside words to dodge filters.
    static let zeroWidth: Set<Unicode.Scalar> = [
        "\u{200B}", "\u{200C}", "\u{200D}", "\u{2060}", "\u{2061}", "\u{2062}", "\u{2063}", "\u{2064}", "\u{FEFF}", "\u{00AD}",
    ]
    /// Direction marks that iOS and WhatsApp add on their own. Removed, never counted as a trick.
    static let directionMarks: Set<Unicode.Scalar> = [
        "\u{200E}", "\u{200F}", "\u{202A}", "\u{202B}", "\u{202C}", "\u{202D}", "\u{202E}",
        "\u{2066}", "\u{2067}", "\u{2068}", "\u{2069}",
    ]

    /// Folds full-width and look-alike forms (NFKC), strips invisible characters, collapses spaces.
    static func clean(_ text: String) -> String {
        let folded = text.precomposedStringWithCompatibilityMapping
        var scalars = String.UnicodeScalarView()
        for s in folded.unicodeScalars where !zeroWidth.contains(s) && !directionMarks.contains(s) {
            scalars.append(s)
        }
        return String(scalars)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Counts zero-width characters sitting *between letters* in the body (not at the edges).
    static func hiddenCharactersInsideWords(_ text: String) -> Int {
        let scalars = Array(text.unicodeScalars)
        var count = 0
        for (i, s) in scalars.enumerated() where zeroWidth.contains(s) {
            guard i > 0, i < scalars.count - 1 else { continue }
            let before = scalars[i - 1], after = scalars[i + 1]
            if CharacterSet.alphanumerics.contains(before) && CharacterSet.alphanumerics.contains(after) {
                count += 1
            }
        }
        return count
    }
}
