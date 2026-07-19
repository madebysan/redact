import Foundation

/// Read-only review metadata derived from the canonical edited timeline.
struct EditReviewModel: Equatable, Sendable {
    static let defaultPreRoll: Double = 1.5

    let cutCount: Int
    let removedDuration: Double
    let finalDuration: Double
    let reviewTargets: [Double]

    init(
        renderPlan: RenderPlan,
        sourceDuration: Double,
        preRoll: Double = Self.defaultPreRoll
    ) {
        cutCount = renderPlan.deletedRanges.count
        removedDuration = max(0, sourceDuration - renderPlan.editedDuration)
        finalDuration = renderPlan.editedDuration

        let boundedPreRoll = max(0, preRoll)
        var targets: [Double] = []
        for range in renderPlan.deletedRanges {
            let transitionTime = renderPlan.timelineMap.editedTime(forSourceTime: range.start)
            let target = max(0, transitionTime - boundedPreRoll)
            if let last = targets.last, abs(last - target) < 0.02 {
                continue
            }
            targets.append(target)
        }
        reviewTargets = targets
    }

    func previousTarget(from editedTime: Double) -> Double? {
        reviewTargets.last { $0 < editedTime - 0.02 }
    }

    func nextTarget(from editedTime: Double) -> Double? {
        reviewTargets.first { $0 > editedTime + 0.02 }
    }
}
