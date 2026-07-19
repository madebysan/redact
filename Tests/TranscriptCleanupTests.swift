import Testing
@testable import Redact

@Test func cleanupFindsClearFillersAndCommonFillerPhrases() {
    let words = [
        cleanupWord("Well", id: "w0", start: 0),
        cleanupWord(" um,", id: "w1", start: 0.3),
        cleanupWord(" I", id: "w2", start: 0.6),
        cleanupWord(" mean", id: "w3", start: 0.9),
        cleanupWord("this", id: "w4", start: 1.2),
        cleanupWord("uh", id: "w5", start: 1.5, deleted: true),
    ]

    let suggestions = TranscriptCleanupAnalyzer.suggestions(for: words)
        .filter { $0.kind == .fillerWords }

    #expect(suggestions.map(\.wordIDs) == [["w1"], ["w2", "w3"]])
    #expect(suggestions[0].changeDescription == "Remove “um,”")
    #expect(suggestions[1].context.contains("[I mean]"))
}

@Test func cleanupDoesNotSuggestAmbiguousKindOrSortOfPhrases() {
    let words = [
        cleanupWord("kind", id: "w0", start: 0),
        cleanupWord("of", id: "w1", start: 0.3),
        cleanupWord("movie", id: "w2", start: 0.6),
        cleanupWord("sort", id: "w3", start: 0.9),
        cleanupWord("of", id: "w4", start: 1.2),
        cleanupWord("works", id: "w5", start: 1.5),
    ]

    let suggestions = TranscriptCleanupAnalyzer.suggestions(for: words)

    #expect(suggestions.allSatisfy { $0.kind != .fillerWords })
}

@Test func cleanupKeepsTheLastWordInAnAdjacentRepetition() {
    let words = [
        cleanupWord("I", id: "w0", start: 0),
        cleanupWord("I", id: "w1", start: 0.3),
        cleanupWord("I,", id: "w2", start: 0.6),
        cleanupWord("think", id: "w3", start: 0.9),
    ]

    let suggestion = TranscriptCleanupAnalyzer.suggestions(for: words)
        .first { $0.kind == .repeatedWords }

    #expect(suggestion?.wordIDs == ["w0", "w1"])
    #expect(suggestion?.changeDescription == "Keep one “I,”")
}

@Test func cleanupDoesNotDuplicateFillerAndRepetitionSuggestions() {
    let words = [
        cleanupWord("um", id: "w0", start: 0),
        cleanupWord("um", id: "w1", start: 0.3),
    ]

    let suggestions = TranscriptCleanupAnalyzer.suggestions(for: words)

    #expect(suggestions.filter { $0.kind == .fillerWords }.count == 2)
    #expect(suggestions.allSatisfy { $0.kind != .repeatedWords })
}

@Test func cleanupShortensLongPausesWithoutRemovingThemEntirely() {
    let words = [
        cleanupWord("before", id: "w0", start: 0),
        cleanupWord("—", id: "s0", start: 0.3, duration: 0.5, isSilence: true),
        cleanupWord("—", id: "s1", start: 0.8, duration: 0.5, isSilence: true),
        cleanupWord("—", id: "s2", start: 1.3, duration: 0.5, isSilence: true),
        cleanupWord("after", id: "w1", start: 1.8),
    ]

    let suggestion = TranscriptCleanupAnalyzer.suggestions(for: words)
        .first { $0.kind == .longPauses }

    #expect(suggestion?.wordIDs == ["s0", "s1"])
    #expect(suggestion?.changeDescription == "Shorten 1.5s pause to 0.5s")
    #expect(suggestion?.removedDuration == 1)
}

@Test func projectDocumentAppliesCleanupAsOneUndoableEdit() {
    let project = ProjectDocument()
    project.setTranscript(
        RawTranscript(
            segments: [
                RawSegment(
                    id: 0,
                    words: [
                        RawWord(word: "um", start: 0, end: 0.2, confidence: 1),
                        RawWord(word: "hello", start: 0.3, end: 0.6, confidence: 1),
                        RawWord(word: "hello", start: 0.7, end: 1, confidence: 1),
                    ]
                ),
            ],
            language: "en",
            duration: 1.2
        )
    )

    let changed = project.deleteWords(["w_0", "w_1"])

    #expect(changed == ["w_0", "w_1"])
    #expect(project.editDecisionList.deletedWordIDs == ["w_0", "w_1"])
    #expect(project.undoStack.count == 1)
    #expect(project.undo() == ["w_0", "w_1"])
    #expect(project.editDecisionList.deletedWordIDs.isEmpty)
}

private func cleanupWord(
    _ text: String,
    id: String,
    start: Double,
    duration: Double = 0.2,
    deleted: Bool = false,
    isSilence: Bool = false
) -> Word {
    Word(
        id: id,
        word: text,
        start: start,
        end: start + duration,
        confidence: 1,
        deleted: deleted,
        isSilence: isSilence
    )
}
