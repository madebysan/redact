import Foundation

/// A single word in the transcript with timing and state information.
struct Word: Codable, Identifiable, Equatable {
    let id: String
    var word: String
    var start: Double
    var end: Double
    var confidence: Double
    var deleted: Bool
    var isSilence: Bool?

    var isActualSilence: Bool {
        isSilence == true
    }
}
