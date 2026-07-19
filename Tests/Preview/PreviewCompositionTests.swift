import AVFoundation
import Foundation
import Testing
@testable import Redact

@Test func previewCompositionKeepsOnlyRenderPlanRanges() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-preview-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let audioURL = directory.appendingPathComponent("source.wav")
    try makeSilentAudio(at: audioURL, duration: 2)

    let prepared = try await AVPreviewCompositionBuilder().build(
        sourceURL: audioURL,
        keptRanges: [
            TimeRange(start: 0, end: 0.5),
            TimeRange(start: 1, end: 1.5),
        ]
    )
    let duration = try await prepared.asset.load(.duration).seconds
    let audioTracks = try await prepared.asset.loadTracks(withMediaType: .audio)

    #expect(abs(duration - 1) < 0.01)
    #expect(audioTracks.count == 1)
}

@Test func previewCompositionRejectsMediaWithoutAudioOrVideoTracks() async {
    let sourceURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-preview-empty-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: sourceURL) }
    try? Data().write(to: sourceURL)

    do {
        _ = try await AVPreviewCompositionBuilder().build(
            sourceURL: sourceURL,
            keptRanges: [TimeRange(start: 0, end: 1)]
        )
        Issue.record("Expected media without tracks to fail")
    } catch let error as PreviewCompositionError {
        #expect(error == .noMediaTracks)
    } catch {
        Issue.record("Unexpected preview error")
    }
}

@Test func previewCompositionBuildPerformance() async throws {
    guard ProcessInfo.processInfo.environment["RUN_REDACT_BENCHMARKS"] == "1" else {
        return
    }

    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-preview-benchmark-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let audioURL = directory.appendingPathComponent("source.wav")
    try makeSilentAudio(at: audioURL, duration: 60)
    let keptRanges = (0..<500).map { index in
        let start = Double(index) * 0.1
        return TimeRange(start: start, end: start + 0.05)
    }

    let start = Date.timeIntervalSinceReferenceDate
    let prepared = try await AVPreviewCompositionBuilder().build(
        sourceURL: audioURL,
        keptRanges: keptRanges
    )
    let elapsed = Date.timeIntervalSinceReferenceDate - start
    let duration = try await prepared.asset.load(.duration).seconds

    #expect(abs(duration - 25) < 0.05)
    #expect(elapsed < 0.15)
    print(String(format: "REDACT_BENCHMARK preview_500_cuts_ms=%.3f", elapsed * 1000))
}

private func makeSilentAudio(at url: URL, duration: Double) throws {
    let sampleRate = 8_000.0
    let format = try #require(
        AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    )
    let frameCount = AVAudioFrameCount(sampleRate * duration)
    let buffer = try #require(
        AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)
    )
    buffer.frameLength = frameCount
    if let channel = buffer.floatChannelData?[0] {
        channel.initialize(repeating: 0, count: Int(frameCount))
    }

    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}
