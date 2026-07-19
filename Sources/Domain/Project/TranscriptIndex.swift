import Foundation

struct TranscriptIndex: Sendable {
    private let positionsByID: [String: Int]

    init(transcript: SourceTranscript) {
        positionsByID = Dictionary(
            uniqueKeysWithValues: transcript.words.enumerated().map { ($0.element.id, $0.offset) }
        )
    }

    func position(forWordID id: String) -> Int? {
        positionsByID[id]
    }

    func positions(forWordIDs ids: Set<String>) -> [Int] {
        ids.compactMap { positionsByID[$0] }.sorted()
    }

    func closedRange(fromWordID: String, toWordID: String) -> ClosedRange<Int>? {
        guard let fromPosition = positionsByID[fromWordID],
              let toPosition = positionsByID[toWordID] else {
            return nil
        }
        return min(fromPosition, toPosition)...max(fromPosition, toPosition)
    }
}
