import Foundation
import Testing
@testable import Redact

@Test func mediaInfoDecodesTypedFFprobeStreams() throws {
    let data = Data(
        """
        {
          "streams": [
            {"index": 0, "codec_name": "h264", "codec_type": "video", "width": 1920, "height": 1080, "avg_frame_rate": "30000/1001", "r_frame_rate": "30000/1001"},
            {"index": 1, "codec_name": "aac", "codec_type": "audio", "sample_rate": "48000", "channels": 2}
          ],
          "format": {"format_name": "mov,mp4,m4a,3gp,3g2,mj2", "duration": "12.5"}
        }
        """.utf8
    )

    let info = try MediaInfo.decodeFFprobeJSON(data)

    #expect(info.duration == 12.5)
    #expect(info.containerNames == ["mov", "mp4", "m4a", "3gp", "3g2", "mj2"])
    #expect(info.videoStream?.codecName == "h264")
    #expect(info.videoStream?.width == 1920)
    #expect(info.videoStream?.height == 1080)
    #expect(abs((info.videoStream?.constantFrameRate ?? 0) - 29.970) < 0.001)
    #expect(info.audioStream?.codecName == "aac")
    #expect(info.audioStream?.sampleRate == 48_000)
    #expect(info.audioStream?.channels == 2)
}

@Test func mediaInfoDecodesUnnamedDataStreams() throws {
    let data = Data(
        """
        {
          "streams": [
            {"index": 0, "codec_name": "hevc", "codec_type": "video", "width": 1920, "height": 1080, "avg_frame_rate": "24000/1001", "r_frame_rate": "24000/1001"},
            {"index": 1, "codec_name": "aac", "codec_type": "audio", "sample_rate": "48000", "channels": 2},
            {"index": 2, "codec_type": "data", "avg_frame_rate": "0/0", "r_frame_rate": "0/0"}
          ],
          "format": {"format_name": "mov,mp4,m4a,3gp,3g2,mj2", "duration": "7577.45"}
        }
        """.utf8
    )

    let info = try MediaInfo.decodeFFprobeJSON(data)

    #expect(info.duration == 7_577.45)
    #expect(info.videoStream?.codecName == "hevc")
    #expect(info.audioStream?.codecName == "aac")
    #expect(info.streams.last?.kind == .other)
    #expect(info.streams.last?.codecName == "unknown")
}

@Test func exportCatalogOffersOnlyValidPresetsForMediaCapabilities() {
    let audioVideo = MediaInfo(
        duration: 1,
        containerNames: ["mov"],
        streams: [
            MediaStreamInfo(index: 0, kind: .video, codecName: "h264", width: 1920, height: 1080),
            MediaStreamInfo(index: 1, kind: .audio, codecName: "aac", sampleRate: 48_000, channels: 2),
        ]
    )
    let audioOnly = MediaInfo(
        duration: 1,
        containerNames: ["mp3"],
        streams: [
            MediaStreamInfo(index: 0, kind: .audio, codecName: "mp3", sampleRate: 44_100, channels: 2),
        ]
    )

    #expect(ExportCatalog.presets(for: audioVideo).map(\.id) == [
        "mp4-video", "mkv-video", "webm-video", "m4a-audio", "mp3-audio", "wav-audio",
    ])
    #expect(ExportCatalog.presets(for: audioOnly).map(\.id) == [
        "m4a-audio", "mp3-audio", "wav-audio",
    ])
}

@Test func exportCatalogDefinesTruthfulContainerAndCodecPairs() {
    #expect(ExportPreset.mp4Video.videoCodec == "libx264")
    #expect(ExportPreset.mp4Video.audioCodec == "aac")
    #expect(ExportPreset.webMVideo.videoCodec == "libvpx-vp9")
    #expect(ExportPreset.webMVideo.audioCodec == "libopus")
    #expect(ExportPreset.m4aAudio.videoCodec == nil)
    #expect(ExportPreset.m4aAudio.audioCodec == "aac")
    #expect(ExportPreset.mp3Audio.audioCodec == "libmp3lame")
    #expect(ExportPreset.wavAudio.audioCodec == "pcm_s16le")
}
