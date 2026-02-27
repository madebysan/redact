import Foundation

/// A segment of the transcript containing a group of words.
struct Segment: Codable, Identifiable, Equatable {
    let id: Int
    var words: [Word]
}
