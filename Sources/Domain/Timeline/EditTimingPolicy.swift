import Foundation

struct EditTimingPolicy: Equatable, Sendable {
    let cutPadding: Double
    let mergeTolerance: Double
    let minimumKeptDuration: Double
    let padsSilence: Bool

    static let mediaV1 = EditTimingPolicy(
        cutPadding: CUT_PADDING,
        mergeTolerance: 0,
        minimumKeptDuration: 0.01,
        padsSilence: false
    )
}
