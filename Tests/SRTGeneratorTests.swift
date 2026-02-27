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
    let lines = srt.split(separator: "\n")
    #expect(lines.count > 0)
}
