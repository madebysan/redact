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

/// Group the transcript into display rows.
///
/// Splitting rules:
///   - a word that ends a sentence (. ! ?) closes the current row
///   - 10 words per row max
///   - a run of silence tokens joins the end of the row it follows and closes it,
///     so a pause reads as one inline length chip instead of rows of dashes
///
/// The result is an array of short, coherent rows; each can be kept or cut whole.
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
    var index = 0
    while index < allWords.count {
        let word = allWords[index]
        if word.isActualSilence {
            var run: [Word] = []
            while index < allWords.count, allWords[index].isActualSilence {
                run.append(allWords[index])
                index += 1
            }
            if current.isEmpty, let previous = lines.popLast() {
                // The previous row already closed on a sentence end: the pause trails it.
                current = previous.words
                nextId -= 1
            }
            current.append(contentsOf: run)
            commit()
            continue
        }

        current.append(word)
        index += 1
        let endsSentence = word.word.hasSuffix(".") || word.word.hasSuffix("!") || word.word.hasSuffix("?")
        if endsSentence || current.count >= 10 {
            commit()
        }
    }

    commit()
    return lines
}
