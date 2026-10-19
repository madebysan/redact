import Foundation

/// A timecode base derived from the source media frame rate.
///
/// `framesPerSecond` is the exact rate used to convert seconds to frame
/// indexes. `nominalFramesPerSecond` is the integer base that timecode
/// digits count in (30 for 29.97 drop-frame). `frameDuration` is the
/// rational frame length written to FCPXML.
struct TimecodeRate: Equatable, Sendable {
    let framesPerSecond: Double
    let nominalFramesPerSecond: Int
    let frameDurationNumerator: Int
    let frameDurationDenominator: Int
    let isDropFrame: Bool

    static let fallback = TimecodeRate(
        framesPerSecond: 30,
        nominalFramesPerSecond: 30,
        frameDurationNumerator: 100,
        frameDurationDenominator: 3000,
        isDropFrame: false
    )

    /// Map a probed frame rate to a timecode base. NTSC rates (23.976,
    /// 29.97, 59.94) use 1001-based frame durations; 29.97 and 59.94 count in
    /// drop-frame timecode. Unknown or missing rates fall back to 30 fps
    /// non-drop.
    static func detect(_ frameRate: Double?) -> TimecodeRate {
        guard let frameRate, frameRate.isFinite, frameRate > 0 else { return .fallback }

        let ntscRates: [(nominal: Int, dropFrame: Bool)] = [
            (24, false), (30, true), (48, false), (60, true),
        ]
        for rate in ntscRates {
            let exact = Double(rate.nominal) * 1000 / 1001
            if abs(frameRate - exact) < 0.01 {
                return TimecodeRate(
                    framesPerSecond: exact,
                    nominalFramesPerSecond: rate.nominal,
                    frameDurationNumerator: 1001,
                    frameDurationDenominator: rate.nominal * 1000,
                    isDropFrame: rate.dropFrame
                )
            }
        }

        let rounded = frameRate.rounded()
        if abs(frameRate - rounded) < 0.01, rounded >= 1 {
            let nominal = Int(rounded)
            return TimecodeRate(
                framesPerSecond: rounded,
                nominalFramesPerSecond: nominal,
                frameDurationNumerator: 100,
                frameDurationDenominator: nominal * 100,
                isDropFrame: false
            )
        }

        let denominator = Int((frameRate * 1000).rounded())
        return TimecodeRate(
            framesPerSecond: Double(denominator) / 1000,
            nominalFramesPerSecond: max(1, Int(frameRate.rounded(.up))),
            frameDurationNumerator: 1000,
            frameDurationDenominator: denominator,
            isDropFrame: false
        )
    }

    var frameDurationSeconds: Double {
        Double(frameDurationNumerator) / Double(frameDurationDenominator)
    }

    /// Nearest whole frame for a time in seconds.
    func frameIndex(forSeconds seconds: Double) -> Int {
        Int((max(0, seconds) * framesPerSecond).rounded())
    }

    func seconds(forFrames frames: Int) -> Double {
        Double(frames) / framesPerSecond
    }

    /// Rational FCPXML time for a whole number of frames, such as `3003/30000s`.
    func rationalTime(forFrames frames: Int) -> String {
        guard frames > 0 else { return "0s" }
        let numerator = frames * frameDurationNumerator
        let divisor = Self.greatestCommonDivisor(numerator, frameDurationDenominator)
        let reducedNumerator = numerator / divisor
        let reducedDenominator = frameDurationDenominator / divisor
        return reducedDenominator == 1
            ? "\(reducedNumerator)s"
            : "\(reducedNumerator)/\(reducedDenominator)s"
    }

    /// Rational FCPXML frame duration, such as `1001/30000s` or `100/2500s`.
    var rationalFrameDuration: String {
        "\(frameDurationNumerator)/\(frameDurationDenominator)s"
    }

    /// `HH:MM:SS:FF` timecode for a frame index, or `HH:MM:SS;FF` at a
    /// drop-frame rate. Drop-frame counting skips the first two (29.97) or
    /// four (59.94) frame numbers of every minute that is not a multiple of
    /// ten, so the displayed clock stays aligned with real time.
    func timecode(forFrames frames: Int) -> String {
        let frames = max(0, frames)
        let nominal = nominalFramesPerSecond
        var counted = frames

        if isDropFrame {
            let droppedPerMinute = Int((Double(nominal) * 0.0666666).rounded())
            let framesPerTenMinutes = Int((framesPerSecond * 600).rounded())
            let framesPerMinute = nominal * 60 - droppedPerMinute
            let tenMinuteBlocks = frames / framesPerTenMinutes
            let remainder = frames % framesPerTenMinutes
            counted += droppedPerMinute * 9 * tenMinuteBlocks
            if remainder > droppedPerMinute {
                counted += droppedPerMinute * ((remainder - droppedPerMinute) / framesPerMinute)
            }
        }

        let frameDigits = counted % nominal
        let totalSeconds = counted / nominal
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        let separator = isDropFrame ? ";" : ":"
        return String(
            format: "%02d:%02d:%02d%@%02d",
            hours, minutes, seconds, separator, frameDigits
        )
    }

    private static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var a = abs(a)
        var b = abs(b)
        while b != 0 {
            (a, b) = (b, a % b)
        }
        return max(1, a)
    }
}

/// One kept range expressed in whole frames on both the source and the
/// edited (record) timelines. Record times come from the `TimelineMap`, and
/// each event keeps the same frame count on both sides so the edited
/// timeline stays contiguous.
struct CutListEvent: Equatable, Sendable {
    let sourceInFrame: Int
    let sourceOutFrame: Int
    let recordInFrame: Int
    let recordOutFrame: Int

    var frameCount: Int { recordOutFrame - recordInFrame }
}

enum CutListEvents {
    /// Quantize the canonical kept ranges to whole frames. Ranges shorter
    /// than one frame after rounding are dropped because no editor can
    /// represent them.
    static func make(renderPlan: RenderPlan, rate: TimecodeRate) -> [CutListEvent] {
        renderPlan.timelineMap.mappings.compactMap { mapping in
            let recordIn = rate.frameIndex(forSeconds: mapping.edited.start)
            let recordOut = rate.frameIndex(forSeconds: mapping.edited.end)
            guard recordOut > recordIn else { return nil }
            let sourceIn = rate.frameIndex(forSeconds: mapping.source.start)
            return CutListEvent(
                sourceInFrame: sourceIn,
                sourceOutFrame: sourceIn + (recordOut - recordIn),
                recordInFrame: recordIn,
                recordOutFrame: recordOut
            )
        }
    }
}
