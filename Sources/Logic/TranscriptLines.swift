import Foundation

/// A visual line in the transcript — a short group of words that belong together.
/// This is the unit the editor can reason about for reordering / cutting (Stage B).
/// For now (Stage A) it's purely a rendering grouping.
struct TranscriptLine: Identifiable, Equatable {
    let id: Int
    let words: [Word]

    var startTime: Double { words.first?.start ?? 0 }
    var endTime: Double { words.last?.end ?? 0 }
}

/// Group the transcript into display lines.
///
/// Splitting rules (first one that fires wins):
///   - a silence token lives on its own line (visible pause indicator)
///   - a word that ends a sentence (. ! ?) closes the current line
///   - 10 words per line max
///
/// The result is an array of short, coherent lines suitable for rendering
/// as subtitle-style rows.
func computeLines(segments: [Segment]) -> [TranscriptLine] {
    var lines: [TranscriptLine] = []
    var current: [Word] = []
    var nextId = 0

    func commit() {
        guard !current.isEmpty else { return }
        lines.append(TranscriptLine(id: nextId, words: current))
        nextId += 1
        current = []
    }

    let allWords = segments.flatMap(\.words)

    for word in allWords {
        if word.isActualSilence {
            commit()
            current.append(word)
            commit()
            continue
        }

        current.append(word)

        let endsSentence = word.word.hasSuffix(".") || word.word.hasSuffix("!") || word.word.hasSuffix("?")
        if endsSentence || current.count >= 10 {
            commit()
        }
    }

    commit()
    return lines
}
