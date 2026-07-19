import Foundation
import Testing
@testable import Redact

@Test func agentSnapshotIsPrivacySafeAndDigestIsDeterministic() throws {
    let project = makeAgentProject()

    let first = try AgentSnapshotBuilder.make(
        project: project,
        agent: .codex,
        snapshotID: "00000000-0000-0000-0000-000000000001"
    )
    let second = try AgentSnapshotBuilder.make(
        project: project,
        agent: first.agent,
        snapshotID: "00000000-0000-0000-0000-000000000002"
    )
    let data = try AgentSnapshotCodec.encode(first)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

    #expect(first.baseDigest == second.baseDigest)
    #expect(first.currentDuration == project.renderPlan(policy: .mediaV1)?.editedDuration)
    #expect(Set(object.keys) == [
        "version", "snapshotID", "baseDigest", "agent",
        "words", "currentDuration", "timingPolicy",
    ])

    let encoded = try #require(String(data: data, encoding: .utf8))
    #expect(!encoded.contains("source.mov"))
    #expect(!encoded.contains("/private/"))
    #expect(!encoded.contains("bookmark"))
    #expect(!encoded.contains("fingerprint"))
    #expect(!encoded.contains("confidence"))
}

@Test func agentProposalValidationAcceptsKnownMatchingWords() throws {
    let project = makeAgentProject()
    let snapshot = try AgentSnapshotBuilder.make(
        project: project,
        agent: .claudeCode,
        snapshotID: "00000000-0000-0000-0000-000000000003"
    )
    let proposal = makeProposal(
        snapshot: snapshot,
        groups: [
            AgentProposalGroup(
                id: "remove-peter",
                words: [AgentProposalWord(id: "w_1", expectedText: "Peter")],
                reason: "Remove the named person",
                category: .namedTerm,
                requirement: .required,
                priority: 100
            ),
        ]
    )

    let review = try AgentProposalValidator.review(
        proposal,
        snapshot: snapshot,
        project: project
    )

    #expect(review.groups.count == 1)
    #expect(review.groups[0].issue == nil)
    #expect(review.initiallySelectedGroupIDs == ["remove-peter"])
    #expect(review.selectedWordIDs(for: review.initiallySelectedGroupIDs) == ["w_1"])
}

@Test func agentProposalValidationRejectsStaleUnknownAndDuplicateTargets() throws {
    let project = makeAgentProject()
    let snapshot = try AgentSnapshotBuilder.make(
        project: project,
        agent: .codex,
        snapshotID: "00000000-0000-0000-0000-000000000004"
    )

    var stale = makeProposal(snapshot: snapshot, groups: [proposalGroup(id: "one", wordID: "w_0")])
    stale = AgentEditProposal(
        version: stale.version,
        snapshotID: stale.snapshotID,
        baseDigest: String(repeating: "0", count: 64),
        agent: stale.agent,
        goal: stale.goal,
        targetReductionSeconds: stale.targetReductionSeconds,
        groups: stale.groups
    )
    #expect(throws: AgentProposalError.staleSnapshot) {
        try AgentProposalValidator.review(stale, snapshot: snapshot, project: project)
    }

    let unknown = makeProposal(
        snapshot: snapshot,
        groups: [proposalGroup(id: "unknown", wordID: "w_999")]
    )
    #expect(throws: AgentProposalError.unknownWordID("w_999")) {
        try AgentProposalValidator.review(unknown, snapshot: snapshot, project: project)
    }

    let duplicate = makeProposal(
        snapshot: snapshot,
        groups: [
            proposalGroup(id: "first", wordID: "w_0"),
            proposalGroup(id: "second", wordID: "w_0"),
        ]
    )
    #expect(throws: AgentProposalError.duplicateWordID("w_0")) {
        try AgentProposalValidator.review(duplicate, snapshot: snapshot, project: project)
    }
}

@Test func agentProposalExpectedTextMismatchIsVisibleAndNotSelected() throws {
    let project = makeAgentProject()
    let snapshot = try AgentSnapshotBuilder.make(
        project: project,
        agent: .codex,
        snapshotID: "00000000-0000-0000-0000-000000000005"
    )
    let proposal = makeProposal(
        snapshot: snapshot,
        groups: [
            AgentProposalGroup(
                id: "mismatch",
                words: [AgentProposalWord(id: "w_1", expectedText: "Pete")],
                reason: "Remove the name",
                category: .namedTerm,
                requirement: .required,
                priority: nil
            ),
        ]
    )

    let review = try AgentProposalValidator.review(
        proposal,
        snapshot: snapshot,
        project: project
    )

    #expect(review.groups[0].issue == .expectedTextMismatch(
        wordID: "w_1",
        expected: "Pete",
        actual: "Peter"
    ))
    #expect(review.initiallySelectedGroupIDs.isEmpty)
}

@Test func agentProposalCodecRejectsUnexpectedAndOversizedPayloads() throws {
    let project = makeAgentProject()
    let snapshot = try AgentSnapshotBuilder.make(
        project: project,
        agent: .codex,
        snapshotID: "00000000-0000-0000-0000-000000000006"
    )
    let proposal = makeProposal(
        snapshot: snapshot,
        groups: [proposalGroup(id: "one", wordID: "w_1")]
    )
    let validData = try AgentProposalCodec.encode(proposal)
    var object = try #require(JSONSerialization.jsonObject(with: validData) as? [String: Any])
    object["command"] = "delete the project"
    let unexpected = try JSONSerialization.data(withJSONObject: object)

    #expect(throws: AgentProposalError.unexpectedField("command")) {
        try AgentProposalCodec.decode(unexpected)
    }

    let oversized = Data(repeating: 0x20, count: AgentExchangeLimits.maximumProposalBytes + 1)
    #expect(throws: AgentProposalError.fileTooLarge) {
        try AgentProposalCodec.decode(oversized)
    }
}

@Test func agentProposalCodecEnforcesItemCountLimits() throws {
    let project = makeAgentProject()
    let snapshot = try AgentSnapshotBuilder.make(
        project: project,
        agent: .codex,
        snapshotID: "00000000-0000-0000-0000-000000000008"
    )
    let groups = (0...AgentExchangeLimits.maximumGroups).map { index in
        AgentProposalGroup(
            id: "group-\(index)",
            words: [AgentProposalWord(id: "w_0", expectedText: "Hello")],
            reason: "Suggested deletion",
            category: .semanticCut,
            requirement: .optional,
            priority: nil
        )
    }
    let proposal = makeProposal(snapshot: snapshot, groups: groups)

    #expect(throws: AgentProposalError.tooManyGroups) {
        try AgentProposalCodec.encode(proposal)
    }
}

@Test func agentDurationTargetUsesCanonicalRenderPlan() throws {
    let project = makeAgentProject()
    let snapshot = try AgentSnapshotBuilder.make(
        project: project,
        agent: .codex,
        snapshotID: "00000000-0000-0000-0000-000000000007"
    )
    let proposal = AgentEditProposal(
        version: AgentProposalCodec.currentVersion,
        snapshotID: snapshot.snapshotID,
        baseDigest: snapshot.baseDigest,
        agent: snapshot.agent.displayName,
        goal: "Shorten this by about one second",
        targetReductionSeconds: 1,
        groups: [
            proposalGroup(id: "required", wordID: "w_1", requirement: .required, priority: 100),
            proposalGroup(id: "optional-near", wordID: "s_0", priority: 50),
            proposalGroup(id: "optional-far", wordID: "w_2", priority: 10),
        ]
    )

    let review = try AgentProposalValidator.review(
        proposal,
        snapshot: snapshot,
        project: project
    )
    let selectedIDs = review.selectedWordIDs(for: review.initiallySelectedGroupIDs)
    let projectedPlan = try #require(project.renderPlan(
        deletingAdditionalWordIDs: selectedIDs,
        policy: .mediaV1
    ))

    #expect(review.projectedDuration == projectedPlan.editedDuration)
    #expect(review.initiallySelectedGroupIDs.contains("required"))
}

private func makeAgentProject() -> ProjectDocument {
    let project = ProjectDocument()
    project.filePath = "/private/source.mov"
    project.setTranscript(
        RawTranscript(
            segments: [
                RawSegment(
                    id: 0,
                    words: [
                        RawWord(word: "Hello", start: 0, end: 0.4, confidence: 0.9),
                        RawWord(word: "Peter", start: 1.5, end: 2, confidence: 0.9),
                        RawWord(word: "again", start: 2.2, end: 2.7, confidence: 0.9),
                    ]
                ),
            ],
            language: "en",
            duration: 3
        )
    )
    return project
}

private func makeProposal(
    snapshot: AgentTranscriptSnapshot,
    groups: [AgentProposalGroup]
) -> AgentEditProposal {
    AgentEditProposal(
        version: AgentProposalCodec.currentVersion,
        snapshotID: snapshot.snapshotID,
        baseDigest: snapshot.baseDigest,
        agent: snapshot.agent.displayName,
        goal: "Remove Peter",
        targetReductionSeconds: nil,
        groups: groups
    )
}

private func proposalGroup(
    id: String,
    wordID: String,
    requirement: AgentProposalRequirement = .optional,
    priority: Int? = nil
) -> AgentProposalGroup {
    AgentProposalGroup(
        id: id,
        words: [AgentProposalWord(id: wordID, expectedText: wordID == "s_0" ? "—" : nil)],
        reason: "Suggested deletion",
        category: wordID == "s_0" ? .pause : .semanticCut,
        requirement: requirement,
        priority: priority
    )
}
