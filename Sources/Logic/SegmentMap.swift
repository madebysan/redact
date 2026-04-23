import Foundation

/// Padding added before and after each deleted word so the tail/onset
/// of the sound is also removed. 75ms matches roughly one consonant.
let CUT_PADDING: Double = 0.075

/// Build a sorted array of deleted time ranges from transcript words.
///
/// A *run* is a maximal sequence of consecutive deleted words in the word list.
/// Each run collapses into a single TimeRange spanning first.start → last.end,
/// with CUT_PADDING only on the outer edges (not between internal words).
///
/// This matters for micro-gaps: Whisper's word timings routinely leave 150-800ms
/// gaps between words. If both neighbors are deleted, the audio in that gap has
/// no kept content to belong to, so it goes with the deletion.
func buildDeletedRanges(_ words: [Word]) -> [TimeRange] {
    var deleted: [TimeRange] = []
    var i = 0

    while i < words.count {
        guard words[i].deleted else {
            i += 1
            continue
        }

        // Walk to the end of this run.
        let runStart = i
        while i < words.count && words[i].deleted {
            i += 1
        }
        let runEnd = i - 1

        let first = words[runStart]
        let last = words[runEnd]

        // Silence tokens already touch their neighbors, so they don't get padding.
        let startPad = first.isActualSilence ? 0.0 : CUT_PADDING
        let endPad = last.isActualSilence ? 0.0 : CUT_PADDING
        let padStart = max(0, first.start - startPad)
        let padEnd = last.end + endPad

        // Still merge with previous range if padded edges touch.
        if var prev = deleted.last, padStart <= prev.end {
            prev.end = max(prev.end, padEnd)
            deleted[deleted.count - 1] = prev
        } else {
            deleted.append(TimeRange(start: padStart, end: padEnd))
        }
    }

    return deleted
}

/// Build a sorted array of kept time ranges (inverse of deleted).
func buildKeptRanges(_ words: [Word], totalDuration: Double) -> [TimeRange] {
    let deleted = buildDeletedRanges(words)
    if deleted.isEmpty {
        return [TimeRange(start: 0, end: totalDuration)]
    }

    var kept: [TimeRange] = []

    if deleted[0].start > 0 {
        kept.append(TimeRange(start: 0, end: deleted[0].start))
    }

    for i in 0..<(deleted.count - 1) {
        let gapStart = deleted[i].end
        let gapEnd = deleted[i + 1].start
        if gapEnd > gapStart + 0.01 {
            kept.append(TimeRange(start: gapStart, end: gapEnd))
        }
    }

    let lastDeleted = deleted[deleted.count - 1]
    if lastDeleted.end < totalDuration {
        kept.append(TimeRange(start: lastDeleted.end, end: totalDuration))
    }

    return kept
}

/// Binary search: is the given time inside a deleted range?
/// Returns the deleted range if found, nil otherwise.
func findDeletedRange(time: Double, deletedRanges: [TimeRange]) -> TimeRange? {
    var lo = 0
    var hi = deletedRanges.count - 1

    while lo <= hi {
        let mid = (lo + hi) / 2
        let range = deletedRanges[mid]

        if time < range.start {
            hi = mid - 1
        } else if time > range.end {
            lo = mid + 1
        } else {
            return range
        }
    }

    return nil
}

/// Find the next deleted range that starts AFTER the given time.
/// Used to fade out audio as we approach a cut.
func findNextDeletedStart(time: Double, deletedRanges: [TimeRange]) -> Double? {
    for range in deletedRanges {
        if range.start > time { return range.start }
    }
    return nil
}

/// Find the word at the given timestamp using binary search.
func findWordAtTime(_ words: [Word], time: Double) -> Word? {
    guard !words.isEmpty else { return nil }

    var lo = 0
    var hi = words.count - 1

    while lo <= hi {
        let mid = (lo + hi) / 2
        let word = words[mid]

        if time < word.start {
            hi = mid - 1
        } else if time > word.end {
            lo = mid + 1
        } else {
            return word
        }
    }

    // If between words, return the closest one
    if lo < words.count && lo > 0 {
        let prev = words[lo - 1]
        let next = words[lo]
        return (time - prev.end) < (next.start - time) ? prev : next
    }

    if lo < words.count {
        return words[lo]
    }
    if hi >= 0 {
        return words[hi]
    }
    return nil
}

/// Calculate the edited duration (total minus deleted).
func calculateEditedDuration(_ words: [Word], totalDuration: Double) -> Double {
    let deleted = buildDeletedRanges(words)
    var deletedTime: Double = 0
    for range in deleted {
        deletedTime += range.end - range.start
    }
    return totalDuration - deletedTime
}
