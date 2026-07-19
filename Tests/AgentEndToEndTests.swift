import Foundation
import Testing
@testable import Redact

@Test(arguments: AgentProvider.allCases)
func agentExchangeEndToEndAppliesAsOneUndoableEdit(agent: AgentProvider) throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-agent-e2e-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let project = syntheticAgentProject()
    let store = AgentExchangeStore(rootDirectory: root)
    let snapshot = try AgentSnapshotBuilder.make(
        project: project,
        agent: agent
    )
    let exchange = try store.prepare(snapshot: snapshot)
    let proposal = AgentEditProposal(
        version: AgentProposalCodec.currentVersion,
        snapshotID: snapshot.snapshotID,
        baseDigest: snapshot.baseDigest,
        agent: agent.displayName,
        goal: "Remove every Peter and shorten this by about one second",
        targetReductionSeconds: 1,
        groups: [
            AgentProposalGroup(
                id: "all-peter",
                words: [
                    AgentProposalWord(id: "w_1", expectedText: "Peter"),
                    AgentProposalWord(id: "w_3", expectedText: "Peter"),
                ],
                reason: "Remove every occurrence of Peter",
                category: .namedTerm,
                requirement: .required,
                priority: 100
            ),
            AgentProposalGroup(
                id: "shorten-pause",
                words: [AgentProposalWord(id: "s_0", expectedText: "—")],
                reason: "Shorten a long pause",
                category: .pause,
                requirement: .optional,
                priority: 50
            ),
        ]
    )
    try AgentProposalCodec.encode(proposal)
        .write(to: exchange.paths.proposalURL, options: .atomic)

    let loadedProposal = try store.loadProposalIfChanged(snapshotID: snapshot.snapshotID)
    let loaded = try #require(loadedProposal)
    let projectBytesBeforeReview = try canonicalProjectData(project)
    let review = try AgentProposalValidator.review(
        loaded,
        snapshot: snapshot,
        project: project
    )

    // Review, Cancel, and Reject are read-only until the explicit apply call.
    let stateBeforeApply = project.editDecisionList
    #expect(project.undoStack.isEmpty)
    #expect(project.editDecisionList == stateBeforeApply)
    #expect(try canonicalProjectData(project) == projectBytesBeforeReview)

    let selectedWordIDs = review.selectedWordIDs(for: review.initiallySelectedGroupIDs)
    let changedWordIDs = project.deleteWords(selectedWordIDs)
    #expect(changedWordIDs.contains("w_1"))
    #expect(changedWordIDs.contains("w_3"))
    #expect(project.undoStack.count == 1)
    #expect(project.undo() == changedWordIDs)
    #expect(project.editDecisionList == stateBeforeApply)
    #expect(try canonicalProjectData(project) == projectBytesBeforeReview)

    try store.complete(snapshotID: snapshot.snapshotID)
    #expect(!FileManager.default.fileExists(atPath: exchange.paths.directoryURL.path))
}

@Test func preparingAgentExchangeNeverWritesTheProjectFile() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-agent-project-safety-" + UUID().uuidString, isDirectory: true)
    let exchangeRoot = root.appendingPathComponent("Agent Exchange", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let projectURL = root.appendingPathComponent("project.rdt")
    let originalData = Data("canonical project bytes".utf8)
    try originalData.write(to: projectURL)
    let project = syntheticAgentProject()
    let snapshot = try AgentSnapshotBuilder.make(
        project: project,
        agent: .codex
    )

    _ = try AgentExchangeStore(rootDirectory: exchangeRoot).prepare(snapshot: snapshot)

    #expect(try Data(contentsOf: projectURL) == originalData)
}

private func syntheticAgentProject() -> ProjectDocument {
    let project = ProjectDocument()
    project.setTranscript(
        RawTranscript(
            segments: [
                RawSegment(
                    id: 0,
                    words: [
                        RawWord(word: "Hello", start: 0, end: 0.3, confidence: 1),
                        RawWord(word: "Peter", start: 0.4, end: 0.8, confidence: 1),
                        RawWord(word: "and", start: 2, end: 2.2, confidence: 1),
                        RawWord(word: "Peter", start: 2.3, end: 2.7, confidence: 1),
                        RawWord(word: "again", start: 2.8, end: 3.2, confidence: 1),
                    ]
                ),
            ],
            language: "en",
            duration: 3.5
        )
    )
    return project
}

private func canonicalProjectData(_ project: ProjectDocument) throws -> Data {
    let transcript = try #require(project.sourceTranscript)
    return try ProjectFileCodec.encode(
        ProjectFile(
            media: ProjectMediaReference(
                displayName: "synthetic.mov",
                fingerprint: nil,
                relativePath: nil,
                bookmarkData: nil
            ),
            transcript: transcript,
            edits: project.editDecisionList,
            segmentStartWordIDs: project.segments.compactMap { $0.words.first?.id }
        )
    )
}
