import AppKit
import Testing
@testable import Redact

@Test @MainActor func captureEditorLayoutWhenRequested() throws {
    guard let outputPath = ProcessInfo.processInfo.environment["REDACT_UI_CAPTURE_DIR"] else { return }

    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    let suiteName = "EditorLayoutVisualCaptureTests.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: suiteName)!
    defer { preferences.removePersistentDomain(forName: suiteName) }
    let controller = MainSplitViewController(preferences: preferences)
    controller.view.frame = NSRect(x: 0, y: 0, width: 1_400, height: 900)
    controller.showEditing(segments: sampleSegments())
    controller.transportControlsView.updateTime(current: 50, total: 240, original: 300)
    controller.transportControlsView.updateReviewSummary(
        cutCount: 12,
        removed: 60,
        final: 240
    )
    controller.waveformView.updateDeletedRanges(
        [
            TimeRange(start: 45, end: 49),
            TimeRange(start: 90, end: 94),
            TimeRange(start: 180, end: 184),
        ],
        duration: 300
    )
    controller.view.layoutSubtreeIfNeeded()

    try capture(controller.view, to: outputURL.appendingPathComponent("editor-1400.png"))

    controller.view.frame.size = NSSize(width: 1_000, height: 700)
    controller.view.layoutSubtreeIfNeeded()
    try capture(controller.view, to: outputURL.appendingPathComponent("editor-1000.png"))

    controller.togglePreview()
    controller.view.layoutSubtreeIfNeeded()
    try capture(controller.view, to: outputURL.appendingPathComponent("editor-preview-hidden.png"))

    let missingMediaController = MainSplitViewController(preferences: preferences)
    missingMediaController.view.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
    missingMediaController.showEditing(
        segments: sampleSegments(),
        showsMissingMediaNotice: true
    )
    missingMediaController.view.layoutSubtreeIfNeeded()
    try capture(
        missingMediaController.view,
        to: outputURL.appendingPathComponent("editor-missing-media.png")
    )

    let importingController = MainSplitViewController(preferences: preferences)
    importingController.view.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
    importingController.showImporting(fileName: "interview.mov")
    importingController.view.layoutSubtreeIfNeeded()
    try capture(
        importingController.view,
        to: outputURL.appendingPathComponent("editor-importing.png")
    )

    let transcribingController = MainSplitViewController(preferences: preferences)
    transcribingController.view.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
    transcribingController.showTranscribing()
    transcribingController.updateTranscribeProgress(
        TranscribeProgress(
            status: .transcribing,
            message: "876 words ready",
            completedTextPreview: "Raw model output should stay hidden.",
            completedWordCount: 876
        )
    )
    transcribingController.view.layoutSubtreeIfNeeded()
    try capture(
        transcribingController.view,
        to: outputURL.appendingPathComponent("editor-transcribing.png")
    )
}

@MainActor
private func capture(_ view: NSView, to url: URL) throws {
    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: view.bounds, to: representation)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

private func sampleSegments() -> [Segment] {
    let words = "Redact makes spoken media editable as a transcript. The preview supports the work without competing with the words."
        .split(separator: " ")
        .enumerated()
        .map { index, text in
            Word(
                id: "w_\(index)",
                word: String(text),
                start: Double(index) * 0.6,
                end: Double(index) * 0.6 + 0.5,
                confidence: 0.99,
                deleted: index == 12,
                isSilence: nil
            )
        }
    return [Segment(id: 0, words: words)]
}
