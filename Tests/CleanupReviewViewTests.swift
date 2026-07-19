import AppKit
import Testing
@testable import Redact

@Test @MainActor func cleanupReviewStartsKeyboardNavigationAtFirstCategory() throws {
    let view = CleanupReviewView(
        frame: NSRect(x: 0, y: 0, width: 680, height: 520),
        suggestions: [cleanupSuggestion(id: "filler", kind: .fillerWords, wordIDs: ["w0"])]
    )
    let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view

    #expect(view.focusInitialControl(in: window))
    let focusedView = try #require(window.firstResponder as? NSView)
    #expect(focusedView.accessibilityLabel() == "Filler words")
}

@Test @MainActor func cleanupReviewSelectsEverythingAndSupportsCategoryFiltering() {
    let suggestions = [
        cleanupSuggestion(id: "filler", kind: .fillerWords, wordIDs: ["w0"]),
        cleanupSuggestion(id: "repeat", kind: .repeatedWords, wordIDs: ["w1"]),
        cleanupSuggestion(id: "pause", kind: .longPauses, wordIDs: ["s0", "s1"]),
    ]
    let view = CleanupReviewView(
        frame: NSRect(x: 0, y: 0, width: 680, height: 520),
        suggestions: suggestions
    )

    #expect(view.selectedSuggestionCount == 3)
    #expect(view.selectedWordIDs == ["w0", "w1", "s0", "s1"])

    view.setCategory(.longPauses, enabled: false)

    #expect(view.selectedSuggestionCount == 2)
    #expect(view.selectedWordIDs == ["w0", "w1"])
    #expect(recursiveAccessibilityLabels(in: view).contains("Filler words"))
    #expect(recursiveAccessibilityLabels(in: view).contains("Repeated words"))
    #expect(recursiveAccessibilityLabels(in: view).contains("Long pauses"))
}

@Test @MainActor func captureCleanupReviewWhenRequested() throws {
    guard let outputPath = ProcessInfo.processInfo.environment["REDACT_UI_CAPTURE_DIR"] else {
        return
    }

    let appearanceValue = ProcessInfo.processInfo.environment["REDACT_UI_APPEARANCE"] ?? "dark"
    let appearanceName: NSAppearance.Name = appearanceValue == "light" ? .aqua : .darkAqua
    let application = NSApplication.shared
    let originalAppearance = application.appearance
    defer { application.appearance = originalAppearance }
    application.appearance = NSAppearance(named: appearanceName)

    let suggestions = [
        TranscriptCleanupSuggestion(
            id: "filler-1",
            kind: .fillerWords,
            wordIDs: ["w0"],
            changeDescription: "Remove “um”",
            context: "… wanted to [um] share some …",
            startTime: 4.2,
            removedDuration: 0.3
        ),
        TranscriptCleanupSuggestion(
            id: "filler-2",
            kind: .fillerWords,
            wordIDs: ["w1", "w2"],
            changeDescription: "Remove “you know”",
            context: "… and [you know] the next …",
            startTime: 12.6,
            removedDuration: 0.6
        ),
        TranscriptCleanupSuggestion(
            id: "repeat-1",
            kind: .repeatedWords,
            wordIDs: ["w3"],
            changeDescription: "Keep one “the”",
            context: "… mention [the the] goals …",
            startTime: 21.1,
            removedDuration: 0.2
        ),
        TranscriptCleanupSuggestion(
            id: "pause-1",
            kind: .longPauses,
            wordIDs: ["s0", "s1"],
            changeDescription: "Shorten 1.5s pause to 0.5s",
            context: "… feedback [pause] I think …",
            startTime: 29.4,
            removedDuration: 1
        ),
    ]
    let view = CleanupReviewView(
        frame: NSRect(x: 0, y: 0, width: 700, height: 520),
        suggestions: suggestions
    )
    view.layoutSubtreeIfNeeded()

    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: view.bounds, to: representation)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    try data.write(
        to: outputURL.appendingPathComponent("cleanup-review-\(appearanceValue).png")
    )
}

private func cleanupSuggestion(
    id: String,
    kind: TranscriptCleanupKind,
    wordIDs: [String]
) -> TranscriptCleanupSuggestion {
    TranscriptCleanupSuggestion(
        id: id,
        kind: kind,
        wordIDs: wordIDs,
        changeDescription: "Suggested change",
        context: "… before [word] after …",
        startTime: 1,
        removedDuration: 0.5
    )
}

@MainActor
private func recursiveAccessibilityLabels(in view: NSView) -> [String] {
    view.subviews.flatMap { subview in
        [subview.accessibilityLabel()].compactMap { $0 }
            + recursiveAccessibilityLabels(in: subview)
    }
}
