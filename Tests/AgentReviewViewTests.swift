import AppKit
import Testing
@testable import Redact

@Test @MainActor func agentPreparationExplainsPromptFirstFlowWithoutCollectingAGoal() throws {
    let view = AgentPreparationView(
        frame: NSRect(x: 0, y: 0, width: 540, height: 280)
    )
    let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = view

    #expect(view.selectedAgent == .codex)
    #expect(recursiveLabels(in: view).contains("Agent"))
    #expect(recursiveText(in: view).contains("After the agent confirms it is connected"))
    #expect(!recursiveText(in: view).contains("What should the agent change?"))
    #expect(recursiveButtons(in: view).contains("Prepare & Copy Prompt"))
    #expect(view.focusInitialControl(in: window))

    var preparedAgent: AgentProvider?
    view.onPrepare = { preparedAgent = $0 }
    recursiveButton(in: view, titled: "Prepare & Copy Prompt")?.performClick(nil)
    #expect(preparedAgent == .codex)
}

@Test @MainActor func agentReviewShowsAttributionIssuesAndAuthoritativeDuration() {
    let suggestions = [
        TranscriptCleanupSuggestion(
            id: "required",
            kind: .namedTerms,
            wordIDs: ["w_1"],
            changeDescription: "Remove “Peter”",
            context: "Named term requested by the user",
            startTime: 1,
            removedDuration: 0.4,
            requirement: .required
        ),
        TranscriptCleanupSuggestion(
            id: "mismatch",
            kind: .semanticCuts,
            wordIDs: ["w_2"],
            changeDescription: "Remove a passage",
            context: "Suggested shortening",
            startTime: 2,
            removedDuration: 1,
            requirement: .optional,
            validationMessage: "Text changed for w_2."
        ),
    ]
    var highlightedWordIDs = Set<String>()
    let configuration = CleanupReviewConfiguration.agent(
        agentName: "Codex",
        goal: "Remove Peter",
        initialSelectedSuggestionIDs: ["required"],
        summaryProvider: { wordIDs, _, _ in
            "Projected result: 3:00 → \(wordIDs.isEmpty ? "3:00" : "2:59.6")"
        }
    )
    let view = CleanupReviewView(
        frame: NSRect(x: 0, y: 0, width: 760, height: 560),
        suggestions: suggestions,
        configuration: configuration
    )
    view.onSelectionChanged = { highlightedWordIDs = $0 }

    #expect(view.selectedSuggestionCount == 1)
    #expect(view.selectedWordIDs == ["w_1"])
    #expect(view.summaryText == "Projected result: 3:00 → 2:59.6")
    #expect(recursiveText(in: view).contains("Proposed by Codex"))
    #expect(recursiveText(in: view).contains("Remove Peter"))
    #expect(recursiveText(in: view).contains("Required"))

    view.setSuggestion("required", enabled: false)
    #expect(view.selectedWordIDs.isEmpty)
    #expect(highlightedWordIDs.isEmpty)

    view.setSuggestion("mismatch", enabled: true)
    #expect(view.selectedWordIDs.isEmpty)
}

@Test @MainActor func transcriptProposalHighlightIsTransient() {
    let project = ProjectDocument()
    project.setTranscript(
        RawTranscript(
            segments: [
                RawSegment(
                    id: 0,
                    words: [RawWord(word: "Peter", start: 0, end: 0.4, confidence: 1)]
                ),
            ],
            language: "en",
            duration: 1
        )
    )
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: 500, height: 300))
    view.project = project
    view.setTranscript(segments: project.segments)
    view.refreshAllWordAppearances()

    view.setProposedWordIDs(["w_0"])
    #expect(view.proposedWordIDs == ["w_0"])
    #expect(project.editDecisionList.deletedWordIDs.isEmpty)

    view.setProposedWordIDs([])
    #expect(view.proposedWordIDs.isEmpty)
    #expect(project.editDecisionList.deletedWordIDs.isEmpty)
}

@Test @MainActor func captureAgentSheetsWhenRequested() throws {
    guard let outputPath = ProcessInfo.processInfo.environment["REDACT_UI_CAPTURE_DIR"] else {
        return
    }
    let appearanceValue = ProcessInfo.processInfo.environment["REDACT_UI_APPEARANCE"] ?? "dark"
    let appearanceName: NSAppearance.Name = appearanceValue == "light" ? .aqua : .darkAqua
    let application = NSApplication.shared
    let originalAppearance = application.appearance
    defer { application.appearance = originalAppearance }
    application.appearance = NSAppearance(named: appearanceName)

    let preparation = AgentPreparationView(
        frame: NSRect(x: 0, y: 0, width: 540, height: 280)
    )
    try capture(
        preparation,
        at: URL(fileURLWithPath: outputPath, isDirectory: true)
            .appendingPathComponent("agent-preparation-\(appearanceValue).png")
    )

    let suggestions = [
        TranscriptCleanupSuggestion(
            id: "required",
            kind: .namedTerms,
            wordIDs: ["w_1", "w_8"],
            changeDescription: "Remove every “Peter”",
            context: "… spoke with [Peter] about the cut …",
            startTime: 12.4,
            removedDuration: 0.8,
            requirement: .required
        ),
        TranscriptCleanupSuggestion(
            id: "filler",
            kind: .fillerWords,
            wordIDs: ["w_3"],
            changeDescription: "Remove “um”",
            context: "… and [um] then we continued …",
            startTime: 28.1,
            removedDuration: 0.3,
            requirement: .required
        ),
        TranscriptCleanupSuggestion(
            id: "optional",
            kind: .semanticCuts,
            wordIDs: ["w_10", "w_11"],
            changeDescription: "Remove repeated setup",
            context: "… [as I mentioned earlier] the result …",
            startTime: 44.7,
            removedDuration: 4.1,
            requirement: .optional
        ),
        TranscriptCleanupSuggestion(
            id: "mismatch",
            kind: .semanticCuts,
            wordIDs: ["w_20"],
            changeDescription: "Remove closing aside",
            context: "Closing aside",
            startTime: 68.2,
            removedDuration: 2.2,
            requirement: .optional,
            validationMessage: "Text changed for w_20: expected “basically”, found “essentially”."
        ),
    ]
    let review = CleanupReviewView(
        frame: NSRect(x: 0, y: 0, width: 760, height: 560),
        suggestions: suggestions,
        configuration: .agent(
            agentName: "Codex",
            goal: "Remove every Peter, clean up speech, and shorten by about 30 seconds",
            initialSelectedSuggestionIDs: ["required", "filler", "optional"],
            summaryProvider: { _, selected, total in
                "\(selected) of \(total) changes selected • Projected result: 12:42.0 → 12:11.8"
            }
        )
    )
    try capture(
        review,
        at: URL(fileURLWithPath: outputPath, isDirectory: true)
            .appendingPathComponent("agent-review-\(appearanceValue).png")
    )
}

private func recursiveLabels(in view: NSView) -> [String] {
    view.subviews.flatMap { subview in
        [subview.accessibilityLabel()].compactMap { $0 } + recursiveLabels(in: subview)
    }
}

private func recursiveText(in view: NSView) -> String {
    view.subviews.map { subview in
        let ownText = (subview as? NSTextField)?.stringValue ?? ""
        return ownText + " " + recursiveText(in: subview)
    }.joined(separator: " ")
}

private func recursiveButtons(in view: NSView) -> [String] {
    view.subviews.flatMap { subview in
        [(subview as? NSButton)?.title].compactMap { $0 } + recursiveButtons(in: subview)
    }
}

private func recursiveButton(in view: NSView, titled title: String) -> NSButton? {
    for subview in view.subviews {
        if let button = subview as? NSButton, button.title == title {
            return button
        }
        if let nested = recursiveButton(in: subview, titled: title) {
            return nested
        }
    }
    return nil
}

@MainActor
private func capture(_ view: NSView, at outputURL: URL) throws {
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    view.layoutSubtreeIfNeeded()
    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: view.bounds, to: representation)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: outputURL)
}
