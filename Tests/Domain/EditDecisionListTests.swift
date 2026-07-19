import Testing
@testable import Redact

@Test func v1AdapterSeparatesSourceTranscriptFromDeletionState() {
    let words = [
        makeWord("Keep", start: 0.0, end: 0.4, id: "w_0"),
        makeWord("remove", start: 0.5, end: 0.8, deleted: true, id: "w_1"),
    ]

    let transcript = SourceTranscript(v1Words: words, language: "en", duration: 1.0)
    let edits = EditDecisionList(v1Words: words)

    #expect(transcript.words.map(\.id) == ["w_0", "w_1"])
    #expect(transcript.words.map(\.text) == ["Keep", "remove"])
    #expect(edits.deletedWordIDs == ["w_1"])
}

@Test func mediaRenderPlanMatchesV1CutRanges() {
    let words = [
        makeWord("Keep", start: 0.0, end: 0.4, id: "w_0"),
        makeWord("remove", start: 0.5, end: 0.8, deleted: true, id: "w_1"),
        makeWord("this", start: 0.9, end: 1.1, deleted: true, id: "w_2"),
        makeWord("End.", start: 1.2, end: 1.6, id: "w_3"),
    ]
    let transcript = SourceTranscript(v1Words: words, language: "en", duration: 2.0)
    let edits = EditDecisionList(v1Words: words)

    let plan = RenderPlan(
        transcript: transcript,
        edits: edits,
        policy: .mediaV1
    )

    #expect(plan.deletedRanges == buildDeletedRanges(words))
    #expect(plan.keptRanges == buildKeptRanges(words, totalDuration: 2.0))
}

@Test func projectRevisionAppliesEditsImmutably() {
    let words = [
        makeWord("Keep", start: 0.0, end: 0.4, id: "w_0"),
        makeWord("remove", start: 0.5, end: 0.8, id: "w_1"),
    ]
    let transcript = SourceTranscript(v1Words: words, language: "en", duration: 1.0)
    let original = ProjectRevision(transcript: transcript)

    let edited = original.applying(.delete(wordIDs: ["w_1"]))

    #expect(!original.edits.contains(wordID: "w_1"))
    #expect(edited.edits.contains(wordID: "w_1"))
    #expect(edited.parentID == original.id)
    #expect(edited.id != original.id)
}

@Test func projectRevisionCorrectsTextWithoutChangingEditDecisionsOrTiming() throws {
    let words = makeSyntheticWords(count: 3)
    let transcript = SourceTranscript(v1Words: words, language: "en", duration: 1)
    let revision = ProjectRevision(
        transcript: transcript,
        edits: EditDecisionList(deletedWordIDs: ["synthetic_0"])
    )

    let corrected = try #require(revision.correctingWordText(
        wordID: "synthetic_1",
        text: "replacement"
    ))

    #expect(corrected.parentID == revision.id)
    #expect(corrected.transcript.words[1].text == "replacement")
    #expect(corrected.transcript.words[1].start == transcript.words[1].start)
    #expect(corrected.transcript.words[1].end == transcript.words[1].end)
    #expect(corrected.edits == revision.edits)
}

@Test func timelineMapConvertsBetweenSourceAndEditedTime() {
    let map = TimelineMap(
        keptRanges: [
            TimeRange(start: 0, end: 1),
            TimeRange(start: 2, end: 4),
        ]
    )

    #expect(map.editedDuration == 3)
    #expect(map.editedTime(forSourceTime: 0.5) == 0.5)
    #expect(map.editedTime(forSourceTime: 1.5) == 1)
    #expect(map.editedTime(forSourceTime: 2.5) == 1.5)
    #expect(map.sourceTime(forEditedTime: 1.5) == 2.5)
}

@Test func timelineMapMapsACutBoundaryToTheNextKeptRange() {
    let map = TimelineMap(
        keptRanges: [
            TimeRange(start: 0, end: 1),
            TimeRange(start: 2, end: 4),
        ]
    )

    #expect(map.sourceTime(forEditedTime: 1) == 2)
    #expect(map.sourceTime(forEditedTime: 3) == 4)
}

@Test func transcriptIndexFindsStableWordPositions() {
    let words = [
        makeWord("one", start: 0.0, end: 0.2, id: "w_0"),
        makeWord("two", start: 0.3, end: 0.5, id: "w_1"),
        makeWord("three", start: 0.6, end: 0.8, id: "w_2"),
    ]
    let transcript = SourceTranscript(v1Words: words, language: "en", duration: 1)
    let index = TranscriptIndex(transcript: transcript)

    #expect(index.position(forWordID: "w_1") == 1)
    #expect(index.positions(forWordIDs: ["w_2", "w_0"]) == [0, 2])
    #expect(index.position(forWordID: "missing") == nil)
}

private struct DeterministicGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}

@Test func mediaRenderPlanMatchesV1AcrossRandomizedDeletionPatterns() {
    for seed in 1...25 {
        var generator = DeterministicGenerator(seed: UInt64(seed))
        let words = (0..<500).map { index in
            let start = Double(index) * 0.25
            return makeWord(
                "word",
                start: start,
                end: start + 0.15,
                deleted: generator.next().isMultiple(of: 4),
                isSilence: index.isMultiple(of: 17),
                id: "w_\(index)"
            )
        }
        let duration = Double(words.count) * 0.25
        let transcript = SourceTranscript(v1Words: words, language: "en", duration: duration)
        let plan = RenderPlan(
            transcript: transcript,
            edits: EditDecisionList(v1Words: words),
            policy: .mediaV1
        )

        #expect(plan.deletedRanges == buildDeletedRanges(words))
        #expect(plan.keptRanges == buildKeptRanges(words, totalDuration: duration))
    }
}
