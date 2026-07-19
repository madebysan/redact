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
