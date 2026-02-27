import Testing
@testable import Redact

func makeWord(_ word: String, start: Double, end: Double, deleted: Bool = false, isSilence: Bool? = nil, id: String? = nil) -> Word {
    Word(
        id: id ?? "w_\(start)",
        word: word,
        start: start,
        end: end,
        confidence: 0.9,
        deleted: deleted,
        isSilence: isSilence
    )
}

// MARK: - buildDeletedRanges

@Test func buildDeletedRanges_returnsEmptyWhenNoDeleted() {
    let words = [
        makeWord("hello", start: 0, end: 0.5),
        makeWord("world", start: 0.6, end: 1.0),
    ]
    #expect(buildDeletedRanges(words).isEmpty)
}

@Test func buildDeletedRanges_returnsRangesWithPadding() {
    let words = [
        makeWord("hello", start: 0, end: 0.5),
        makeWord("um", start: 0.6, end: 0.8, deleted: true),
        makeWord("world", start: 0.9, end: 1.5),
    ]
    let ranges = buildDeletedRanges(words)
    #expect(ranges.count == 1)
    // 75ms padding: 0.6 - 0.075 = 0.525, 0.8 + 0.075 = 0.875
    #expect(ranges[0].start == 0.525)
    #expect(ranges[0].end == 0.875)
}

@Test func buildDeletedRanges_mergesAdjacentDeleted() {
    let words = [
        makeWord("um", start: 0.0, end: 0.2, deleted: true),
        makeWord("uh", start: 0.22, end: 0.4, deleted: true),
        makeWord("hello", start: 0.5, end: 1.0),
    ]
    let ranges = buildDeletedRanges(words)
    #expect(ranges.count == 1)
    #expect(ranges[0].start == 0)
    #expect(abs(ranges[0].end - 0.475) < 0.001)
}

@Test func buildDeletedRanges_createsSeparateRangesForNonAdjacent() {
    let words = [
        makeWord("um", start: 0.0, end: 0.2, deleted: true),
        makeWord("hello", start: 0.5, end: 1.0),
        makeWord("uh", start: 1.5, end: 1.7, deleted: true),
    ]
    let ranges = buildDeletedRanges(words)
    #expect(ranges.count == 2)
    #expect(ranges[0] == TimeRange(start: 0.0, end: 0.275))
    #expect(ranges[1] == TimeRange(start: 1.425, end: 1.775))
}

// MARK: - buildKeptRanges

@Test func buildKeptRanges_returnsFullDurationWhenNothingDeleted() {
    let words = [
        makeWord("hello", start: 0, end: 0.5),
        makeWord("world", start: 0.6, end: 1.0),
    ]
    let kept = buildKeptRanges(words, totalDuration: 2.0)
    #expect(kept.count == 1)
    #expect(kept[0] == TimeRange(start: 0, end: 2.0))
}

@Test func buildKeptRanges_excludesDeletedRanges() {
    let words = [
        makeWord("hello", start: 0, end: 0.5),
        makeWord("um", start: 0.6, end: 0.8, deleted: true),
        makeWord("world", start: 0.9, end: 1.5),
    ]
    let kept = buildKeptRanges(words, totalDuration: 2.0)
    #expect(kept.count == 2)
    #expect(kept[0] == TimeRange(start: 0, end: 0.525))
    #expect(kept[1] == TimeRange(start: 0.875, end: 2.0))
}

// MARK: - findDeletedRange

@Test func findDeletedRange_returnsRangeWhenInside() {
    let ranges = [
        TimeRange(start: 1.0, end: 2.0),
        TimeRange(start: 5.0, end: 6.0),
    ]
    #expect(findDeletedRange(time: 1.5, deletedRanges: ranges) == TimeRange(start: 1.0, end: 2.0))
    #expect(findDeletedRange(time: 5.5, deletedRanges: ranges) == TimeRange(start: 5.0, end: 6.0))
}

@Test func findDeletedRange_returnsNilWhenOutside() {
    let ranges = [
        TimeRange(start: 1.0, end: 2.0),
        TimeRange(start: 5.0, end: 6.0),
    ]
    #expect(findDeletedRange(time: 0.5, deletedRanges: ranges) == nil)
    #expect(findDeletedRange(time: 3.0, deletedRanges: ranges) == nil)
    #expect(findDeletedRange(time: 7.0, deletedRanges: ranges) == nil)
}

@Test func findDeletedRange_returnsRangeAtBoundaries() {
    let ranges = [
        TimeRange(start: 1.0, end: 2.0),
        TimeRange(start: 5.0, end: 6.0),
    ]
    #expect(findDeletedRange(time: 1.0, deletedRanges: ranges) == TimeRange(start: 1.0, end: 2.0))
    #expect(findDeletedRange(time: 2.0, deletedRanges: ranges) == TimeRange(start: 1.0, end: 2.0))
}

// MARK: - findWordAtTime

@Test func findWordAtTime_findsWordAtExactTime() {
    let words = [
        makeWord("hello", start: 0, end: 0.5, id: "w_0"),
        makeWord("world", start: 0.6, end: 1.0, id: "w_1"),
        makeWord("goodbye", start: 1.5, end: 2.0, id: "w_2"),
    ]
    let result = findWordAtTime(words, time: 0.3)
    #expect(result?.id == "w_0")
}

@Test func findWordAtTime_findsWordAtBoundary() {
    let words = [
        makeWord("hello", start: 0, end: 0.5, id: "w_0"),
        makeWord("world", start: 0.6, end: 1.0, id: "w_1"),
        makeWord("goodbye", start: 1.5, end: 2.0, id: "w_2"),
    ]
    let result = findWordAtTime(words, time: 0.6)
    #expect(result?.id == "w_1")
}

@Test func findWordAtTime_returnsClosestWhenBetweenWords() {
    let words = [
        makeWord("hello", start: 0, end: 0.5, id: "w_0"),
        makeWord("world", start: 0.6, end: 1.0, id: "w_1"),
        makeWord("goodbye", start: 1.5, end: 2.0, id: "w_2"),
    ]
    let result = findWordAtTime(words, time: 0.55)
    #expect(result != nil)
    #expect(["w_0", "w_1"].contains(result?.id))
}

// MARK: - calculateEditedDuration

@Test func calculateEditedDuration_returnsFullWhenNothingDeleted() {
    let words = [
        makeWord("hello", start: 0, end: 0.5),
        makeWord("world", start: 0.6, end: 1.0),
    ]
    #expect(calculateEditedDuration(words, totalDuration: 2.0) == 2.0)
}

@Test func calculateEditedDuration_subtractsDeletedDuration() {
    let words = [
        makeWord("hello", start: 0, end: 0.5),
        makeWord("um", start: 0.6, end: 0.8, deleted: true),
        makeWord("world", start: 0.9, end: 1.5),
    ]
    // Deleted with padding: 0.525 to 0.875 = 0.35s -> 2.0 - 0.35 = 1.65
    let result = calculateEditedDuration(words, totalDuration: 2.0)
    #expect(abs(result - 1.65) < 0.01)
}
