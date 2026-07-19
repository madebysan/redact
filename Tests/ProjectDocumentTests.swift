import Testing
@testable import Redact

private func makeRawTranscript() -> RawTranscript {
    RawTranscript(
        segments: [
            RawSegment(
                id: 0,
                words: [
                    RawWord(word: "one", start: 0.0, end: 0.3, confidence: 0.9),
                    RawWord(word: "two", start: 0.4, end: 0.7, confidence: 0.9),
                    RawWord(word: "three", start: 0.8, end: 1.2, confidence: 0.9),
                ]
            ),
        ],
        language: "en",
        duration: 1.5
    )
}

private func makeProjectDocument() -> ProjectDocument {
    let project = ProjectDocument()
    project.setTranscript(makeRawTranscript())
    return project
}

@Test func projectDocument_deletesMultipleSelectedWordsAndKeepsRepresentationsAligned() {
    let project = makeProjectDocument()

    project.selectWords(["w_0", "w_2"])
    let changedWordIDs = project.deleteSelected()

    #expect(project.allWords.map(\.deleted) == [true, false, true])
    #expect(project.segments.flatMap(\.words).map(\.deleted) == [true, false, true])
    #expect(project.editDecisionList.deletedWordIDs == ["w_0", "w_2"])
    #expect(changedWordIDs == ["w_0", "w_2"])
    #expect(project.selectedWordIds.isEmpty)
    #expect(project.canUndo)
    #expect(!project.canRedo)
}

@Test func projectDocument_undoAndRedoRestoreTheSameDeletion() {
    let project = makeProjectDocument()
    project.selectWords(["w_1"])
    project.deleteSelected()

    let undoChanges = project.undo()
    #expect(project.allWords.map(\.deleted) == [false, false, false])
    #expect(project.editDecisionList.deletedWordIDs.isEmpty)
    #expect(undoChanges == ["w_1"])
    #expect(!project.canUndo)
    #expect(project.canRedo)

    let redoChanges = project.redo()
    #expect(project.allWords.map(\.deleted) == [false, true, false])
    #expect(project.editDecisionList.deletedWordIDs == ["w_1"])
    #expect(redoChanges == ["w_1"])
    #expect(project.canUndo)
    #expect(!project.canRedo)
}

@Test func projectDocument_restoreWordIsUndoable() {
    let project = makeProjectDocument()
    project.selectWords(["w_1"])
    project.deleteSelected()

    let restoreChanges = project.restoreWord("w_1")
    #expect(project.allWords[1].deleted == false)
    #expect(restoreChanges == ["w_1"])

    project.undo()
    #expect(project.allWords[1].deleted)
}

@Test func projectDocumentRestoresSelectedDeletedWordsForKeyboardWorkflows() {
    let project = makeProjectDocument()
    project.selectWords(["w_0", "w_1"])
    _ = project.deleteSelected()
    project.selectWords(["w_0", "w_1"])

    let changedWordIDs = project.restoreSelected()

    #expect(changedWordIDs == ["w_0", "w_1"])
    #expect(project.allWords.prefix(2).allSatisfy { !$0.deleted })
    #expect(project.selectedWordIds.isEmpty)
    #expect(project.undo() == ["w_0", "w_1"])
    #expect(project.allWords.prefix(2).allSatisfy { $0.deleted })
}

@Test func projectDocument_capsUndoHistoryAtOneHundredEntries() {
    let project = makeProjectDocument()

    for operation in 0..<101 {
        if operation.isMultiple(of: 2) {
            project.selectWords(["w_0"])
            project.deleteSelected()
        } else {
            project.restoreWord("w_0")
        }
    }

    #expect(project.undoStack.count == 100)
}

@Test func projectDocumentSelectionReportsOnlyChangedAppearances() {
    let project = makeProjectDocument()

    #expect(project.selectWords(["w_0", "w_1"]) == ["w_0", "w_1"])
    #expect(project.selectWords(["w_1", "w_2"]) == ["w_0", "w_2"])
    #expect(project.clearSelection() == ["w_1", "w_2"])
}

@Test func projectDocumentUsesItsTranscriptIndexForLookupAndRanges() throws {
    let project = makeProjectDocument()

    #expect(project.word(withID: "w_1")?.word == "two")
    #expect(project.wordIDs(from: "w_2", to: "w_0") == ["w_0", "w_1", "w_2"])
    #expect(project.word(withID: "missing") == nil)
    #expect(project.wordIDs(from: "missing", to: "w_0").isEmpty)
    #expect(try #require(project.sourceTranscript).words.map(\.text) == ["one", "two", "three"])
}

@Test func projectDocumentRenderPlanUsesCanonicalEditDecisions() throws {
    let project = makeProjectDocument()
    project.selectWords(["w_1"])
    project.deleteSelected()

    let plan = try #require(project.renderPlan(policy: .mediaV1))

    #expect(plan.deletedRanges == buildDeletedRanges(project.allWords))
    #expect(plan.editedDuration < project.duration)
}

@Test func projectDocumentCorrectsDisplayTextWithoutChangingTimingOrCuts() throws {
    let project = makeProjectDocument()
    project.selectWords(["w_0"])
    _ = project.deleteSelected()
    let planBeforeCorrection = try #require(project.renderPlan(policy: .mediaV1))

    let changedWordIDs = project.correctWordText(id: "w_1", text: "corrected")

    #expect(changedWordIDs == ["w_1"])
    #expect(project.word(withID: "w_1")?.word == "corrected")
    #expect(project.segments.flatMap(\.words).first { $0.id == "w_1" }?.word == "corrected")
    #expect(project.sourceTranscript?.words.first { $0.id == "w_1" }?.text == "corrected")
    #expect(project.renderPlan(policy: .mediaV1) == planBeforeCorrection)
    #expect(generateSrt(words: project.allWords, totalDuration: project.duration).contains("corrected"))
    let savedProject = try ProjectFileCodec.decode(
        ProjectFileCodec.encode(
            ProjectFile(
                media: ProjectMediaReference(
                    displayName: "source.mov",
                    fingerprint: nil,
                    relativePath: nil,
                    bookmarkData: nil
                ),
                transcript: try #require(project.sourceTranscript),
                edits: project.editDecisionList,
                segmentStartWordIDs: project.segments.compactMap { $0.words.first?.id }
            )
        )
    )
    #expect(savedProject.transcript.words.first { $0.id == "w_1" }?.text == "corrected")

    #expect(project.undo() == ["w_1"])
    #expect(project.word(withID: "w_1")?.word == "two")
    #expect(project.renderPlan(policy: .mediaV1) == planBeforeCorrection)

    #expect(project.redo() == ["w_1"])
    #expect(project.word(withID: "w_1")?.word == "corrected")
    #expect(project.renderPlan(policy: .mediaV1) == planBeforeCorrection)
}

@Test func projectDocumentRejectsInvalidDisplayTextCorrections() {
    let project = makeProjectDocument()

    #expect(project.correctWordText(id: "w_0", text: "   ").isEmpty)
    #expect(project.correctWordText(id: "missing", text: "corrected").isEmpty)
    #expect(project.correctWordText(id: "w_0", text: String(repeating: "x", count: 201)).isEmpty)
    #expect(project.word(withID: "w_0")?.word == "one")
    #expect(!project.canUndo)
}

@Test func projectDocumentKeepsTranscriptEditableWhenMediaIsMissing() {
    let transcript = SourceTranscript(
        words: [
            TranscriptWord(
                id: "w_0",
                text: "safe",
                start: 0,
                end: 0.5,
                confidence: 0.9,
                isSilence: false
            ),
        ],
        language: "en",
        duration: 1
    )
    let project = ProjectDocument()

    project.loadProject(
        transcript: transcript,
        edits: EditDecisionList(deletedWordIDs: ["w_0"]),
        segmentStartWordIDs: ["w_0"],
        filePath: ""
    )

    #expect(project.appState == .missingMedia)
    #expect(project.hasEditableTranscript)
    #expect(project.allWords.first?.word == "safe")
    #expect(project.allWords.first?.deleted == true)
}
