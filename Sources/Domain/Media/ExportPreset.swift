import Foundation

enum ExportMediaKind: String, Equatable, Sendable {
    case audio
    case video
}

struct ExportPreset: Equatable, Hashable, Sendable {
    let id: String
    let title: String
    let pathExtension: String
    let mediaKind: ExportMediaKind
    let videoCodec: String?
    let audioCodec: String

    var supportsVideoQuality: Bool {
        mediaKind == .video
    }

    func supportsStreamCopy(from mediaInfo: MediaInfo) -> Bool {
        guard let audioStream = mediaInfo.audioStream,
              audioStream.codecName == streamCodecName(for: audioCodec) else {
            return false
        }
        guard mediaKind == .video else { return true }
        guard let videoCodec,
              let videoStream = mediaInfo.videoStream else {
            return false
        }
        return videoStream.codecName == streamCodecName(for: videoCodec)
    }

    private func streamCodecName(for encoderName: String) -> String {
        switch encoderName {
        case "libx264": "h264"
        case "libvpx-vp9": "vp9"
        case "libmp3lame": "mp3"
        default: encoderName
        }
    }

    static let mp4Video = ExportPreset(
        id: "mp4-video",
        title: "MP4 Video (H.264 + AAC)",
        pathExtension: "mp4",
        mediaKind: .video,
        videoCodec: "libx264",
        audioCodec: "aac"
    )
    static let mkvVideo = ExportPreset(
        id: "mkv-video",
        title: "MKV Video (H.264 + AAC)",
        pathExtension: "mkv",
        mediaKind: .video,
        videoCodec: "libx264",
        audioCodec: "aac"
    )
    static let webMVideo = ExportPreset(
        id: "webm-video",
        title: "WebM Video (VP9 + Opus)",
        pathExtension: "webm",
        mediaKind: .video,
        videoCodec: "libvpx-vp9",
        audioCodec: "libopus"
    )
    static let m4aAudio = ExportPreset(
        id: "m4a-audio",
        title: "M4A Audio (AAC)",
        pathExtension: "m4a",
        mediaKind: .audio,
        videoCodec: nil,
        audioCodec: "aac"
    )
    static let mp3Audio = ExportPreset(
        id: "mp3-audio",
        title: "MP3 Audio",
        pathExtension: "mp3",
        mediaKind: .audio,
        videoCodec: nil,
        audioCodec: "libmp3lame"
    )
    static let wavAudio = ExportPreset(
        id: "wav-audio",
        title: "WAV Audio (PCM)",
        pathExtension: "wav",
        mediaKind: .audio,
        videoCodec: nil,
        audioCodec: "pcm_s16le"
    )
}

enum ExportCatalog {
    static let videoPresets: [ExportPreset] = [.mp4Video, .mkvVideo, .webMVideo]
    static let audioPresets: [ExportPreset] = [.m4aAudio, .mp3Audio, .wavAudio]

    static func presets(for mediaInfo: MediaInfo) -> [ExportPreset] {
        guard mediaInfo.hasAudio else { return [] }
        return (mediaInfo.hasVideo ? videoPresets : []) + audioPresets
    }
}
