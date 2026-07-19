import Foundation
import Testing
@testable import Redact

@Test func transcriptSelectionIndexNormalizesPartialAndDiscontiguousRanges() {
    let index = TranscriptSelectionIndex(spans: [
        TranscriptSelectionSpan(wordID: "one", range: NSRange(location: 8, length: 3)),
        TranscriptSelectionSpan(wordID: "two", range: NSRange(location: 12, length: 3)),
        TranscriptSelectionSpan(wordID: "three", range: NSRange(location: 24, length: 5)),
    ])

    #expect(index.wordIDs(intersecting: [NSRange(location: 9, length: 16)]) == ["one", "two", "three"])
    #expect(index.normalizedCharacterRanges(for: [
        NSRange(location: 9, length: 1),
        NSRange(location: 25, length: 2),
    ]) == [
        NSRange(location: 8, length: 3),
        NSRange(location: 24, length: 5),
    ])
    #expect(index.characterRanges(forWordIDs: ["one", "two"]) == [
        NSRange(location: 8, length: 7),
    ])
}

@Test func transcriptSelectionIndexKeepsNonWordCaretSelection() {
    let index = TranscriptSelectionIndex(spans: [
        TranscriptSelectionSpan(wordID: "one", range: NSRange(location: 8, length: 3)),
    ])
    let timestampCaret = NSRange(location: 2, length: 0)

    #expect(index.wordIDs(intersecting: [timestampCaret]).isEmpty)
    #expect(index.normalizedCharacterRanges(for: [timestampCaret]) == [timestampCaret])
}

@Test @MainActor func transcriptViewUsesTextKitTwoAndSelectAllUpdatesTheProject() {
    let project = ProjectDocument()
    project.setTranscript(RawTranscript(
        segments: [RawSegment(id: 0, words: [
            RawWord(word: "one", start: 0, end: 0.2, confidence: 1),
            RawWord(word: "two", start: 0.3, end: 0.5, confidence: 1),
        ])],
        language: "en",
        duration: 0.5
    ))
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.project = project
    view.setTranscript(segments: project.segments)

    view.selectAllTranscriptWords()

    #expect(view.usesViewportTextLayout)
    #expect(project.selectedWordIds == ["w_0", "w_1"])

    view.clearTranscriptSelection()
    #expect(project.selectedWordIds.isEmpty)
}

@Test @MainActor func transcriptViewPatchesCorrectedTextAndPreservesSelection() throws {
    let project = ProjectDocument()
    project.setTranscript(RawTranscript(
        segments: [RawSegment(id: 0, words: [
            RawWord(word: "one", start: 0, end: 0.2, confidence: 1),
            RawWord(word: "two", start: 0.3, end: 0.5, confidence: 1),
        ])],
        language: "en",
        duration: 0.5
    ))
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.project = project
    view.setTranscript(segments: project.segments)
    view.selectAllTranscriptWords()
    _ = project.correctWordText(id: "w_0", text: "corrected")

    let didPatch = view.updateCorrectedWord(
        id: "w_0",
        text: "corrected",
        segments: project.segments
    )

    #expect(didPatch)
    #expect(view.displayedText.contains("corrected two"))
    #expect(project.selectedWordIds == ["w_0", "w_1"])
    #expect(Set(view.displayedSelectedWordIDs) == ["w_0", "w_1"])
}

@Test @MainActor func transcriptViewKeepsWordIdentityAfterUnicodeCorrection() {
    let project = ProjectDocument()
    project.setTranscript(RawTranscript(
        segments: [RawSegment(id: 0, words: [
            RawWord(word: "one", start: 0, end: 0.2, confidence: 1),
            RawWord(word: "two", start: 0.3, end: 0.5, confidence: 1),
        ])],
        language: "en",
        duration: 0.5
    ))
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    view.project = project
    view.setTranscript(segments: project.segments)
    _ = project.correctWordText(id: "w_0", text: "🎬")

    let didPatch = view.updateCorrectedWord(
        id: "w_0",
        text: "🎬",
        segments: project.segments
    )

    #expect(didPatch)
    #expect(view.displayedWordText(id: "w_0") == "🎬")
    #expect(view.displayedWordText(id: "w_1") == "two")
}
