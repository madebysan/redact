import CryptoKit
import Foundation
import Testing
@testable import Redact

private struct WhisperWordMetric: Codable {
    let textHash: String
    let start: Double
    let end: Double
}

private struct WhisperCompatibilityReport: Codable {
    let engineLabel: String
    let model: String
    let detectedLanguage: String
    let mediaDuration: Double
    let segmentCount: Int
    let wordCount: Int
    let firstTextMilliseconds: Double?
    let totalMilliseconds: Double
    let transcriptHash: String
    let words: [WhisperWordMetric]
    let cleanupSuggestionCounts: [String: Int]
    let cleanupSuggestionCount: Int
    let cleanupWordCount: Int
    let cleanupRemovedDuration: Double
    let projectRoundTripBytes: Int
    let editedDuration: Double
    let srtEntryCount: Int
    let srtBytes: Int
}

private final class FirstTextRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var firstTextTime: TimeInterval?

    func record(_ progress: TranscribeProgress) {
        guard (progress.completedWordCount ?? 0) > 0 else { return }
        lock.lock()
        if firstTextTime == nil {
            firstTextTime = Date.timeIntervalSinceReferenceDate
        }
        lock.unlock()
    }

    var value: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        return firstTextTime
    }
}

/// Local-only compatibility harness. It runs only when explicit media and output
/// paths are supplied, and writes hashes plus timing data instead of transcript text.
@Test func whisperCompatibilityBenchmark() async throws {
    let environment = ProcessInfo.processInfo.environment
    guard let audioPath = environment["REDACT_WHISPER_BENCHMARK_MEDIA"],
          let outputPath = environment["REDACT_WHISPER_BENCHMARK_OUTPUT"] else {
        return
    }

    let model = environment["REDACT_WHISPER_BENCHMARK_MODEL"] ?? "openai_whisper-tiny"
    let engineLabel = environment["REDACT_WHISPER_ENGINE_LABEL"] ?? "unspecified"
    let firstTextRecorder = FirstTextRecorder()
    let start = Date.timeIntervalSinceReferenceDate
    let transcript = try await TranscriptionEngine().transcribe(
        audioPath: audioPath,
        model: model,
        onProgress: { firstTextRecorder.record($0) }
    )
    let end = Date.timeIntervalSinceReferenceDate
    let words = transcript.segments.flatMap(\.words)
    let project = ProjectDocument()
    project.setTranscript(transcript)
    let cleanupSuggestions = TranscriptCleanupAnalyzer.suggestions(for: project.allWords)
    let cleanupWordIDs = Set(cleanupSuggestions.flatMap(\.wordIDs))
    let changedWordIDs = project.deleteWords(cleanupWordIDs)
    #expect(changedWordIDs == cleanupWordIDs)

    let sourceTranscript = try #require(project.sourceTranscript)
    let projectFile = ProjectFile(
        media: ProjectMediaReference(
            displayName: "private-media.mp4",
            fingerprint: nil,
            relativePath: nil,
            bookmarkData: nil
        ),
        transcript: sourceTranscript,
        edits: project.editDecisionList,
        segmentStartWordIDs: project.segments.compactMap { $0.words.first?.id }
    )
    let projectData = try ProjectFileCodec.encode(projectFile)
    let decodedProject = try ProjectFileCodec.decode(projectData)
    #expect(decodedProject.transcript == projectFile.transcript)
    #expect(decodedProject.edits.deletedWordIDs == cleanupWordIDs)
    let renderPlan = try #require(project.renderPlan(policy: .mediaV1))
    let srt = generateSrt(
        transcript: sourceTranscript,
        edits: project.editDecisionList,
        renderPlan: renderPlan
    )
    #expect(!srt.isEmpty)

    let report = WhisperCompatibilityReport(
        engineLabel: engineLabel,
        model: model,
        detectedLanguage: transcript.language,
        mediaDuration: transcript.duration,
        segmentCount: transcript.segments.count,
        wordCount: words.count,
        firstTextMilliseconds: firstTextRecorder.value.map { ($0 - start) * 1_000 },
        totalMilliseconds: (end - start) * 1_000,
        transcriptHash: sha256(words.map(\.word).joined(separator: "\u{1f}")),
        words: words.map {
            WhisperWordMetric(
                textHash: sha256($0.word),
                start: $0.start,
                end: $0.end
            )
        },
        cleanupSuggestionCounts: Dictionary(
            grouping: cleanupSuggestions,
            by: { $0.kind.rawValue }
        ).mapValues(\.count),
        cleanupSuggestionCount: cleanupSuggestions.count,
        cleanupWordCount: cleanupWordIDs.count,
        cleanupRemovedDuration: cleanupSuggestions.reduce(0) { $0 + $1.removedDuration },
        projectRoundTripBytes: projectData.count,
        editedDuration: renderPlan.editedDuration,
        srtEntryCount: srt.split(separator: "\n").count { $0.contains(" --> ") },
        srtBytes: srt.utf8.count
    )

    let outputURL = URL(fileURLWithPath: outputPath)
    try FileManager.default.createDirectory(
        at: outputURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(report).write(to: outputURL, options: .atomic)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: outputURL.path
    )
}

private func sha256(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
}
