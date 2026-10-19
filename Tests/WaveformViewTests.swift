import AVFoundation
import AppKit
import Testing
@testable import Redact

@Test @MainActor func waveformAnnouncesCanonicalRemovedRanges() throws {
    let waveform = WaveformView(frame: NSRect(x: 0, y: 0, width: 600, height: 60))

    waveform.updateDeletedRanges(
        [
            TimeRange(start: 10, end: 12),
            TimeRange(start: 30, end: 31),
        ],
        duration: 60
    )

    _ = try #require(
        waveform.subviews.first {
            $0.accessibilityLabel() == "2 removed ranges on source waveform"
        }
    )
}

@Test @MainActor func waveformRendersAnImageForAnalyzedAudio() async throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-waveform-\(UUID().uuidString).wav")
    defer { try? FileManager.default.removeItem(at: url) }
    try writeSineFile(to: url)

    let waveform = WaveformView()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 60),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = waveform
    window.layoutIfNeeded()

    waveform.loadAudio(url: url, duration: 2)
    for _ in 0..<50 where !waveform.hasRenderedWaveform {
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    // Regression: the drawer needs exactly one sample per pixel; a fixed 200-sample
    // request rendered nothing at any real panel width.
    #expect(waveform.hasRenderedWaveform)
}

@Test func waveformResamplingKeepsOneSamplePerBucket() {
    let samples: [Float] = [0, 1, 0, 1, 0, 1, 0, 1]
    #expect(WaveformView.resample(samples, to: 4) == [0.5, 0.5, 0.5, 0.5])
    #expect(WaveformView.resample(samples, to: 16).count == 16)
    #expect(WaveformView.resample([], to: 4).isEmpty)
}

private func writeSineFile(to url: URL) throws {
    let format = try #require(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
    let frameCount = AVAudioFrameCount(44_100 * 2)
    let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
    buffer.frameLength = frameCount
    let channel = try #require(buffer.floatChannelData?[0])
    for index in 0..<Int(frameCount) {
        let amplitude: Float = index % 44_100 < 22_050 ? 0.8 : 0.05
        channel[index] = sinf(Float(index) * 2 * .pi * 440 / 44_100) * amplitude
    }
    let file = try AVAudioFile(forWriting: url, settings: format.settings)
    try file.write(from: buffer)
}
