import Foundation

/// A CMX3600 edit decision list describing the current edit as cuts from
/// the original source file. Premiere Pro and DaVinci Resolve import it
/// directly and relink the `FROM CLIP NAME` to the source media.
struct EDLSidecar: Equatable, Sendable {
    let url: URL
    let contents: String
    let eventCount: Int
    let rate: TimecodeRate
}

enum EDLSidecarBuilder {
    static func make(
        outputURL: URL,
        sourceURL: URL,
        renderPlan: RenderPlan,
        mediaInfo: MediaInfo
    ) -> EDLSidecar {
        let videoRate = mediaInfo.videoStream.flatMap {
            $0.constantFrameRate ?? $0.averageFrameRate
        }
        return make(
            outputURL: outputURL,
            sourceURL: sourceURL,
            renderPlan: renderPlan,
            rate: TimecodeRate.detect(videoRate),
            hasVideo: mediaInfo.hasVideo
        )
    }

    static func make(
        outputURL: URL,
        sourceURL: URL,
        renderPlan: RenderPlan,
        rate: TimecodeRate,
        hasVideo: Bool
    ) -> EDLSidecar {
        let events = CutListEvents.make(renderPlan: renderPlan, rate: rate)
        let title = outputURL.deletingPathExtension().lastPathComponent
        let clipName = sourceURL.lastPathComponent
        let track = hasVideo ? "AA/V" : "AA"

        var lines: [String] = [
            "TITLE: \(sanitize(title))",
            "FCM: \(rate.isDropFrame ? "DROP FRAME" : "NON-DROP FRAME")",
            "",
        ]

        for (index, event) in events.enumerated() {
            lines.append([
                String(format: "%03d ", index + 1),
                pad("AX", to: 8),
                pad(track, to: 5),
                pad("C", to: 8),
                rate.timecode(forFrames: event.sourceInFrame),
                rate.timecode(forFrames: event.sourceOutFrame),
                rate.timecode(forFrames: event.recordInFrame),
                rate.timecode(forFrames: event.recordOutFrame),
            ].joined(separator: " "))
            lines.append("* FROM CLIP NAME: \(sanitize(clipName))")
            lines.append("")
        }

        return EDLSidecar(
            url: outputURL.deletingPathExtension().appendingPathExtension("edl"),
            contents: lines.joined(separator: "\n"),
            eventCount: events.count,
            rate: rate
        )
    }

    /// CMX3600 readers expect fixed-width columns.
    private static func pad(_ value: String, to width: Int) -> String {
        value + String(repeating: " ", count: max(0, width - value.count))
    }

    /// EDL lines are single-line ASCII-tolerant text; strip line breaks so a
    /// file name can never split an event.
    private static func sanitize(_ value: String) -> String {
        value
            .components(separatedBy: .newlines)
            .joined(separator: " ")
    }
}
