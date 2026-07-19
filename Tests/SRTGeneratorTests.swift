import Testing
@testable import Redact

@Test func generateSrt_returnsEmptyForNoWords() {
    #expect(generateSrt(words: [], totalDuration: 10) == "")
}

@Test func generateSrt_returnsEmptyWhenAllDeleted() {
    let words = [
        makeWord("hello", start: 0, end: 0.5, deleted: true),
        makeWord("world", start: 0.6, end: 1.0, deleted: true),
    ]
    #expect(generateSrt(words: words, totalDuration: 2) == "")
}

@Test func generateSrt_generatesForSimpleWords() {
    let words = [
        makeWord("Hello", start: 0, end: 0.5),
        makeWord("world.", start: 0.6, end: 1.0),
    ]
    let srt = generateSrt(words: words, totalDuration: 2)
    #expect(srt.contains("1\n"))
    #expect(srt.contains("Hello world."))
    #expect(srt.contains("00:00:00,000"))
}

@Test func generateSrt_breaksAtSentenceBoundaries() {
    let words = [
        makeWord("First.", start: 0, end: 0.5),
        makeWord("Second.", start: 0.6, end: 1.0),
    ]
    let srt = generateSrt(words: words, totalDuration: 2)
    #expect(srt.contains("1\n"))
    #expect(srt.contains("2\n"))
}

@Test func generateSrt_excludesDeletedWords() {
    let words = [
        makeWord("Hello", start: 0, end: 0.5),
        makeWord("um", start: 0.6, end: 0.8, deleted: true),
        makeWord("world.", start: 0.9, end: 1.5),
    ]
    let srt = generateSrt(words: words, totalDuration: 2)
    #expect(!srt.contains("um"))
    #expect(srt.contains("Hello world."))
}

@Test func generateSrt_adjustsTimestampsForDeleted() {
    let words = [
        makeWord("Hello", start: 0, end: 0.5),
        makeWord("um", start: 0.6, end: 0.8, deleted: true),
        makeWord("world.", start: 0.9, end: 1.5),
    ]
    let srt = generateSrt(words: words, totalDuration: 2)
    #expect(srt.contains("00:00:00,000 --> 00:00:01,150"))
}

@Test func generateSrt_collapsesConsecutiveDeletedWordsIntoOneOffset() {
    let words = [
        makeWord("Keep", start: 0.0, end: 0.4),
        makeWord("remove", start: 0.5, end: 0.7, deleted: true),
        makeWord("this", start: 0.9, end: 1.1, deleted: true),
        makeWord("End.", start: 1.2, end: 1.6),
    ]

    let srt = generateSrt(words: words, totalDuration: 2)

    #expect(srt.contains("Keep End."))
    #expect(srt.contains("00:00:00,000 --> 00:00:00,850"))
}

@Test func generateSrt_deletedSilenceUsesItsExactDuration() {
    let words = [
        makeWord("Start", start: 0.0, end: 0.4),
        makeWord("—", start: 0.4, end: 0.9, deleted: true, isSilence: true),
        makeWord("End.", start: 0.9, end: 1.3),
    ]

    let srt = generateSrt(words: words, totalDuration: 1.3)

    #expect(srt.contains("00:00:00,000 --> 00:00:00,800"))
}

@Test func canonicalSrtEntryPointMatchesTheV1Adapter() {
    let words = [
        makeWord("Keep", start: 0.0, end: 0.4),
        makeWord("remove", start: 0.5, end: 0.8, deleted: true),
        makeWord("End.", start: 0.9, end: 1.3),
    ]
    let transcript = SourceTranscript(v1Words: words, language: "en", duration: 1.5)
    let edits = EditDecisionList(v1Words: words)
    let renderPlan = RenderPlan(
        transcript: transcript,
        edits: edits,
        policy: .mediaV1
    )

    #expect(
        generateSrt(transcript: transcript, edits: edits, renderPlan: renderPlan)
            == generateSrt(words: words, totalDuration: 1.5)
    )
    #expect(
        generateSrt(transcript: transcript, edits: edits, renderPlan: renderPlan)
            .contains("00:00:00,000 --> 00:00:00,850")
    )
}
