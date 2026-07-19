import Foundation

struct TimelineMapping: Equatable, Sendable {
    let source: TimeRange
    let edited: TimeRange
}

struct TimelineMap: Equatable, Sendable {
    let mappings: [TimelineMapping]
    let editedDuration: Double

    init(keptRanges: [TimeRange]) {
        var editedCursor = 0.0
        mappings = keptRanges.map { sourceRange in
            let duration = max(0, sourceRange.duration)
            let editedRange = TimeRange(
                start: editedCursor,
                end: editedCursor + duration
            )
            editedCursor = editedRange.end
            return TimelineMapping(source: sourceRange, edited: editedRange)
        }
        editedDuration = editedCursor
    }

    func editedTime(forSourceTime sourceTime: Double) -> Double {
        guard let first = mappings.first else { return 0 }

        if sourceTime <= first.source.start {
            return first.edited.start
        }

        for mapping in mappings {
            if sourceTime < mapping.source.start {
                return mapping.edited.start
            }
            if sourceTime <= mapping.source.end {
                return mapping.edited.start + sourceTime - mapping.source.start
            }
        }

        return editedDuration
    }

    func sourceTime(forEditedTime editedTime: Double) -> Double {
        guard let first = mappings.first else { return 0 }

        if editedTime <= first.edited.start {
            return first.source.start
        }

        for (index, mapping) in mappings.enumerated() {
            if editedTime < mapping.edited.start {
                return mapping.source.start
            }
            let isLastMapping = index == mappings.count - 1
            if editedTime < mapping.edited.end
                || (isLastMapping && editedTime <= mapping.edited.end) {
                return mapping.source.start + editedTime - mapping.edited.start
            }
        }

        return mappings.last?.source.end ?? 0
    }
}
