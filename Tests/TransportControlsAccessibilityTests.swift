import AppKit
import Testing
@testable import Redact

@Test @MainActor func transportControlsExposeVoiceOverLabels() {
    let controls = TransportControlsView(frame: NSRect(x: 0, y: 0, width: 500, height: 84))
    let labels = descendantViews(of: controls).compactMap { $0.accessibilityLabel() }

    #expect(labels.contains("Previous edit"))
    #expect(labels.contains("Skip back 5 seconds"))
    #expect(labels.contains("Play"))
    #expect(labels.contains("Skip forward 5 seconds"))
    #expect(labels.contains("Next edit"))
    #expect(labels.contains("Preview volume"))
}

@Test @MainActor func transportShowsEditedAndOriginalDurations() throws {
    let controls = TransportControlsView(frame: NSRect(x: 0, y: 0, width: 700, height: 84))

    controls.updateTime(current: 50, total: 240, original: 300)

    let timeLabel = try #require(
        controls.subviews.compactMap { $0 as? NSTextField }
            .first { $0.stringValue.contains("original") }
    )
    #expect(timeLabel.stringValue == "00:50 / 04:00 · 05:00 original")
    #expect(timeLabel.accessibilityLabel() == "00:50 of 04:00 edited, 05:00 original")
}

@Test @MainActor func transportShowsCanonicalEditSummaryAndScrubFeedback() throws {
    let controls = TransportControlsView(frame: NSRect(x: 0, y: 0, width: 700, height: 84))
    controls.updateTime(current: 0, total: 240, original: 300)
    controls.updateReviewSummary(cutCount: 12, removed: 60, final: 240)

    let summary = try #require(
        controls.subviews.compactMap { $0 as? NSTextField }
            .first { $0.stringValue.contains("cuts") }
    )
    #expect(summary.stringValue == "12 cuts · 01:00 removed · 04:00 final")
    #expect(summary.accessibilityLabel()?.contains("12 cuts") == true)

    let timeline = try #require(
        descendantViews(of: controls).compactMap { $0 as? NSSlider }
            .first { $0.accessibilityLabel() == "Edited timeline position" }
    )
    timeline.doubleValue = 0.25
    _ = timeline.sendAction(timeline.action, to: timeline.target)
    #expect(timeline.toolTip == "Seek to 01:00")
}

private func descendantViews(of root: NSView) -> [NSView] {
    root.subviews.flatMap { [$0] + descendantViews(of: $0) }
}
