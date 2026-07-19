import Foundation
import Testing
@testable import Redact

@Test func subtitleSidecarUsesTheMediaBaseNameAndCanonicalEditedTimeline() {
    let transcript = SourceTranscript(
        words: [
            TranscriptWord(id: "keep", text: "Keep", start: 0, end: 1, confidence: 1, isSilence: false),
            TranscriptWord(id: "cut", text: "remove", start: 1, end: 2, confidence: 1, isSilence: false),
            TranscriptWord(id: "end", text: "this.", start: 2, end: 3, confidence: 1, isSilence: false),
        ],
        language: "en",
        duration: 3
    )
    let edits = EditDecisionList(deletedWordIDs: ["cut"])
    let plan = RenderPlan(transcript: transcript, edits: edits, policy: .mediaV1)

    let sidecar = SubtitleSidecarBuilder.make(
        outputURL: URL(fileURLWithPath: "/tmp/interview_edited.mp4"),
        transcript: transcript,
        edits: edits,
        renderPlan: plan
    )

    #expect(sidecar.url.path == "/tmp/interview_edited.srt")
    #expect(!sidecar.contents.contains("remove"))
    #expect(sidecar.contents.contains("Keep this."))
}
