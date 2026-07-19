import Foundation

struct SubtitleSidecar: Equatable, Sendable {
    let url: URL
    let contents: String
}

enum SubtitleSidecarBuilder {
    static func make(
        outputURL: URL,
        transcript: SourceTranscript,
        edits: EditDecisionList,
        renderPlan: RenderPlan
    ) -> SubtitleSidecar {
        SubtitleSidecar(
            url: outputURL.deletingPathExtension().appendingPathExtension("srt"),
            contents: generateSrt(
                transcript: transcript,
                edits: edits,
                renderPlan: renderPlan
            )
        )
    }
}
