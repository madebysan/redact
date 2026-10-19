import CryptoKit
import Foundation

/// A Final Cut Pro XML 1.10 document with one asset for the source media
/// and one `asset-clip` per kept range on a single spine. Final Cut Pro and
/// DaVinci Resolve import it directly.
struct FCPXMLSidecar: Equatable, Sendable {
    let url: URL
    let contents: String
    let clipCount: Int
    let rate: TimecodeRate
}

enum FCPXMLSidecarBuilder {
    static let version = "1.10"

    /// Returns `nil` for audio-only sources; those receive only the EDL.
    static func make(
        outputURL: URL,
        sourceURL: URL,
        renderPlan: RenderPlan,
        mediaInfo: MediaInfo
    ) -> FCPXMLSidecar? {
        guard let video = mediaInfo.videoStream else { return nil }
        let rate = TimecodeRate.detect(video.constantFrameRate ?? video.averageFrameRate)
        let events = CutListEvents.make(renderPlan: renderPlan, rate: rate)
        let projectName = outputURL.deletingPathExtension().lastPathComponent
        let assetName = sourceURL.deletingPathExtension().lastPathComponent
        let tcFormat = rate.isDropFrame ? "DF" : "NDF"
        let assetFrames = rate.frameIndex(forSeconds: mediaInfo.duration)
        let sequenceFrames = events.last?.recordOutFrame ?? 0

        var formatAttributes = [
            "id=\"r1\"",
        ]
        if let name = formatName(rate: rate, width: video.width, height: video.height) {
            formatAttributes.append("name=\"\(name)\"")
        }
        formatAttributes.append("frameDuration=\"\(rate.rationalFrameDuration)\"")
        if let width = video.width, let height = video.height {
            formatAttributes.append("width=\"\(width)\"")
            formatAttributes.append("height=\"\(height)\"")
        }

        var assetAttributes = [
            "id=\"r2\"",
            "name=\"\(escape(assetName))\"",
            "uid=\"\(stableUID(for: sourceURL))\"",
            "start=\"0s\"",
            "duration=\"\(rate.rationalTime(forFrames: assetFrames))\"",
            "hasVideo=\"1\"",
            "format=\"r1\"",
        ]
        if let audio = mediaInfo.audioStream {
            assetAttributes.append("hasAudio=\"1\"")
            assetAttributes.append("audioSources=\"1\"")
            if let channels = audio.channels {
                assetAttributes.append("audioChannels=\"\(channels)\"")
            }
            if let sampleRate = audio.sampleRate {
                assetAttributes.append("audioRate=\"\(sampleRate)\"")
            }
        }

        var sequenceAttributes = [
            "format=\"r1\"",
            "duration=\"\(rate.rationalTime(forFrames: sequenceFrames))\"",
            "tcStart=\"0s\"",
            "tcFormat=\"\(tcFormat)\"",
        ]
        if let layout = audioLayout(channels: mediaInfo.audioStream?.channels) {
            sequenceAttributes.append("audioLayout=\"\(layout)\"")
        }
        if let audioRate = sequenceAudioRate(sampleRate: mediaInfo.audioStream?.sampleRate) {
            sequenceAttributes.append("audioRate=\"\(audioRate)\"")
        }

        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE fcpxml>",
            "<fcpxml version=\"\(version)\">",
            "    <resources>",
            "        <format \(formatAttributes.joined(separator: " "))/>",
            "        <asset \(assetAttributes.joined(separator: " "))>",
            "            <media-rep kind=\"original-media\" src=\"\(escape(sourceURL.absoluteString))\"/>",
            "        </asset>",
            "    </resources>",
            "    <library>",
            "        <event name=\"Redact\">",
            "            <project name=\"\(escape(projectName))\">",
            "                <sequence \(sequenceAttributes.joined(separator: " "))>",
            "                    <spine>",
        ]

        for event in events {
            lines.append(
                "                        <asset-clip ref=\"r2\" name=\"\(escape(assetName))\""
                    + " offset=\"\(rate.rationalTime(forFrames: event.recordInFrame))\""
                    + " start=\"\(rate.rationalTime(forFrames: event.sourceInFrame))\""
                    + " duration=\"\(rate.rationalTime(forFrames: event.frameCount))\""
                    + " tcFormat=\"\(tcFormat)\"/>"
            )
        }

        lines.append(contentsOf: [
            "                    </spine>",
            "                </sequence>",
            "            </project>",
            "        </event>",
            "    </library>",
            "</fcpxml>",
            "",
        ])

        return FCPXMLSidecar(
            url: outputURL.deletingPathExtension().appendingPathExtension("fcpxml"),
            contents: lines.joined(separator: "\n"),
            clipCount: events.count,
            rate: rate
        )
    }

    /// Final Cut Pro's own format names for the common broadcast sizes and
    /// rates; other combinations leave the name out and rely on the explicit
    /// frame duration and dimensions.
    static func formatName(rate: TimecodeRate, width: Int?, height: Int?) -> String? {
        guard let width, let height else { return nil }
        let size: String
        switch (width, height) {
        case (1280, 720): size = "720p"
        case (1920, 1080): size = "1080p"
        case (3840, 2160): size = "3840x2160"
        default: return nil
        }
        let rateName: String
        switch (rate.nominalFramesPerSecond, rate.frameDurationNumerator) {
        case (24, 1001): rateName = "2398"
        case (24, _): rateName = "24"
        case (25, _): rateName = "25"
        case (30, 1001): rateName = "2997"
        case (30, _): rateName = "30"
        case (50, _): rateName = "50"
        case (60, 1001): rateName = "5994"
        case (60, _): rateName = "60"
        default: return nil
        }
        return "FFVideoFormat\(size)\(rateName)"
    }

    private static func audioLayout(channels: Int?) -> String? {
        switch channels {
        case 1: "mono"
        case 2: "stereo"
        case 6: "surround"
        default: nil
        }
    }

    private static func sequenceAudioRate(sampleRate: Int?) -> String? {
        switch sampleRate {
        case 32_000: "32k"
        case 44_100: "44.1k"
        case 48_000: "48k"
        case 88_200: "88.2k"
        case 96_000: "96k"
        case 176_400: "176.4k"
        case 192_000: "192k"
        default: nil
        }
    }

    /// A deterministic asset identifier so re-exports of the same source
    /// relink to the same clip in Final Cut Pro.
    static func stableUID(for sourceURL: URL) -> String {
        let digest = SHA256.hash(data: Data(sourceURL.standardizedFileURL.path.utf8))
        let hex = digest.map { String(format: "%02X", $0) }.joined()
        let characters = Array(hex.prefix(32))
        let groups = [8, 4, 4, 4, 12]
        var cursor = 0
        return groups.map { length in
            defer { cursor += length }
            return String(characters[cursor..<cursor + length])
        }.joined(separator: "-")
    }

    static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
