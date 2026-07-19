import Foundation

struct ProjectRevision: Codable, Equatable, Sendable {
    let id: UUID
    let parentID: UUID?
    let transcript: SourceTranscript
    let edits: EditDecisionList

    init(
        id: UUID = UUID(),
        parentID: UUID? = nil,
        transcript: SourceTranscript,
        edits: EditDecisionList = EditDecisionList()
    ) {
        self.id = id
        self.parentID = parentID
        self.transcript = transcript
        self.edits = edits
    }

    func applying(_ decision: EditDecision) -> ProjectRevision {
        ProjectRevision(
            parentID: id,
            transcript: transcript,
            edits: edits.applying(decision)
        )
    }

    func correctingWordText(wordID: String, text: String) -> ProjectRevision? {
        guard let correctedTranscript = transcript.correctingWordText(
            wordID: wordID,
            text: text
        ) else {
            return nil
        }
        return ProjectRevision(
            parentID: id,
            transcript: correctedTranscript,
            edits: edits
        )
    }

    func renderPlan(policy: EditTimingPolicy) -> RenderPlan {
        RenderPlan(
            transcript: transcript,
            edits: edits,
            policy: policy
        )
    }
}
