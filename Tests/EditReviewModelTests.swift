import Testing
@testable import Redact

@Test func editReviewModelUsesCanonicalCutRangesAndEditedDuration() throws {
    let transcript = SourceTranscript(
        words: [
            TranscriptWord(id: "keep-1", text: "Keep", start: 0, end: 1, confidence: 1, isSilence: false),
            TranscriptWord(id: "cut-1", text: "remove", start: 2, end: 3, confidence: 1, isSilence: false),
            TranscriptWord(id: "keep-2", text: "this", start: 5, end: 6, confidence: 1, isSilence: false),
            TranscriptWord(id: "cut-2", text: "remove", start: 8, end: 9, confidence: 1, isSilence: false),
        ],
        language: "en",
        duration: 10
    )
    let plan = RenderPlan(
        transcript: transcript,
        edits: EditDecisionList(deletedWordIDs: ["cut-1", "cut-2"]),
        policy: .mediaV1
    )

    let model = EditReviewModel(renderPlan: plan, sourceDuration: transcript.duration)

    #expect(model.cutCount == plan.deletedRanges.count)
    #expect(model.removedDuration == transcript.duration - plan.editedDuration)
    #expect(model.finalDuration == plan.editedDuration)
    #expect(model.reviewTargets.count == 2)
    let first = try #require(model.reviewTargets.first)
    let second = try #require(model.reviewTargets.last)
    #expect(model.nextTarget(from: 0) == first)
    #expect(model.nextTarget(from: first) == second)
    #expect(model.previousTarget(from: second + 1) == second)
    #expect(model.previousTarget(from: 0) == nil)
}

@Test func editReviewModelDeduplicatesCutsThatShareAReviewTarget() {
    let plan = RenderPlan(
        transcript: SourceTranscript(
            words: [
                TranscriptWord(id: "cut", text: "remove", start: 0, end: 1, confidence: 1, isSilence: false),
            ],
            language: "en",
            duration: 2
        ),
        edits: EditDecisionList(deletedWordIDs: ["cut"]),
        policy: .mediaV1
    )

    let model = EditReviewModel(renderPlan: plan, sourceDuration: 2)

    #expect(model.reviewTargets == [0])
    #expect(model.nextTarget(from: 0) == nil)
}
