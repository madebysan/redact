import Foundation

enum MediaStreamKind: String, Codable, Equatable, Sendable {
    case audio
    case video
    case other
}

struct MediaStreamInfo: Codable, Equatable, Sendable {
    let index: Int
    let kind: MediaStreamKind
    let codecName: String
    let width: Int?
    let height: Int?
    let averageFrameRate: Double?
    let realFrameRate: Double?
    let sampleRate: Int?
    let channels: Int?

    var constantFrameRate: Double? {
        guard kind == .video,
              let averageFrameRate,
              let realFrameRate,
              averageFrameRate.isFinite,
              realFrameRate.isFinite,
              averageFrameRate > 0,
              realFrameRate > 0 else {
            return nil
        }
        let relativeDifference = abs(averageFrameRate - realFrameRate)
            / max(averageFrameRate, realFrameRate)
        guard relativeDifference < 0.002 else { return nil }
        return averageFrameRate
    }

    init(
        index: Int,
        kind: MediaStreamKind,
        codecName: String,
        width: Int? = nil,
        height: Int? = nil,
        averageFrameRate: Double? = nil,
        realFrameRate: Double? = nil,
        sampleRate: Int? = nil,
        channels: Int? = nil
    ) {
        self.index = index
        self.kind = kind
        self.codecName = codecName
        self.width = width
        self.height = height
        self.averageFrameRate = averageFrameRate
        self.realFrameRate = realFrameRate
        self.sampleRate = sampleRate
        self.channels = channels
    }
}

struct MediaInfo: Codable, Equatable, Sendable {
    let duration: Double
    let containerNames: [String]
    let streams: [MediaStreamInfo]

    var videoStream: MediaStreamInfo? {
        streams.first { $0.kind == .video }
    }

    var audioStream: MediaStreamInfo? {
        streams.first { $0.kind == .audio }
    }

    var hasVideo: Bool { videoStream != nil }
    var hasAudio: Bool { audioStream != nil }

    static func decodeFFprobeJSON(_ data: Data) throws -> MediaInfo {
        let response: FFprobeResponse
        do {
            response = try JSONDecoder().decode(FFprobeResponse.self, from: data)
        } catch {
            throw MediaInfoError.invalidProbeData
        }

        let duration = response.format.duration.flatMap(Double.init) ?? 0
        guard duration.isFinite, duration >= 0 else {
            throw MediaInfoError.invalidProbeData
        }

        return MediaInfo(
            duration: duration,
            containerNames: response.format.formatName
                .split(separator: ",")
                .map(String.init),
            streams: response.streams.map { stream in
                let kind = MediaStreamKind(rawValue: stream.codecType) ?? .other
                return MediaStreamInfo(
                    index: stream.index,
                    kind: kind,
                    codecName: stream.codecName ?? "unknown",
                    width: stream.width,
                    height: stream.height,
                    averageFrameRate: parseRational(stream.averageFrameRate),
                    realFrameRate: parseRational(stream.realFrameRate),
                    sampleRate: stream.sampleRate.flatMap(Int.init),
                    channels: stream.channels
                )
            }
        )
    }

    private static func parseRational(_ value: String?) -> Double? {
        guard let value else { return nil }
        let parts = value.split(separator: "/", maxSplits: 1)
        guard parts.count == 2,
              let numerator = Double(parts[0]),
              let denominator = Double(parts[1]),
              denominator != 0 else {
            return nil
        }
        let result = numerator / denominator
        return result.isFinite && result > 0 ? result : nil
    }
}

private struct FFprobeResponse: Decodable {
    let streams: [FFprobeStream]
    let format: FFprobeFormat
}

private struct FFprobeStream: Decodable {
    let index: Int
    let codecName: String?
    let codecType: String
    let width: Int?
    let height: Int?
    let averageFrameRate: String?
    let realFrameRate: String?
    let sampleRate: String?
    let channels: Int?

    private enum CodingKeys: String, CodingKey {
        case index
        case codecName = "codec_name"
        case codecType = "codec_type"
        case width
        case height
        case averageFrameRate = "avg_frame_rate"
        case realFrameRate = "r_frame_rate"
        case sampleRate = "sample_rate"
        case channels
    }
}

private struct FFprobeFormat: Decodable {
    let formatName: String
    let duration: String?

    private enum CodingKeys: String, CodingKey {
        case formatName = "format_name"
        case duration
    }
}

enum MediaInfoError: LocalizedError {
    case invalidProbeData

    var errorDescription: String? {
        "FFprobe returned invalid media information."
    }
}
