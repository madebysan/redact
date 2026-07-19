import Foundation

/// Generate SRT content from transcript words.
/// Groups consecutive non-deleted words into subtitle segments.
/// Timestamps are recalculated relative to the edited timeline.
func generateSrt(words: [Word], totalDuration: Double) -> String {
    let transcript = SourceTranscript(
        v1Words: words,
        language: "",
        duration: totalDuration
    )
    let edits = EditDecisionList(v1Words: words)
    let renderPlan = RenderPlan(
        transcript: transcript,
        edits: edits,
        policy: .mediaV1
    )
    return generateSrt(
        transcript: transcript,
        edits: edits,
        renderPlan: renderPlan
    )
}

func generateSrt(
    transcript: SourceTranscript,
    edits: EditDecisionList,
    renderPlan: RenderPlan
) -> String {
    let keptWords = transcript.words.filter { !edits.contains(wordID: $0.id) }
    if keptWords.isEmpty { return "" }

    let timelineMap = renderPlan.timelineMap

    // Group words into subtitle segments (max 10 words, break at sentence boundaries)
    struct SrtSegment {
        let words: [TranscriptWord]
        let start: Double
        let end: Double
    }

    var segments: [SrtSegment] = []
    var currentGroup: [TranscriptWord] = []

    for word in keptWords {
        currentGroup.append(word)

        let isSentenceEnd = word.text.hasSuffix(".")
            || word.text.hasSuffix("!")
            || word.text.hasSuffix("?")
        let isLongEnough = currentGroup.count >= 10

        if isSentenceEnd || isLongEnough {
            segments.append(SrtSegment(
                words: currentGroup,
                start: currentGroup[0].start,
                end: word.end
            ))
            currentGroup = []
        }
    }

    // Remaining words
    if !currentGroup.isEmpty {
        segments.append(SrtSegment(
            words: currentGroup,
            start: currentGroup[0].start,
            end: currentGroup[currentGroup.count - 1].end
        ))
    }

    // Generate SRT
    var lines: [String] = []
    for (i, seg) in segments.enumerated() {
        let startEdited = timelineMap.editedTime(forSourceTime: seg.start)
        let endEdited = timelineMap.editedTime(forSourceTime: seg.end)
        let text = seg.words.map(\.text).joined(separator: " ")

        lines.append("\(i + 1)")
        lines.append("\(formatSrtTime(startEdited)) --> \(formatSrtTime(endEdited))")
        lines.append(text)
        lines.append("")
    }

    return lines.joined(separator: "\n")
}
