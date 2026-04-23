import Foundation

/// Generate SRT content from transcript words.
/// Groups consecutive non-deleted words into subtitle segments.
/// Timestamps are recalculated relative to the edited timeline.
func generateSrt(words: [Word], totalDuration: Double) -> String {
    let keptWords = words.filter { !$0.deleted }
    if keptWords.isEmpty { return "" }

    // Build deleted ranges for time offset calculation
    let deletedRanges = buildDeletedRangesForSrt(words)

    func getEditedTime(_ originalTime: Double) -> Double {
        var offset: Double = 0
        for range in deletedRanges {
            if originalTime <= range.start { break }
            if originalTime >= range.end {
                offset += range.end - range.start
            } else {
                offset += originalTime - range.start
            }
        }
        return originalTime - offset
    }

    // Group words into subtitle segments (max 10 words, break at sentence boundaries)
    struct SrtSegment {
        let words: [Word]
        let start: Double
        let end: Double
    }

    var segments: [SrtSegment] = []
    var currentGroup: [Word] = []

    for word in keptWords {
        currentGroup.append(word)

        let isSentenceEnd = word.word.hasSuffix(".") || word.word.hasSuffix("!") || word.word.hasSuffix("?")
        let isLongEnough = currentGroup.count >= 10

        if isSentenceEnd || isLongEnough {
            segments.append(SrtSegment(
                words: currentGroup,
                start: currentGroup[0].start,
                end: word.end
            ))
            currentGroup = []
        }
    }

    // Remaining words
    if !currentGroup.isEmpty {
        segments.append(SrtSegment(
            words: currentGroup,
            start: currentGroup[0].start,
            end: currentGroup[currentGroup.count - 1].end
        ))
    }

    // Generate SRT
    var lines: [String] = []
    for (i, seg) in segments.enumerated() {
        let startEdited = getEditedTime(seg.start)
        let endEdited = getEditedTime(seg.end)
        let text = seg.words.map(\.word).joined(separator: " ")

        lines.append("\(i + 1)")
        lines.append("\(formatSrtTime(startEdited)) --> \(formatSrtTime(endEdited))")
        lines.append(text)
        lines.append("")
    }

    return lines.joined(separator: "\n")
}

/// Build deleted ranges without padding — used for SRT time offset calculation.
/// Runs of consecutive deleted words collapse into one range so micro-gaps
/// inside a deletion don't inflate the edited timeline.
private func buildDeletedRangesForSrt(_ words: [Word]) -> [TimeRange] {
    var deleted: [TimeRange] = []
    var i = 0

    while i < words.count {
        guard words[i].deleted else {
            i += 1
            continue
        }

        let runStart = i
        while i < words.count && words[i].deleted {
            i += 1
        }
        let runEnd = i - 1

        let spanStart = words[runStart].start
        let spanEnd = words[runEnd].end

        if var last = deleted.last, spanStart <= last.end + 0.05 {
            last.end = max(last.end, spanEnd)
            deleted[deleted.count - 1] = last
        } else {
            deleted.append(TimeRange(start: spanStart, end: spanEnd))
        }
    }

    return deleted
}
