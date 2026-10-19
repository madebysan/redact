import AppKit
import Testing
@testable import Redact

private func rowsProject() -> ProjectDocument {
    let project = ProjectDocument()
    project.setTranscript(RawTranscript(
        segments: [RawSegment(id: 0, words: [
            RawWord(word: "Hello", start: 0, end: 0.4, confidence: 1),
            RawWord(word: "there.", start: 0.5, end: 0.9, confidence: 1),
            RawWord(word: "Second", start: 2.4, end: 2.8, confidence: 1),
            RawWord(word: "line.", start: 2.9, end: 3.3, confidence: 1),
        ])],
        language: "en",
        duration: 3.5
    ))
    return project
}

@Test func pauseRunsJoinTheRowTheyFollow() {
    let project = rowsProject()
    let rows = computeLines(segments: project.segments)

    #expect(rows.count == 2)
    #expect(rows[0].words.map(\.word).prefix(2) == ["Hello", "there."])
    #expect(rows[0].words.dropFirst(2).allSatisfy { $0.isActualSilence })
    #expect(rows[0].words.count > 2)
    #expect(rows[1].words.map(\.word) == ["Second", "line."])
}

@Test func settingWordsDeletedIsOneUndoStep() {
    let project = rowsProject()
    let ids = Set(project.allWords.prefix(2).map(\.id))

    #expect(project.setWords(ids, deleted: true) == ids)
    #expect(ids.allSatisfy { project.word(withID: $0)?.deleted == true })
    #expect(project.setWords(ids, deleted: true).isEmpty)

    project.undo()
    #expect(ids.allSatisfy { project.word(withID: $0)?.deleted == false })
}

@Test @MainActor func sentenceToggleCutsAndKeepsTheWholeSentence() throws {
    let project = rowsProject()
    let view = TranscriptView()
    view.project = project
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view
    view.setTranscript(segments: project.segments)
    window.layoutIfNeeded()
    view.onSetWordsDeleted = { ids, deleted in
        let changed = project.setWords(ids, deleted: deleted)
        view.updateWordAppearances(wordIDs: changed)
    }

    #expect(view.rows.count == 2)
    #expect(view.rowState(1) == .keep)
    view.toggleRow(1)
    #expect(view.rowState(1) == .cut)
    view.toggleRow(1)
    #expect(view.rowState(1) == .keep)

    // A pause chip is one displayed span for its whole run of silence tokens.
    let pauseID = try #require(view.rows[0].words.first(where: \.isActualSilence)?.id)
    #expect(view.displayedWordText(id: pauseID)?.hasSuffix("s\u{2009}") == true)
}

@Test @MainActor func transcriptReadsAsParagraphsNotSubtitleLines() {
    let project = ProjectDocument()
    let sentences = ["One two three.", "Four five six.", "Seven eight nine.", "Ten eleven twelve.", "Thirteen fourteen."]
    var words: [RawWord] = []
    var time = 0.0
    for sentence in sentences {
        for token in sentence.split(separator: " ") {
            words.append(RawWord(word: String(token), start: time, end: time + 0.3, confidence: 1))
            time += 0.35
        }
    }
    project.setTranscript(RawTranscript(segments: [RawSegment(id: 0, words: words)], language: "en", duration: time))
    let view = TranscriptView()
    view.project = project
    view.setTranscript(segments: project.segments)

    // Five sentences flow into two paragraphs (three, then two), separated by one line break.
    #expect(view.rows.count == 5)
    #expect(view.paragraphStarts.count == 2)
    #expect(view.displayedText.components(separatedBy: "\n").count == 2)
    #expect(view.displayedText.hasPrefix("One two three. Four five six. Seven eight nine."))
    #expect(view.displayedText.components(separatedBy: "\n").allSatisfy { !$0.hasPrefix(" ") })
}

@Test @MainActor func previewFloatsOverAFullWidthTranscript() {
    let suite = "redact.tests.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    let controller = MainSplitViewController(preferences: preferences)
    controller.view.frame = NSRect(x: 0, y: 0, width: 1_400, height: 900)
    controller.showEditing(segments: [])
    controller.view.layoutSubtreeIfNeeded()

    let preview = controller.floatingPreview!.convert(controller.floatingPreview!.bounds, to: controller.view)
    let transcript = controller.transcriptView!.convert(controller.transcriptView!.bounds, to: controller.view)
    #expect(abs(transcript.width - 1_400) < 0.5)
    #expect(transcript.contains(preview))
    #expect(abs(preview.maxX - (1_400 - FloatingPreviewView.edgeMargin)) < 0.5)
    #expect(controller.cleanupBarView != nil)
}

@Test func cleanupBarGroupsSelectableSuggestionsByKind() {
    let suggestions = [
        TranscriptCleanupSuggestion(id: "a", kind: .fillerWords, wordIDs: ["w1"], changeDescription: "", context: "", startTime: 1, removedDuration: 0.3),
        TranscriptCleanupSuggestion(id: "b", kind: .fillerWords, wordIDs: ["w5"], changeDescription: "", context: "", startTime: 5, removedDuration: 0.3),
        TranscriptCleanupSuggestion(id: "c", kind: .longPauses, wordIDs: ["s1", "s2"], changeDescription: "", context: "", startTime: 8, removedDuration: 1),
    ]
    let categories = CleanupBarView.categories(from: suggestions)

    #expect(categories.map(\.title) == ["Remove fillers", "Tighten pauses"])
    #expect(categories[0].count == 2)
    #expect(categories[0].wordIDs == ["w1", "w5"])
    #expect(categories[1].wordIDs == ["s1", "s2"])
}

@Test @MainActor func readingColumnStaysClearOfTheFloatingPreview() {
    let suite = "redact.tests.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: suite)!
    defer { preferences.removePersistentDomain(forName: suite) }
    let controller = MainSplitViewController(preferences: preferences)
    controller.view.frame = NSRect(x: 0, y: 0, width: 1_400, height: 900)
    controller.showEditing(segments: [])
    controller.view.layoutSubtreeIfNeeded()

    let reserve = FloatingPreviewView.largeWidth + FloatingPreviewView.edgeMargin
    #expect(abs(controller.transcriptView!.trailingReserve - reserve) < 0.5)

    controller.togglePreview()
    #expect(controller.transcriptView!.trailingReserve == 0)
}

@Test @MainActor func transcribedLeadingSpacesDoNotIndentParagraphs() {
    let project = ProjectDocument()
    let tokens = [" One", " two.", " Three", " four.", " Five", " six.", " Seven", " eight."]
    let words = tokens.enumerated().map { index, text in
        RawWord(word: text, start: Double(index) * 0.4, end: Double(index) * 0.4 + 0.3, confidence: 1)
    }
    project.setTranscript(RawTranscript(segments: [RawSegment(id: 0, words: words)], language: "en", duration: 4))
    let view = TranscriptView()
    view.project = project
    view.setTranscript(segments: project.segments)

    #expect(view.displayedText.components(separatedBy: "\n").allSatisfy { !$0.hasPrefix(" ") })
    #expect(!view.displayedText.contains("  "))
}
