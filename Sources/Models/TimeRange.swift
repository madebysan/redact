import Foundation

/// A time range with start and end in seconds.
struct TimeRange: Codable, Equatable {
    var start: Double
    var end: Double

    var duration: Double {
        end - start
    }
}
