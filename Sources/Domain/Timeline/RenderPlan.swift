import Foundation

struct RenderPlan: Equatable, Sendable {
    let deletedRanges: [TimeRange]
    let keptRanges: [TimeRange]
    let timelineMap: TimelineMap

    var editedDuration: Double {
        timelineMap.editedDuration
    }

    init(
        transcript: SourceTranscript,
        edits: EditDecisionList,
        policy: EditTimingPolicy
    ) {
        deletedRanges = Self.makeDeletedRanges(
            transcript: transcript,
            edits: edits,
            policy: policy
        )
        keptRanges = Self.makeKeptRanges(
            deletedRanges: deletedRanges,
            totalDuration: transcript.duration,
            minimumDuration: policy.minimumKeptDuration
        )
        timelineMap = TimelineMap(keptRanges: keptRanges)
    }

    private static func makeDeletedRanges(
        transcript: SourceTranscript,
        edits: EditDecisionList,
        policy: EditTimingPolicy
    ) -> [TimeRange] {
        let words = transcript.words
        var ranges: [TimeRange] = []
        var index = 0

        while index < words.count {
            guard edits.contains(wordID: words[index].id) else {
                index += 1
                continue
            }

            let runStart = index
            while index < words.count, edits.contains(wordID: words[index].id) {
                index += 1
            }
            let runEnd = index - 1
            let first = words[runStart]
            let last = words[runEnd]

            let startPadding = first.isSilence && !policy.padsSilence ? 0 : policy.cutPadding
            let endPadding = last.isSilence && !policy.padsSilence ? 0 : policy.cutPadding
            let range = TimeRange(
                start: max(0, first.start - startPadding),
                end: last.end + endPadding
            )

            if let previous = ranges.last,
               range.start <= previous.end + policy.mergeTolerance {
                ranges[ranges.count - 1].end = max(previous.end, range.end)
            } else {
                ranges.append(range)
            }
        }

        return ranges
    }

    private static func makeKeptRanges(
        deletedRanges: [TimeRange],
        totalDuration: Double,
        minimumDuration: Double
    ) -> [TimeRange] {
        guard let firstDeletedRange = deletedRanges.first else {
            return [TimeRange(start: 0, end: totalDuration)]
        }

        var ranges: [TimeRange] = []

        if firstDeletedRange.start > 0 {
            ranges.append(TimeRange(start: 0, end: firstDeletedRange.start))
        }

        for pair in zip(deletedRanges, deletedRanges.dropFirst()) {
            let gapStart = pair.0.end
            let gapEnd = pair.1.start
            if gapEnd > gapStart + minimumDuration {
                ranges.append(TimeRange(start: gapStart, end: gapEnd))
            }
        }

        if let lastDeletedRange = deletedRanges.last,
           lastDeletedRange.end < totalDuration {
            ranges.append(TimeRange(start: lastDeletedRange.end, end: totalDuration))
        }

        return ranges
    }
}
