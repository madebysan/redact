import Foundation
import Testing
@testable import Redact

private struct RepresentativeMediaStreamReport: Codable {
    let codec: String
    let width: Int?
    let height: Int?
    let frameRate: Double?
    let sampleRate: Int?
    let channels: Int?
}

private struct RepresentativeMediaCutResult: Codable {
    let cutCount: Int
    let keptRangeCount: Int
    let expectedDurationSeconds: Double
    let previewDurationSeconds: Double
    let outputDurationSeconds: Double
    let previewDurationDeltaSeconds: Double
    let outputDurationDeltaSeconds: Double
    let previewBuildMedianMilliseconds: Double
    let exportMedianMilliseconds: Double
    let outputSizeMedianBytes: Int64
}

private struct RepresentativeMediaReport: Codable {
    let schemaVersion: Int
    let label: String
    let durationSeconds: Double
    let sourceSizeBytes: Int64
    let containers: [String]
    let video: RepresentativeMediaStreamReport?
    let audio: RepresentativeMediaStreamReport
    let probeMedianMilliseconds: Double
    let runsPerCutCount: Int
    let results: [RepresentativeMediaCutResult]
}

private enum RepresentativeMediaBenchmarkError: LocalizedError {
    case invalidLabel
    case unreadableSource
    case missingAudio
    case invalidRunCount
    case invalidCutCounts

    var errorDescription: String? {
        switch self {
        case .invalidLabel:
            "Representative media label must be short, medium, or long."
        case .unreadableSource:
            "Representative media is not a readable file."
        case .missingAudio:
            "Representative media must contain an audio stream."
        case .invalidRunCount:
            "Representative benchmark run count must be between 1 and 10."
        case .invalidCutCounts:
            "Representative cut counts must be an ordered subset of 0, 10, 100, and 500."
        }
    }
}

@Test func representativeMediaReportSchemaOmitsPrivateIdentityFields() throws {
    let report = RepresentativeMediaReport(
        schemaVersion: 1,
        label: "short",
        durationSeconds: 120,
        sourceSizeBytes: 1_024,
        containers: ["mov"],
        video: RepresentativeMediaStreamReport(
            codec: "h264",
            width: 1_920,
            height: 1_080,
            frameRate: 30,
            sampleRate: nil,
            channels: nil
        ),
        audio: RepresentativeMediaStreamReport(
            codec: "aac",
            width: nil,
            height: nil,
            frameRate: nil,
            sampleRate: 48_000,
            channels: 2
        ),
        probeMedianMilliseconds: 10,
        runsPerCutCount: 3,
        results: [
            RepresentativeMediaCutResult(
                cutCount: 0,
                keptRangeCount: 1,
                expectedDurationSeconds: 120,
                previewDurationSeconds: 120,
                outputDurationSeconds: 120,
                previewDurationDeltaSeconds: 0,
                outputDurationDeltaSeconds: 0,
                previewBuildMedianMilliseconds: 5,
                exportMedianMilliseconds: 20,
                outputSizeMedianBytes: 1_024
            ),
        ]
    )

    let data = try JSONEncoder().encode(report)
    let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(Set(root.keys) == [
        "schemaVersion", "label", "durationSeconds", "sourceSizeBytes", "containers",
        "video", "audio", "probeMedianMilliseconds", "runsPerCutCount", "results",
    ])
    let result = try #require((root["results"] as? [[String: Any]])?.first)
    #expect(Set(result.keys) == [
        "cutCount", "keptRangeCount", "expectedDurationSeconds", "previewDurationSeconds",
        "outputDurationSeconds", "previewDurationDeltaSeconds", "outputDurationDeltaSeconds",
        "previewBuildMedianMilliseconds", "exportMedianMilliseconds", "outputSizeMedianBytes",
    ])
    let keyText = (Array(root.keys) + Array(result.keys)).joined(separator: " ").lowercased()
    #expect(!keyText.contains("path"))
    #expect(!keyText.contains("filename"))
    #expect(!keyText.contains("transcript"))
}

/// Opt-in benchmark for san-selected local media. The report intentionally
/// excludes source paths, filenames, transcript text, and media hashes.
@Test func representativeMediaCutCountBenchmark() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard environment["RUN_REDACT_REPRESENTATIVE_BENCHMARKS"] == "1" else {
        return
    }
    guard let inputPath = environment["REDACT_REPRESENTATIVE_MEDIA"],
          let label = environment["REDACT_REPRESENTATIVE_LABEL"],
          let outputPath = environment["REDACT_REPRESENTATIVE_OUTPUT"] else {
        throw RepresentativeMediaBenchmarkError.unreadableSource
    }
    guard ["short", "medium", "long"].contains(label) else {
        throw RepresentativeMediaBenchmarkError.invalidLabel
    }
    let runs = Int(environment["REDACT_REPRESENTATIVE_RUNS"] ?? "3") ?? 0
    guard (1...10).contains(runs) else {
        throw RepresentativeMediaBenchmarkError.invalidRunCount
    }
    let allowedCutCounts = [0, 10, 100, 500]
    let cutCounts: [Int]
    if let value = environment["REDACT_REPRESENTATIVE_CUT_COUNTS"] {
        let components = value.split(separator: ",", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.allSatisfy({ Int($0) != nil }) else {
            throw RepresentativeMediaBenchmarkError.invalidCutCounts
        }
        cutCounts = components.compactMap { Int($0) }
    } else {
        cutCounts = allowedCutCounts
    }
    guard !cutCounts.isEmpty,
          cutCounts == allowedCutCounts.filter(cutCounts.contains) else {
        throw RepresentativeMediaBenchmarkError.invalidCutCounts
    }
    guard FileManager.default.isReadableFile(atPath: inputPath),
          PathUtilities.findFFmpeg() != nil else {
        throw RepresentativeMediaBenchmarkError.unreadableSource
    }

    let inputURL = URL(fileURLWithPath: inputPath)
    let outputURL = URL(fileURLWithPath: outputPath)
    let workingDirectory = outputURL.deletingLastPathComponent()
        .appendingPathComponent(".redact-media-work-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: workingDirectory,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    defer { try? FileManager.default.removeItem(at: workingDirectory) }

    let service = FFmpegService()
    var probeTimes: [Double] = []
    var sourceInfo: MediaInfo?
    for _ in 0..<runs {
        let start = Date.timeIntervalSinceReferenceDate
        sourceInfo = try await service.getMediaInfo(
            filePath: inputPath,
            operation: ProcessOperation()
        )
        probeTimes.append((Date.timeIntervalSinceReferenceDate - start) * 1_000)
    }
    let mediaInfo = try #require(sourceInfo)
    guard let audioStream = mediaInfo.audioStream else {
        throw RepresentativeMediaBenchmarkError.missingAudio
    }

    let sourceSize = try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    let preset: ExportPreset = mediaInfo.hasVideo ? .mp4Video : .m4aAudio
    var cutResults: [RepresentativeMediaCutResult] = []

    for cutCount in cutCounts {
        let keptRanges = representativeKeptRanges(
            duration: mediaInfo.duration,
            cutCount: cutCount
        )
        let expectedDuration = keptRanges.reduce(0) { $0 + $1.duration }
        var previewTimes: [Double] = []
        var previewDurations: [Double] = []
        var exportTimes: [Double] = []
        var outputDurations: [Double] = []
        var outputSizes: [Int64] = []

        for runIndex in 0..<runs {
            let previewStart = Date.timeIntervalSinceReferenceDate
            let preview = try await AVPreviewCompositionBuilder().build(
                sourceURL: inputURL,
                keptRanges: keptRanges
            )
            previewTimes.append((Date.timeIntervalSinceReferenceDate - previewStart) * 1_000)
            previewDurations.append(try await preview.asset.load(.duration).seconds)

            let renderedURL = workingDirectory.appendingPathComponent(
                "render-\(cutCount)-\(runIndex)." + preset.pathExtension
            )
            let exportStart = Date.timeIntervalSinceReferenceDate
            try await service.exportMedia(
                inputPath: inputPath,
                outputPath: renderedURL.path,
                segments: keptRanges,
                preset: preset,
                sourceInfo: mediaInfo,
                sourceIsUnchanged: cutCount == 0,
                quality: nil,
                speed: 1,
                enhanceAudio: false,
                operation: ProcessOperation(),
                onProgress: nil,
                totalDuration: expectedDuration
            )
            exportTimes.append((Date.timeIntervalSinceReferenceDate - exportStart) * 1_000)

            let outputInfo = try await service.getMediaInfo(
                filePath: renderedURL.path,
                operation: ProcessOperation()
            )
            outputDurations.append(outputInfo.duration)
            let outputSize = try renderedURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            outputSizes.append(Int64(outputSize))
            try FileManager.default.removeItem(at: renderedURL)
        }

        let previewDuration = median(previewDurations)
        let outputDuration = median(outputDurations)
        let previewDelta = abs(previewDuration - expectedDuration)
        let outputDelta = abs(outputDuration - expectedDuration)
        let previewTolerance = cutCount >= 500 ? 0.75 : 0.25
        #expect(previewDelta <= previewTolerance)
        #expect(outputDelta <= 0.25)

        cutResults.append(
            RepresentativeMediaCutResult(
                cutCount: cutCount,
                keptRangeCount: keptRanges.count,
                expectedDurationSeconds: expectedDuration,
                previewDurationSeconds: previewDuration,
                outputDurationSeconds: outputDuration,
                previewDurationDeltaSeconds: previewDelta,
                outputDurationDeltaSeconds: outputDelta,
                previewBuildMedianMilliseconds: median(previewTimes),
                exportMedianMilliseconds: median(exportTimes),
                outputSizeMedianBytes: median(outputSizes)
            )
        )
    }

    let report = RepresentativeMediaReport(
        schemaVersion: 1,
        label: label,
        durationSeconds: mediaInfo.duration,
        sourceSizeBytes: Int64(sourceSize),
        containers: mediaInfo.containerNames,
        video: mediaInfo.videoStream.map(streamReport),
        audio: streamReport(audioStream),
        probeMedianMilliseconds: median(probeTimes),
        runsPerCutCount: runs,
        results: cutResults
    )
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: outputURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: outputURL.path
    )
    print("REDACT_REPRESENTATIVE_BENCHMARK label=\(label) completed")
}

private func representativeKeptRanges(duration: Double, cutCount: Int) -> [TimeRange] {
    guard cutCount > 0 else {
        return [TimeRange(start: 0, end: duration)]
    }

    let sliceDuration = duration / Double(cutCount * 2 + 1)
    return (0...cutCount).map { index in
        let start = Double(index * 2) * sliceDuration
        return TimeRange(start: start, end: min(duration, start + sliceDuration))
    }
}

private func streamReport(_ stream: MediaStreamInfo) -> RepresentativeMediaStreamReport {
    RepresentativeMediaStreamReport(
        codec: stream.codecName,
        width: stream.width,
        height: stream.height,
        frameRate: stream.averageFrameRate,
        sampleRate: stream.sampleRate,
        channels: stream.channels
    )
}

private func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

private func median(_ values: [Int64]) -> Int64 {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}
