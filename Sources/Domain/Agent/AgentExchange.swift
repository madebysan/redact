import CryptoKit
import Foundation

enum AgentExchangeLimits {
    static let maximumSnapshotBytes = 32 * 1_024 * 1_024
    static let maximumProposalBytes = 2 * 1_024 * 1_024
    static let maximumGroups = 10_000
    static let maximumTargetedWords = 50_000
    static let maximumGoalBytes = 4 * 1_024
    static let maximumReasonBytes = 2 * 1_024
    static let maximumAgentBytes = 128
    static let maximumGroupIDBytes = 512
}

enum AgentProvider: String, Codable, CaseIterable, Sendable {
    case codex
    case claudeCode

    var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claudeCode: "Claude Code"
        }
    }
}

struct AgentSnapshotTimingPolicy: Codable, Equatable, Sendable {
    let cutPadding: Double
    let mergeTolerance: Double
    let minimumKeptDuration: Double
    let padsSilence: Bool

    init(_ policy: EditTimingPolicy) {
        cutPadding = policy.cutPadding
        mergeTolerance = policy.mergeTolerance
        minimumKeptDuration = policy.minimumKeptDuration
        padsSilence = policy.padsSilence
    }
}

struct AgentSnapshotWord: Codable, Equatable, Sendable {
    let id: String
    let text: String
    let start: Double
    let end: Double
    let isSilence: Bool
    let deleted: Bool
}

struct AgentTranscriptSnapshot: Codable, Equatable, Sendable {
    let version: Int
    let snapshotID: String
    let baseDigest: String
    let agent: AgentProvider
    let words: [AgentSnapshotWord]
    let currentDuration: Double
    let timingPolicy: AgentSnapshotTimingPolicy
}

enum AgentSnapshotBuilder {
    static func make(
        project: ProjectDocument,
        agent: AgentProvider,
        snapshotID: String = UUID().uuidString.lowercased(),
        policy: EditTimingPolicy = .mediaV1
    ) throws -> AgentTranscriptSnapshot {
        guard let transcript = project.sourceTranscript,
              let renderPlan = project.renderPlan(policy: policy) else {
            throw AgentProposalError.transcriptUnavailable
        }
        try validateSnapshotID(snapshotID)

        return AgentTranscriptSnapshot(
            version: AgentSnapshotCodec.currentVersion,
            snapshotID: snapshotID,
            baseDigest: try digest(
                transcript: transcript,
                edits: project.editDecisionList,
                policy: policy
            ),
            agent: agent,
            words: transcript.words.map { word in
                AgentSnapshotWord(
                    id: word.id,
                    text: word.text,
                    start: word.start,
                    end: word.end,
                    isSilence: word.isSilence,
                    deleted: project.editDecisionList.contains(wordID: word.id)
                )
            },
            currentDuration: renderPlan.editedDuration,
            timingPolicy: AgentSnapshotTimingPolicy(policy)
        )
    }

    static func digest(
        project: ProjectDocument,
        policy: EditTimingPolicy = .mediaV1
    ) throws -> String {
        guard let transcript = project.sourceTranscript else {
            throw AgentProposalError.transcriptUnavailable
        }
        return try digest(
            transcript: transcript,
            edits: project.editDecisionList,
            policy: policy
        )
    }

    private static func digest(
        transcript: SourceTranscript,
        edits: EditDecisionList,
        policy: EditTimingPolicy
    ) throws -> String {
        struct DigestPayload: Encodable {
            let schemaVersion: Int
            let words: [TranscriptWord]
            let duration: Double
            let deletedWordIDs: [String]
            let timingPolicy: AgentSnapshotTimingPolicy
        }

        let payload = DigestPayload(
            schemaVersion: AgentSnapshotCodec.currentVersion,
            words: transcript.words,
            duration: transcript.duration,
            deletedWordIDs: edits.deletedWordIDs.sorted(),
            timingPolicy: AgentSnapshotTimingPolicy(policy)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let digest = SHA256.hash(data: try encoder.encode(payload))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

enum AgentSnapshotCodec {
    static let currentVersion = 2

    static func encode(_ snapshot: AgentTranscriptSnapshot) throws -> Data {
        try validate(snapshot)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> AgentTranscriptSnapshot {
        guard data.count <= AgentExchangeLimits.maximumSnapshotBytes else {
            throw AgentProposalError.fileTooLarge
        }
        let snapshot = try JSONDecoder().decode(AgentTranscriptSnapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }

    private static func validate(_ snapshot: AgentTranscriptSnapshot) throws {
        guard snapshot.version == currentVersion else {
            throw AgentProposalError.unsupportedVersion(snapshot.version)
        }
        try validateSnapshotID(snapshot.snapshotID)
        try validateDigest(snapshot.baseDigest)
        guard snapshot.words.count <= ProjectFileLimits.maximumWords,
              snapshot.currentDuration.isFinite,
              snapshot.currentDuration >= 0,
              snapshot.currentDuration <= ProjectFileLimits.maximumDuration else {
            throw AgentProposalError.invalidField("snapshot duration or word count")
        }
        var wordIDs = Set<String>()
        for word in snapshot.words {
            guard wordIDs.insert(word.id).inserted else {
                throw AgentProposalError.duplicateWordID(word.id)
            }
            try validateString(
                word.id,
                maximumBytes: ProjectFileLimits.maximumWordIDBytes,
                field: "word id",
                allowEmpty: false
            )
            try validateString(
                word.text,
                maximumBytes: ProjectFileLimits.maximumWordTextBytes,
                field: "word text"
            )
            guard word.start.isFinite,
                  word.end.isFinite,
                  word.start >= 0,
                  word.end >= word.start,
                  word.end <= ProjectFileLimits.maximumDuration else {
                throw AgentProposalError.invalidField("word timing")
            }
        }
    }
}

enum AgentProposalCategory: String, Codable, CaseIterable, Sendable {
    case filler
    case pause
    case namedTerm
    case semanticCut
}

enum AgentProposalRequirement: String, Codable, Sendable {
    case required
    case optional
}

struct AgentProposalWord: Codable, Equatable, Sendable {
    let id: String
    let expectedText: String?
}

struct AgentProposalGroup: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let words: [AgentProposalWord]
    let reason: String
    let category: AgentProposalCategory
    let requirement: AgentProposalRequirement
    let priority: Int?
}

struct AgentEditProposal: Codable, Equatable, Sendable {
    let version: Int
    let snapshotID: String
    let baseDigest: String
    let agent: String
    let goal: String
    let targetReductionSeconds: Double?
    let groups: [AgentProposalGroup]
}

enum AgentProposalCodec {
    static let currentVersion = 1

    static func encode(_ proposal: AgentEditProposal) throws -> Data {
        try validateStructure(proposal)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(proposal)
    }

    static func decode(_ data: Data) throws -> AgentEditProposal {
        guard data.count <= AgentExchangeLimits.maximumProposalBytes else {
            throw AgentProposalError.fileTooLarge
        }
        try rejectUnexpectedFields(in: data)
        let proposal: AgentEditProposal
        do {
            proposal = try JSONDecoder().decode(AgentEditProposal.self, from: data)
        } catch {
            throw AgentProposalError.malformedJSON
        }
        try validateStructure(proposal)
        return proposal
    }

    private static func validateStructure(_ proposal: AgentEditProposal) throws {
        guard proposal.version == currentVersion else {
            throw AgentProposalError.unsupportedVersion(proposal.version)
        }
        try validateSnapshotID(proposal.snapshotID)
        try validateDigest(proposal.baseDigest)
        try validateString(
            proposal.agent,
            maximumBytes: AgentExchangeLimits.maximumAgentBytes,
            field: "agent",
            allowEmpty: false
        )
        try validateString(
            proposal.goal,
            maximumBytes: AgentExchangeLimits.maximumGoalBytes,
            field: "goal",
            allowEmpty: false
        )
        guard proposal.groups.count <= AgentExchangeLimits.maximumGroups else {
            throw AgentProposalError.tooManyGroups
        }
        if let target = proposal.targetReductionSeconds {
            guard target.isFinite,
                  target >= 0,
                  target <= ProjectFileLimits.maximumDuration else {
                throw AgentProposalError.invalidField("target reduction")
            }
        }

        var groupIDs = Set<String>()
        var targetedWordCount = 0
        for group in proposal.groups {
            try validateString(
                group.id,
                maximumBytes: AgentExchangeLimits.maximumGroupIDBytes,
                field: "group id",
                allowEmpty: false
            )
            guard groupIDs.insert(group.id).inserted else {
                throw AgentProposalError.duplicateGroupID(group.id)
            }
            try validateString(
                group.reason,
                maximumBytes: AgentExchangeLimits.maximumReasonBytes,
                field: "reason",
                allowEmpty: false
            )
            guard !group.words.isEmpty else {
                throw AgentProposalError.invalidField("empty proposal group")
            }
            targetedWordCount += group.words.count
            guard targetedWordCount <= AgentExchangeLimits.maximumTargetedWords else {
                throw AgentProposalError.tooManyTargetedWords
            }
            for word in group.words {
                try validateString(
                    word.id,
                    maximumBytes: ProjectFileLimits.maximumWordIDBytes,
                    field: "word id",
                    allowEmpty: false
                )
                if let expectedText = word.expectedText {
                    try validateString(
                        expectedText,
                        maximumBytes: ProjectFileLimits.maximumWordTextBytes,
                        field: "expected text"
                    )
                }
            }
        }
    }

    private static func rejectUnexpectedFields(in data: Data) throws {
        let root: [String: Any]
        do {
            root = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        } catch {
            throw AgentProposalError.malformedJSON
        }
        let rootKeys: Set<String> = [
            "version", "snapshotID", "baseDigest", "agent", "goal",
            "targetReductionSeconds", "groups",
        ]
        if let unexpected = Set(root.keys).subtracting(rootKeys).sorted().first {
            throw AgentProposalError.unexpectedField(unexpected)
        }
        guard let groups = root["groups"] as? [[String: Any]] else {
            throw AgentProposalError.malformedJSON
        }
        let groupKeys: Set<String> = [
            "id", "words", "reason", "category", "requirement", "priority",
        ]
        let wordKeys: Set<String> = ["id", "expectedText"]
        for group in groups {
            if let unexpected = Set(group.keys).subtracting(groupKeys).sorted().first {
                throw AgentProposalError.unexpectedField(unexpected)
            }
            guard let words = group["words"] as? [[String: Any]] else {
                throw AgentProposalError.malformedJSON
            }
            for word in words {
                if let unexpected = Set(word.keys).subtracting(wordKeys).sorted().first {
                    throw AgentProposalError.unexpectedField(unexpected)
                }
            }
        }
    }
}

enum AgentProposalIssue: Equatable, Sendable {
    case expectedTextMismatch(wordID: String, expected: String, actual: String)
    case alreadyDeleted(wordID: String)

    var message: String {
        switch self {
        case .expectedTextMismatch(let wordID, let expected, let actual):
            "Text changed for \(wordID): expected “\(expected)”, found “\(actual)”."
        case .alreadyDeleted(let wordID):
            "\(wordID) is already deleted."
        }
    }
}

struct AgentProposalReviewGroup: Equatable, Identifiable, Sendable {
    let proposalGroup: AgentProposalGroup
    let issue: AgentProposalIssue?

    var id: String { proposalGroup.id }
    var isSelectable: Bool { issue == nil }
}

struct AgentProposalReview: Equatable, Sendable {
    let snapshot: AgentTranscriptSnapshot
    let proposal: AgentEditProposal
    let groups: [AgentProposalReviewGroup]
    let initiallySelectedGroupIDs: Set<String>
    let projectedDuration: Double

    func selectedWordIDs(for groupIDs: Set<String>) -> Set<String> {
        Set(
            groups.lazy
                .filter { groupIDs.contains($0.id) && $0.isSelectable }
                .flatMap { $0.proposalGroup.words.map(\.id) }
        )
    }
}

enum AgentProposalValidator {
    static func review(
        _ proposal: AgentEditProposal,
        snapshot: AgentTranscriptSnapshot,
        project: ProjectDocument,
        policy: EditTimingPolicy = .mediaV1
    ) throws -> AgentProposalReview {
        guard proposal.snapshotID == snapshot.snapshotID else {
            throw AgentProposalError.wrongSnapshot
        }
        let currentDigest = try AgentSnapshotBuilder.digest(project: project, policy: policy)
        guard proposal.baseDigest == snapshot.baseDigest,
              snapshot.baseDigest == currentDigest else {
            throw AgentProposalError.staleSnapshot
        }

        let wordsByID = Dictionary(
            uniqueKeysWithValues: project.allWords.map { ($0.id, $0) }
        )
        var seenWordIDs = Set<String>()
        var reviewGroups: [AgentProposalReviewGroup] = []
        reviewGroups.reserveCapacity(proposal.groups.count)

        for group in proposal.groups {
            var issue: AgentProposalIssue?
            for proposedWord in group.words {
                guard let word = wordsByID[proposedWord.id] else {
                    throw AgentProposalError.unknownWordID(proposedWord.id)
                }
                guard seenWordIDs.insert(proposedWord.id).inserted else {
                    throw AgentProposalError.duplicateWordID(proposedWord.id)
                }
                if issue == nil,
                   let expectedText = proposedWord.expectedText,
                   expectedText != word.word {
                    issue = .expectedTextMismatch(
                        wordID: proposedWord.id,
                        expected: expectedText,
                        actual: word.word
                    )
                }
                if issue == nil, word.deleted {
                    issue = .alreadyDeleted(wordID: proposedWord.id)
                }
            }
            reviewGroups.append(
                AgentProposalReviewGroup(proposalGroup: group, issue: issue)
            )
        }

        let selectableGroups = reviewGroups.filter(\.isSelectable)
        var selectedGroupIDs = Set(
            selectableGroups.lazy
                .filter { $0.proposalGroup.requirement == .required }
                .map(\.id)
        )
        let baseDuration = project.renderPlan(policy: policy)?.editedDuration ?? 0

        if let targetReduction = proposal.targetReductionSeconds {
            let optionalGroups = selectableGroups
                .filter { $0.proposalGroup.requirement == .optional }
                .sorted {
                    let leftPriority = $0.proposalGroup.priority ?? 0
                    let rightPriority = $1.proposalGroup.priority ?? 0
                    return leftPriority == rightPriority
                        ? $0.id < $1.id
                        : leftPriority > rightPriority
                }
            var currentError = durationError(
                project: project,
                groups: reviewGroups,
                selectedGroupIDs: selectedGroupIDs,
                baseDuration: baseDuration,
                targetReduction: targetReduction,
                policy: policy
            )
            for group in optionalGroups {
                var candidate = selectedGroupIDs
                candidate.insert(group.id)
                let candidateError = durationError(
                    project: project,
                    groups: reviewGroups,
                    selectedGroupIDs: candidate,
                    baseDuration: baseDuration,
                    targetReduction: targetReduction,
                    policy: policy
                )
                if candidateError < currentError {
                    selectedGroupIDs = candidate
                    currentError = candidateError
                }
            }
        } else {
            selectedGroupIDs.formUnion(selectableGroups.map(\.id))
        }

        let selectedWordIDs = wordIDs(
            groups: reviewGroups,
            selectedGroupIDs: selectedGroupIDs
        )
        let projectedDuration = project.renderPlan(
            deletingAdditionalWordIDs: selectedWordIDs,
            policy: policy
        )?.editedDuration ?? baseDuration

        return AgentProposalReview(
            snapshot: snapshot,
            proposal: proposal,
            groups: reviewGroups,
            initiallySelectedGroupIDs: selectedGroupIDs,
            projectedDuration: projectedDuration
        )
    }

    private static func durationError(
        project: ProjectDocument,
        groups: [AgentProposalReviewGroup],
        selectedGroupIDs: Set<String>,
        baseDuration: Double,
        targetReduction: Double,
        policy: EditTimingPolicy
    ) -> Double {
        let selectedWordIDs = wordIDs(
            groups: groups,
            selectedGroupIDs: selectedGroupIDs
        )
        let duration = project.renderPlan(
            deletingAdditionalWordIDs: selectedWordIDs,
            policy: policy
        )?.editedDuration ?? baseDuration
        return abs((baseDuration - duration) - targetReduction)
    }

    private static func wordIDs(
        groups: [AgentProposalReviewGroup],
        selectedGroupIDs: Set<String>
    ) -> Set<String> {
        Set(
            groups.lazy
                .filter { selectedGroupIDs.contains($0.id) && $0.isSelectable }
                .flatMap { $0.proposalGroup.words.map(\.id) }
        )
    }
}

enum AgentProposalError: LocalizedError, Equatable {
    case transcriptUnavailable
    case fileTooLarge
    case malformedJSON
    case unsupportedVersion(Int)
    case invalidField(String)
    case unexpectedField(String)
    case tooManyGroups
    case tooManyTargetedWords
    case duplicateGroupID(String)
    case duplicateWordID(String)
    case unknownWordID(String)
    case wrongSnapshot
    case staleSnapshot

    var errorDescription: String? {
        switch self {
        case .transcriptUnavailable:
            "The transcript is not ready for agent editing."
        case .fileTooLarge:
            "The agent file is larger than Redact's safety limit."
        case .malformedJSON:
            "The agent proposal is not valid JSON in Redact's proposal format."
        case .unsupportedVersion(let version):
            "Unsupported agent exchange version: \(version)."
        case .invalidField(let field):
            "The agent proposal contains an invalid \(field)."
        case .unexpectedField(let field):
            "The agent proposal contains an unexpected field: \(field)."
        case .tooManyGroups:
            "The agent proposal contains too many edit groups."
        case .tooManyTargetedWords:
            "The agent proposal targets too many transcript words."
        case .duplicateGroupID(let id):
            "The agent proposal repeats the group identifier \(id)."
        case .duplicateWordID(let id):
            "The agent proposal targets \(id) more than once."
        case .unknownWordID(let id):
            "The agent proposal targets an unknown word: \(id)."
        case .wrongSnapshot:
            "The agent proposal belongs to a different transcript snapshot."
        case .staleSnapshot:
            "The transcript changed after this agent snapshot was prepared. Prepare a new snapshot before applying edits."
        }
    }
}

extension AgentProposalReview {
    func cleanupSuggestions(project: ProjectDocument) -> [TranscriptCleanupSuggestion] {
        let orderedWords = project.allWords
        let positions = Dictionary(
            uniqueKeysWithValues: orderedWords.enumerated().map { ($0.element.id, $0.offset) }
        )

        return groups.map { reviewGroup in
            let group = reviewGroup.proposalGroup
            let groupWords = group.words.compactMap { project.word(withID: $0.id) }
            let startTime = groupWords.map(\.start).min() ?? 0
            let removedDuration = groupWords.reduce(0) { result, word in
                result + max(0, word.end - word.start)
            }
            let groupPositions = group.words.compactMap { positions[$0.id] }
            let context: String
            if let first = groupPositions.min(), let last = groupPositions.max() {
                let lower = max(0, first - 3)
                let upper = min(orderedWords.count - 1, last + 3)
                context = orderedWords[lower...upper].enumerated().map { offset, word in
                    let absolutePosition = lower + offset
                    let text = word.isActualSilence ? "pause" : word.word
                    return (first...last).contains(absolutePosition) ? "[\(text)]" : text
                }.joined(separator: " ")
            } else {
                context = group.reason
            }

            return TranscriptCleanupSuggestion(
                id: group.id,
                kind: group.category.cleanupKind,
                wordIDs: group.words.map(\.id),
                changeDescription: group.reason,
                context: context,
                startTime: startTime,
                removedDuration: removedDuration,
                requirement: group.requirement == .required ? .required : .optional,
                validationMessage: reviewGroup.issue?.message
            )
        }
    }
}

private extension AgentProposalCategory {
    var cleanupKind: TranscriptCleanupKind {
        switch self {
        case .filler: .fillerWords
        case .pause: .longPauses
        case .namedTerm: .namedTerms
        case .semanticCut: .semanticCuts
        }
    }
}

private func validateSnapshotID(_ value: String) throws {
    guard let uuid = UUID(uuidString: value),
          uuid.uuidString.lowercased() == value.lowercased() else {
        throw AgentProposalError.invalidField("snapshot identifier")
    }
}

private func validateDigest(_ value: String) throws {
    guard value.count == 64, value.allSatisfy(\.isHexDigit) else {
        throw AgentProposalError.invalidField("base digest")
    }
}

private func validateString(
    _ value: String,
    maximumBytes: Int,
    field: String,
    allowEmpty: Bool = true
) throws {
    guard (allowEmpty || !value.isEmpty), value.utf8.count <= maximumBytes else {
        throw AgentProposalError.invalidField(field)
    }
}
