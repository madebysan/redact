import Foundation
import Testing
@testable import Redact

@Test func syntheticTranscriptFixturesCoverTargetScales() {
    for count in [5_000, 25_000, 100_000] {
        let words = makeSyntheticWords(count: count)

        #expect(words.count == count)
        #expect(words.first?.id == "synthetic_0")
        #expect(words.last?.id == "synthetic_\(count - 1)")
    }
}

@Test func canonicalEditPlanPerformance() {
    guard ProcessInfo.processInfo.environment["RUN_REDACT_BENCHMARKS"] == "1" else {
        return
    }

    for count in [5_000, 25_000, 100_000] {
        let words = makeSyntheticWords(count: count)
        let duration = Double(count) * 0.22

        let v1Start = Date.timeIntervalSinceReferenceDate
        let v1DeletedRanges = buildDeletedRanges(words)
        let v1Elapsed = Date.timeIntervalSinceReferenceDate - v1Start

        let transcript = SourceTranscript(v1Words: words, language: "en", duration: duration)
        let edits = EditDecisionList(v1Words: words)

        let planStart = Date.timeIntervalSinceReferenceDate
        let plan = RenderPlan(transcript: transcript, edits: edits, policy: .mediaV1)
        let planElapsed = Date.timeIntervalSinceReferenceDate - planStart

        let indexStart = Date.timeIntervalSinceReferenceDate
        let index = TranscriptIndex(transcript: transcript)
        let indexElapsed = Date.timeIntervalSinceReferenceDate - indexStart

        #expect(plan.deletedRanges == v1DeletedRanges)
        #expect(index.position(forWordID: "synthetic_\(count - 1)") == count - 1)

        print(
            String(
                format: "REDACT_BENCHMARK words=%d v1_ranges_ms=%.3f render_plan_ms=%.3f index_ms=%.3f",
                count,
                v1Elapsed * 1000,
                planElapsed * 1000,
                indexElapsed * 1000
            )
        )
    }
}

@Test func indexedProjectEditPerformance() {
    guard ProcessInfo.processInfo.environment["RUN_REDACT_BENCHMARKS"] == "1" else {
        return
    }

    let words = makeSyntheticWords(count: 100_000).enumerated().map { index, word in
        Word(
            id: word.id,
            word: word.word,
            start: word.start,
            end: word.end,
            confidence: word.confidence,
            deleted: index.isMultiple(of: 2),
            isSilence: word.isSilence
        )
    }
    let project = ProjectDocument()
    project.loadProject(
        segments: [Segment(id: 0, words: words)],
        language: "en",
        duration: Double(words.count) * 0.22,
        filePath: "/benchmark.mov"
    )
    project.selectWords(["synthetic_50001"])

    let start = Date.timeIntervalSinceReferenceDate
    let changedWordIDs = project.deleteSelected()
    let elapsed = Date.timeIntervalSinceReferenceDate - start

    #expect(changedWordIDs == ["synthetic_50001"])
    #expect(project.editDecisionList.contains(wordID: "synthetic_50001"))
    #expect(elapsed < 0.016)
    print(String(format: "REDACT_BENCHMARK indexed_single_edit_ms=%.3f", elapsed * 1000))
}

@Test func transcriptSelectionIndexPerformance() {
    guard ProcessInfo.processInfo.environment["RUN_REDACT_BENCHMARKS"] == "1" else {
        return
    }

    let spans = (0..<100_000).map { index in
        TranscriptSelectionSpan(
            wordID: "synthetic_\(index)",
            range: NSRange(location: index * 8, length: 7)
        )
    }

    let buildStart = Date.timeIntervalSinceReferenceDate
    let index = TranscriptSelectionIndex(spans: spans)
    let buildElapsed = Date.timeIntervalSinceReferenceDate - buildStart

    let pointStart = Date.timeIntervalSinceReferenceDate
    let pointSelection = index.wordIDs(intersecting: [NSRange(location: 400_003, length: 0)])
    let pointElapsed = Date.timeIntervalSinceReferenceDate - pointStart

    let fullStart = Date.timeIntervalSinceReferenceDate
    let fullSelection = index.wordIDs(intersecting: [NSRange(location: 0, length: 799_999)])
    let fullElapsed = Date.timeIntervalSinceReferenceDate - fullStart

    let replacementStart = Date.timeIntervalSinceReferenceDate
    let correctedIndex = index.replacingWordText(wordID: "synthetic_50000", newLength: 9)
    let replacementElapsed = Date.timeIntervalSinceReferenceDate - replacementStart

    #expect(pointSelection == ["synthetic_50000"])
    #expect(fullSelection.count == 100_000)
    #expect(correctedIndex.spans[50_001].range.location == index.spans[50_001].range.location + 2)
    #expect(pointElapsed < 0.016)
    print(
        String(
            format: "REDACT_BENCHMARK selection_index_build_ms=%.3f point_selection_ms=%.3f select_all_ms=%.3f corrected_range_shift_ms=%.3f",
            buildElapsed * 1000,
            pointElapsed * 1000,
            fullElapsed * 1000,
            replacementElapsed * 1000
        )
    )
}

@Test func displayTextCorrectionPerformance() {
    guard ProcessInfo.processInfo.environment["RUN_REDACT_BENCHMARKS"] == "1" else {
        return
    }

    let words = makeSyntheticWords(count: 100_000)
    let project = ProjectDocument()
    project.loadProject(
        segments: [Segment(id: 0, words: words)],
        language: "en",
        duration: Double(words.count) * 0.22,
        filePath: "/benchmark.mov"
    )

    let correctionStart = Date.timeIntervalSinceReferenceDate
    let changedWordIDs = project.correctWordText(
        id: "synthetic_50000",
        text: "corrected"
    )
    let correctionElapsed = Date.timeIntervalSinceReferenceDate - correctionStart

    #expect(changedWordIDs == ["synthetic_50000"])
    #expect(project.word(withID: "synthetic_50000")?.word == "corrected")
    #expect(correctionElapsed < 0.016)
    print(
        String(
            format: "REDACT_BENCHMARK display_text_correction_ms=%.3f",
            correctionElapsed * 1000
        )
    )
}

@Test @MainActor func transcriptViewLoadAndCorrectionPerformance() {
    guard ProcessInfo.processInfo.environment["RUN_REDACT_BENCHMARKS"] == "1" else {
        return
    }

    let words = makeSyntheticWords(count: 100_000)
    let project = ProjectDocument()
    project.loadProject(
        segments: [Segment(id: 0, words: words)],
        language: "en",
        duration: Double(words.count) * 0.22,
        filePath: "/benchmark.mov"
    )
    let view = TranscriptView(frame: NSRect(x: 0, y: 0, width: 900, height: 700))
    view.project = project

    let loadStart = Date.timeIntervalSinceReferenceDate
    view.setTranscript(segments: project.segments)
    let loadElapsed = Date.timeIntervalSinceReferenceDate - loadStart

    _ = project.correctWordText(id: "synthetic_50000", text: "corrected")
    let correctionStart = Date.timeIntervalSinceReferenceDate
    let didPatch = view.updateCorrectedWord(
        id: "synthetic_50000",
        text: "corrected",
        segments: project.segments
    )
    let correctionElapsed = Date.timeIntervalSinceReferenceDate - correctionStart

    #expect(view.usesViewportTextLayout)
    #expect(didPatch)
    #expect(view.displayedWordText(id: "synthetic_50000") == "corrected")
    #expect(correctionElapsed < 0.016)
    print(
        String(
            format: "REDACT_BENCHMARK transcript_view_load_ms=%.3f transcript_view_correction_ms=%.3f",
            loadElapsed * 1000,
            correctionElapsed * 1000
        )
    )
}
