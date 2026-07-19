import Foundation
import Testing
@testable import Redact

private struct RealMediaFeatureCase {
    let id: String
    let preset: ExportPreset
    let segments: [TimeRange]
    let quality: String?
    let speed: Double
    let enhanceAudio: Bool
    let sourceIsUnchanged: Bool
}

private struct RealMediaFeatureResult: Codable {
    let id: String
    let presetID: String
    let quality: String?
    let speed: Double
    let enhanceAudio: Bool
    let expectedDurationSeconds: Double
    let outputDurationSeconds: Double
    let durationDeltaSeconds: Double
    let exportMilliseconds: Double
    let outputSizeBytes: Int64
    let videoCodec: String?
    let videoHeight: Int?
    let audioCodec: String?
}

private struct RealMediaFeatureReport: Codable {
    let schemaVersion: Int
    let sourceDurationSeconds: Double
    let sourceVideoCodec: String?
    let sourceVideoHeight: Int?
    let sourceAudioCodec: String?
    let results: [RealMediaFeatureResult]
}

private struct GeneratedCompatibilityCase {
    let id: String
    let sourceURL: URL
    let expectedVideoCodec: String?
    let expectedStrategy: FFmpegExportStrategy
}

@Test func ffmpegExportIntegrationRendersEveryOfferedPreset() async throws {
    guard ProcessInfo.processInfo.environment["REDACT_RUN_EXPORT_INTEGRATION"] == "1" else {
        return
    }
    guard let ffmpeg = PathUtilities.findFFmpeg() else {
        Issue.record("FFmpeg is required for the export integration test")
        return
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-export-integration-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let inputURL = directory.appendingPathComponent("source.mp4")
    let generator = Process()
    generator.executableURL = URL(fileURLWithPath: ffmpeg)
    generator.arguments = [
        "-nostdin",
        "-f", "lavfi", "-i", "color=c=black:s=320x180:d=3",
        "-f", "lavfi", "-i", "sine=frequency=440:duration=3",
        "-c:v", "libx264", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-shortest", "-y", inputURL.path,
    ]
    generator.standardOutput = FileHandle.nullDevice
    generator.standardError = FileHandle.nullDevice
    try generator.run()
    generator.waitUntilExit()
    #expect(generator.terminationStatus == 0)

    let service = FFmpegService()
    let sourceInfo = try await service.getMediaInfo(
        filePath: inputURL.path,
        operation: ProcessOperation()
    )
    for preset in ExportCatalog.videoPresets + ExportCatalog.audioPresets {
        let outputURL = directory.appendingPathComponent("output." + preset.pathExtension)
        try await service.exportMedia(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            segments: [
                TimeRange(start: 0, end: 1),
                TimeRange(start: 2, end: 3),
            ],
            preset: preset,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: false,
            quality: preset.supportsVideoQuality ? "720p" : nil,
            speed: 1,
            enhanceAudio: true,
            operation: ProcessOperation(),
            onProgress: nil,
            totalDuration: 2
        )

        let outputInfo = try await service.getMediaInfo(
            filePath: outputURL.path,
            operation: ProcessOperation()
        )
        #expect(outputInfo.hasAudio)
        #expect(outputInfo.hasVideo == (preset.mediaKind == .video))
    }
}

/// Opt-in background feature matrix for explicitly supplied private media.
/// The report contains aggregate media properties and timings, never source paths
/// or filenames. Rendered outputs stay in the caller-provided private directory.
@Test func realMediaFeatureMatrix() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["RUN_REDACT_REAL_MEDIA_FEATURE_MATRIX"] == "1" else {
        return
    }
    guard let inputPath = environment["REDACT_REAL_MEDIA_FEATURE_SOURCE"],
          let outputDirectoryPath = environment["REDACT_REAL_MEDIA_FEATURE_OUTPUT_DIR"],
          let reportPath = environment["REDACT_REAL_MEDIA_FEATURE_REPORT"] else {
        Issue.record("Real-media feature matrix requires source, output directory, and report paths")
        return
    }
    guard FileManager.default.isReadableFile(atPath: inputPath),
          PathUtilities.findFFmpeg() != nil else {
        Issue.record("Real-media feature source or FFmpeg is unavailable")
        return
    }

    let outputDirectory = URL(fileURLWithPath: outputDirectoryPath, isDirectory: true)
    guard !FileManager.default.fileExists(atPath: outputDirectory.path) else {
        Issue.record("Real-media feature output directory must not already exist")
        return
    }
    try FileManager.default.createDirectory(
        at: outputDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )

    let service = FFmpegService()
    let sourceInfo = try await service.getMediaInfo(
        filePath: inputPath,
        operation: ProcessOperation()
    )
    guard sourceInfo.hasAudio, sourceInfo.hasVideo else {
        Issue.record("Real-media feature matrix requires video with audio")
        return
    }

    let fullRange = TimeRange(start: 0, end: sourceInfo.duration)
    let editedEnd = min(sourceInfo.duration, 60)
    guard editedEnd >= 45 else {
        Issue.record("Real-media feature source must be at least 45 seconds")
        return
    }
    let editedRanges = [
        TimeRange(start: 0, end: 20),
        TimeRange(start: 30, end: editedEnd),
    ]
    let testCases = [
        RealMediaFeatureCase(
            id: "mp4-unchanged-plain",
            preset: .mp4Video,
            segments: [fullRange],
            quality: nil,
            speed: 1,
            enhanceAudio: false,
            sourceIsUnchanged: true
        ),
        RealMediaFeatureCase(
            id: "mp4-unchanged-enhanced",
            preset: .mp4Video,
            segments: [fullRange],
            quality: nil,
            speed: 1,
            enhanceAudio: true,
            sourceIsUnchanged: true
        ),
        RealMediaFeatureCase(
            id: "mp4-edited-720-enhanced",
            preset: .mp4Video,
            segments: editedRanges,
            quality: "720p",
            speed: 1,
            enhanceAudio: true,
            sourceIsUnchanged: false
        ),
        RealMediaFeatureCase(
            id: "mp4-edited-speed-125",
            preset: .mp4Video,
            segments: editedRanges,
            quality: "720p",
            speed: 1.25,
            enhanceAudio: true,
            sourceIsUnchanged: false
        ),
        RealMediaFeatureCase(
            id: "mkv-edited-enhanced",
            preset: .mkvVideo,
            segments: editedRanges,
            quality: "720p",
            speed: 1,
            enhanceAudio: true,
            sourceIsUnchanged: false
        ),
        RealMediaFeatureCase(
            id: "webm-edited-enhanced",
            preset: .webMVideo,
            segments: editedRanges,
            quality: "720p",
            speed: 1,
            enhanceAudio: true,
            sourceIsUnchanged: false
        ),
        RealMediaFeatureCase(
            id: "m4a-edited-enhanced",
            preset: .m4aAudio,
            segments: editedRanges,
            quality: nil,
            speed: 1,
            enhanceAudio: true,
            sourceIsUnchanged: false
        ),
        RealMediaFeatureCase(
            id: "mp3-edited-plain",
            preset: .mp3Audio,
            segments: editedRanges,
            quality: nil,
            speed: 1,
            enhanceAudio: false,
            sourceIsUnchanged: false
        ),
        RealMediaFeatureCase(
            id: "mp3-edited-enhanced",
            preset: .mp3Audio,
            segments: editedRanges,
            quality: nil,
            speed: 1,
            enhanceAudio: true,
            sourceIsUnchanged: false
        ),
        RealMediaFeatureCase(
            id: "wav-edited-enhanced",
            preset: .wavAudio,
            segments: editedRanges,
            quality: nil,
            speed: 1,
            enhanceAudio: true,
            sourceIsUnchanged: false
        ),
    ]

    var results: [RealMediaFeatureResult] = []
    for testCase in testCases {
        let outputURL = outputDirectory.appendingPathComponent(
            testCase.id + "." + testCase.preset.pathExtension
        )
        let sourceDuration = testCase.segments.reduce(0) { $0 + $1.duration }
        let expectedDuration = sourceDuration / testCase.speed
        let exportStart = Date.timeIntervalSinceReferenceDate
        try await service.exportMedia(
            inputPath: inputPath,
            outputPath: outputURL.path,
            segments: testCase.segments,
            preset: testCase.preset,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: testCase.sourceIsUnchanged,
            quality: testCase.quality,
            speed: testCase.speed,
            enhanceAudio: testCase.enhanceAudio,
            operation: ProcessOperation(),
            onProgress: nil,
            totalDuration: expectedDuration
        )
        let exportMilliseconds = (Date.timeIntervalSinceReferenceDate - exportStart) * 1_000
        let outputInfo = try await service.getMediaInfo(
            filePath: outputURL.path,
            operation: ProcessOperation()
        )
        let durationDelta = abs(outputInfo.duration - expectedDuration)
        #expect(outputInfo.hasAudio)
        #expect(outputInfo.hasVideo == (testCase.preset.mediaKind == .video))
        #expect(durationDelta <= 0.35)
        if testCase.quality == "720p", testCase.preset.mediaKind == .video {
            #expect(outputInfo.videoStream?.height == 720)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outputURL.path
        )
        let outputSize = try outputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        results.append(
            RealMediaFeatureResult(
                id: testCase.id,
                presetID: testCase.preset.id,
                quality: testCase.quality,
                speed: testCase.speed,
                enhanceAudio: testCase.enhanceAudio,
                expectedDurationSeconds: expectedDuration,
                outputDurationSeconds: outputInfo.duration,
                durationDeltaSeconds: durationDelta,
                exportMilliseconds: exportMilliseconds,
                outputSizeBytes: Int64(outputSize),
                videoCodec: outputInfo.videoStream?.codecName,
                videoHeight: outputInfo.videoStream?.height,
                audioCodec: outputInfo.audioStream?.codecName
            )
        )
    }

    let report = RealMediaFeatureReport(
        schemaVersion: 1,
        sourceDurationSeconds: sourceInfo.duration,
        sourceVideoCodec: sourceInfo.videoStream?.codecName,
        sourceVideoHeight: sourceInfo.videoStream?.height,
        sourceAudioCodec: sourceInfo.audioStream?.codecName,
        results: results
    )
    let reportURL = URL(fileURLWithPath: reportPath)
    try FileManager.default.createDirectory(
        at: reportURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: reportURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: reportURL.path
    )
}

@Test func mediaRenderingCutCountBenchmark() async throws {
    guard ProcessInfo.processInfo.environment["RUN_REDACT_MEDIA_BENCHMARKS"] == "1" else {
        return
    }
    guard let ffmpeg = PathUtilities.findFFmpeg() else {
        Issue.record("FFmpeg is required for the media rendering benchmark")
        return
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-media-benchmark-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let sourceDuration = 12.0
    let inputURL = directory.appendingPathComponent("source.mp4")
    try makeSyntheticVideo(
        at: inputURL,
        duration: sourceDuration,
        ffmpegPath: ffmpeg
    )

    let service = FFmpegService()
    let sourceInfo = try await service.getMediaInfo(
        filePath: inputURL.path,
        operation: ProcessOperation()
    )
    for cutCount in [0, 10, 100, 500] {
        let keptRanges = benchmarkKeptRanges(
            duration: sourceDuration,
            cutCount: cutCount
        )
        let expectedDuration = keptRanges.reduce(0) { $0 + $1.duration }

        let previewStart = Date.timeIntervalSinceReferenceDate
        let preview = try await AVPreviewCompositionBuilder().build(
            sourceURL: inputURL,
            keptRanges: keptRanges
        )
        let previewElapsed = Date.timeIntervalSinceReferenceDate - previewStart
        let previewDuration = try await preview.asset.load(.duration).seconds

        let outputURL = directory.appendingPathComponent("output-\(cutCount).mp4")
        let exportStart = Date.timeIntervalSinceReferenceDate
        try await service.exportMedia(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            segments: keptRanges,
            preset: .mp4Video,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: cutCount == 0,
            quality: nil,
            speed: 1,
            enhanceAudio: false,
            operation: ProcessOperation(),
            onProgress: nil,
            totalDuration: expectedDuration
        )
        let exportElapsed = Date.timeIntervalSinceReferenceDate - exportStart
        let outputInfo = try await service.getMediaInfo(
            filePath: outputURL.path,
            operation: ProcessOperation()
        )

        // Hundreds of sub-frame synthetic ranges accumulate AVFoundation rounding.
        #expect(abs(previewDuration - expectedDuration) < 0.6)
        #expect(abs(outputInfo.duration - expectedDuration) < 0.15)
        #expect(outputInfo.hasVideo)
        #expect(outputInfo.hasAudio)
        print(
            String(
                format: "REDACT_MEDIA_BENCHMARK cuts=%d kept_ranges=%d expected_s=%.3f preview_s=%.3f output_s=%.3f preview_ms=%.3f export_ms=%.3f",
                cutCount,
                keptRanges.count,
                expectedDuration,
                previewDuration,
                outputInfo.duration,
                previewElapsed * 1_000,
                exportElapsed * 1_000
            )
        )
    }
}

/// Opt-in regression coverage for the batched path used by selections above
/// FFmpegExportPlan.selectionFilterMaximumRangeCount. This intentionally runs
/// real FFmpeg processes because duration, cancellation, and temporary-file
/// cleanup cannot be proven by argument-plan tests alone.
@Test func batchedExportIntegrationPreservesDurationAndCleansWorkspaces() async throws {
    guard ProcessInfo.processInfo.environment["REDACT_RUN_BATCHED_EXPORT_INTEGRATION"] == "1" else {
        return
    }
    guard let ffmpeg = PathUtilities.findFFmpeg() else {
        Issue.record("FFmpeg is required for the batched export integration test")
        return
    }

    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("redact-batched-export-integration-" + UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }

    let inputURL = directory.appendingPathComponent("source.mp4")
    try makeSyntheticVideo(at: inputURL, duration: 12, ffmpegPath: ffmpeg)

    let service = FFmpegService()
    let sourceInfo = try await service.getMediaInfo(
        filePath: inputURL.path,
        operation: ProcessOperation()
    )
    let keptRanges = benchmarkKeptRanges(duration: sourceInfo.duration, cutCount: 500)
    #expect(keptRanges.count > FFmpegExportPlan.selectionFilterMaximumRangeCount)

    let workspaceRoot = fileManager.temporaryDirectory
        .appendingPathComponent("redact-export-batches", isDirectory: true)
    let baselineWorkspaces = try batchWorkspaceNames(in: workspaceRoot, fileManager: fileManager)
    let rawKeptDuration = keptRanges.reduce(0) { $0 + $1.duration }

    for speed in [0.5, 1.0, 1.25, 2.0] {
        let expectedDuration = rawKeptDuration / speed
        let outputURL = directory.appendingPathComponent("speed-\(speed).mp4")
        try await service.exportMedia(
            inputPath: inputURL.path,
            outputPath: outputURL.path,
            segments: keptRanges,
            preset: .mp4Video,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: false,
            quality: nil,
            speed: speed,
            enhanceAudio: false,
            operation: ProcessOperation(),
            onProgress: nil,
            totalDuration: expectedDuration
        )

        let outputInfo = try await service.getMediaInfo(
            filePath: outputURL.path,
            operation: ProcessOperation()
        )
        #expect(outputInfo.hasVideo)
        #expect(outputInfo.hasAudio)
        #expect(abs(outputInfo.duration - expectedDuration) <= 0.25)
        #expect(try batchWorkspaceNames(in: workspaceRoot, fileManager: fileManager) == baselineWorkspaces)
    }

    let failingPreset = ExportPreset(
        id: "integration-invalid-video",
        title: "Invalid integration encoder",
        pathExtension: "mp4",
        mediaKind: .video,
        videoCodec: "redact_encoder_that_does_not_exist",
        audioCodec: "aac"
    )
    do {
        try await service.exportMedia(
            inputPath: inputURL.path,
            outputPath: directory.appendingPathComponent("expected-failure.mp4").path,
            segments: keptRanges,
            preset: failingPreset,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: false,
            quality: nil,
            speed: 1,
            enhanceAudio: false,
            operation: ProcessOperation(),
            onProgress: nil,
            totalDuration: rawKeptDuration
        )
        Issue.record("The invalid encoder should fail the batched export")
    } catch {
        #expect(error is FFmpegError)
    }
    #expect(try batchWorkspaceNames(in: workspaceRoot, fileManager: fileManager) == baselineWorkspaces)

    let cancelledOperation = ProcessOperation()
    cancelledOperation.cancel()
    do {
        try await service.exportMedia(
            inputPath: inputURL.path,
            outputPath: directory.appendingPathComponent("expected-cancellation.mp4").path,
            segments: keptRanges,
            preset: .mp4Video,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: false,
            quality: nil,
            speed: 1,
            enhanceAudio: false,
            operation: cancelledOperation,
            onProgress: nil,
            totalDuration: rawKeptDuration
        )
        Issue.record("The pre-cancelled operation should reject the batched export")
    } catch let error as FFmpegError {
        #expect(error == .cancelled)
    }
    #expect(try batchWorkspaceNames(in: workspaceRoot, fileManager: fileManager) == baselineWorkspaces)
}

/// Deterministic compatibility coverage for source shapes seen in real media
/// libraries. All inputs are generated at runtime and removed after the test.
@Test func generatedMediaCompatibilityMatrix() async throws {
    guard ProcessInfo.processInfo.environment["REDACT_RUN_GENERATED_MEDIA_INTEGRATION"] == "1" else {
        return
    }
    guard let ffmpeg = PathUtilities.findFFmpeg() else {
        Issue.record("FFmpeg is required for the generated-media integration test")
        return
    }

    let fileManager = FileManager.default
    let directory = fileManager.temporaryDirectory
        .appendingPathComponent("redact-generated-media-integration-" + UUID().uuidString, isDirectory: true)
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: directory) }

    let timecodeURL = directory.appendingPathComponent("h264-timecode.mp4")
    try runFFmpeg(
        ffmpegPath: ffmpeg,
        arguments: generatedVideoArguments(
            outputURL: timecodeURL,
            videoInput: "testsrc2=size=160x90:rate=30:duration=3",
            videoCodecArguments: ["-c:v", "libx264", "-preset", "ultrafast"],
            extraArguments: ["-timecode", "00:00:00:00"]
        )
    )

    let hevcURL = directory.appendingPathComponent("hevc.mp4")
    try runFFmpeg(
        ffmpegPath: ffmpeg,
        arguments: generatedVideoArguments(
            outputURL: hevcURL,
            videoInput: "testsrc2=size=160x90:rate=24000/1001:duration=3",
            videoCodecArguments: [
                "-c:v", "libx265",
                "-preset", "ultrafast",
                "-x265-params", "pools=1:frame-threads=1:log-level=error",
            ]
        )
    )

    let vfrURL = directory.appendingPathComponent("vfr.mp4")
    try runFFmpeg(
        ffmpegPath: ffmpeg,
        arguments: generatedVideoArguments(
            outputURL: vfrURL,
            videoInput: "testsrc2=size=160x90:rate=30:duration=3",
            videoCodecArguments: ["-c:v", "libx264", "-preset", "ultrafast"],
            extraArguments: [
                "-vf", "select='not(mod(n,2))+not(mod(n,5))'",
                "-fps_mode", "vfr",
            ]
        )
    )

    let audioURL = directory.appendingPathComponent("audio-only.m4a")
    try runFFmpeg(
        ffmpegPath: ffmpeg,
        arguments: [
            "-nostdin", "-f", "lavfi", "-i",
            "sine=frequency=440:sample_rate=48000:duration=3",
            "-c:a", "aac", "-y", audioURL.path,
        ]
    )

    let service = FFmpegService()
    let cases = [
        GeneratedCompatibilityCase(
            id: "h264-timecode",
            sourceURL: timecodeURL,
            expectedVideoCodec: "h264",
            expectedStrategy: .selectionFilterTranscode
        ),
        GeneratedCompatibilityCase(
            id: "hevc",
            sourceURL: hevcURL,
            expectedVideoCodec: "hevc",
            expectedStrategy: .selectionFilterTranscode
        ),
        GeneratedCompatibilityCase(
            id: "vfr",
            sourceURL: vfrURL,
            expectedVideoCodec: "h264",
            expectedStrategy: .filterGraphTranscode
        ),
        GeneratedCompatibilityCase(
            id: "audio-only",
            sourceURL: audioURL,
            expectedVideoCodec: nil,
            expectedStrategy: .filterGraphTranscode
        ),
    ]

    for testCase in cases {
        let sourceInfo = try await service.getMediaInfo(
            filePath: testCase.sourceURL.path,
            operation: ProcessOperation()
        )
        #expect(sourceInfo.videoStream?.codecName == testCase.expectedVideoCodec)
        #expect(sourceInfo.hasAudio)
        #expect(sourceInfo.hasVideo == (testCase.expectedVideoCodec != nil))
        if testCase.id == "h264-timecode" {
            #expect(sourceInfo.streams.contains { $0.kind == .other && $0.codecName == "unknown" })
        }
        if testCase.id == "vfr" {
            #expect(sourceInfo.videoStream?.constantFrameRate == nil)
        }

        let segments = [
            TimeRange(start: 0.1, end: 0.9),
            TimeRange(start: 1.4, end: 2.4),
        ]
        let expectedDuration = segments.reduce(0) { $0 + $1.duration }
        let preset: ExportPreset = sourceInfo.hasVideo ? .mp4Video : .m4aAudio
        let outputURL = directory.appendingPathComponent(
            testCase.id + "-output." + preset.pathExtension
        )
        let plan = FFmpegExportPlan(
            inputPath: testCase.sourceURL.path,
            outputPath: outputURL.path,
            segments: segments,
            preset: preset,
            quality: nil,
            speed: 1,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: false
        )
        #expect(plan.strategy == testCase.expectedStrategy)

        try await service.exportMedia(
            inputPath: testCase.sourceURL.path,
            outputPath: outputURL.path,
            segments: segments,
            preset: preset,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: false,
            quality: nil,
            speed: 1,
            enhanceAudio: false,
            operation: ProcessOperation(),
            onProgress: nil,
            totalDuration: expectedDuration
        )
        let outputInfo = try await service.getMediaInfo(
            filePath: outputURL.path,
            operation: ProcessOperation()
        )
        #expect(outputInfo.hasAudio)
        #expect(outputInfo.hasVideo == sourceInfo.hasVideo)
        #expect(abs(outputInfo.duration - expectedDuration) <= 0.25)
    }
}

private func makeSyntheticVideo(
    at outputURL: URL,
    duration: Double,
    ffmpegPath: String
) throws {
    try runFFmpeg(ffmpegPath: ffmpegPath, arguments: [
        "-nostdin",
        "-f", "lavfi", "-i", "testsrc2=size=160x90:rate=15:duration=\(duration)",
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=\(duration)",
        "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-shortest", "-y", outputURL.path,
    ])
}

private func generatedVideoArguments(
    outputURL: URL,
    videoInput: String,
    videoCodecArguments: [String],
    extraArguments: [String] = []
) -> [String] {
    [
        "-nostdin",
        "-f", "lavfi", "-i", videoInput,
        "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=48000:duration=3",
    ] + extraArguments + videoCodecArguments + [
        "-pix_fmt", "yuv420p",
        "-c:a", "aac",
        "-shortest", "-y", outputURL.path,
    ]
}

private func runFFmpeg(ffmpegPath: String, arguments: [String]) throws {
    let generator = Process()
    generator.executableURL = URL(fileURLWithPath: ffmpegPath)
    generator.arguments = arguments
    generator.standardOutput = FileHandle.nullDevice
    generator.standardError = FileHandle.nullDevice
    try generator.run()
    generator.waitUntilExit()
    guard generator.terminationStatus == 0 else {
        throw FFmpegError.exportFailed(generator.terminationStatus, "Synthetic media generation failed")
    }
}

private func benchmarkKeptRanges(duration: Double, cutCount: Int) -> [TimeRange] {
    guard cutCount > 0 else {
        return [TimeRange(start: 0, end: duration)]
    }

    let sliceDuration = duration / Double(cutCount * 2 + 1)
    return (0...cutCount).map { index in
        let start = Double(index * 2) * sliceDuration
        return TimeRange(start: start, end: min(duration, start + sliceDuration))
    }
}

private func batchWorkspaceNames(
    in root: URL,
    fileManager: FileManager
) throws -> Set<String> {
    guard fileManager.fileExists(atPath: root.path) else { return [] }
    return Set(
        try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ).map(\.lastPathComponent)
    )
}
