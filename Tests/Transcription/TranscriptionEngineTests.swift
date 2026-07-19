import Foundation
import Testing
import WhisperKit
@testable import Redact

private actor StubTranscriptionFactory: TranscriptionBackendFactory {
    private(set) var requestedModels: [String] = []

    func makeBackend(model: String) async throws -> any TranscriptionBackend {
        requestedModels.append(model)
        return StubTranscriptionBackend(model: model)
    }
}

private struct StubTranscriptionBackend: TranscriptionBackend {
    let model: String

    func transcribe(
        audioPath: String,
        cancellation: TranscriptionCancellation,
        onProgress: @escaping @Sendable (TranscribeProgress) -> Void
    ) async throws -> RawTranscript {
        if cancellation.isCancelled {
            throw Redact.WhisperError.cancelled
        }
        onProgress(TranscribeProgress(status: .complete, message: model))
        return RawTranscript(
            segments: [],
            language: "en",
            duration: 1
        )
    }
}

private struct WaitingTranscriptionFactory: TranscriptionBackendFactory {
    func makeBackend(model: String) async throws -> any TranscriptionBackend {
        WaitingTranscriptionBackend()
    }
}

private struct WaitingTranscriptionBackend: TranscriptionBackend {
    func transcribe(
        audioPath: String,
        cancellation: TranscriptionCancellation,
        onProgress: @escaping @Sendable (TranscribeProgress) -> Void
    ) async throws -> RawTranscript {
        while !cancellation.isCancelled {
            await Task.yield()
        }
        throw Redact.WhisperError.cancelled
    }
}

private final class TranscriptionProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedProgress: [TranscribeProgress] = []

    func append(_ progress: TranscribeProgress) {
        lock.lock()
        recordedProgress.append(progress)
        lock.unlock()
    }

    var values: [TranscribeProgress] {
        lock.lock()
        defer { lock.unlock() }
        return recordedProgress
    }
}

private struct PartialReportingFactory: TranscriptionBackendFactory {
    func makeBackend(model: String) async throws -> any TranscriptionBackend {
        PartialReportingBackend()
    }
}

private struct PartialReportingBackend: TranscriptionBackend {
    func transcribe(
        audioPath: String,
        cancellation: TranscriptionCancellation,
        onProgress: @escaping @Sendable (TranscribeProgress) -> Void
    ) async throws -> RawTranscript {
        onProgress(
            TranscribeProgress(
                status: .transcribing,
                message: "2 words ready",
                completedTextPreview: "Hello world.",
                completedWordCount: 2
            )
        )
        return RawTranscript(segments: [], language: "en", duration: 1)
    }
}

@Test func transcriptionEngineReusesTheLoadedModelAcrossImports() async throws {
    let factory = StubTranscriptionFactory()
    let engine = TranscriptionEngine(factory: factory)

    _ = try await engine.transcribe(
        audioPath: "/first.wav",
        model: "small",
        onProgress: { _ in }
    )
    _ = try await engine.transcribe(
        audioPath: "/second.wav",
        model: "small",
        onProgress: { _ in }
    )

    #expect(await factory.requestedModels == ["small"])
}

@Test func transcriptionEngineReloadsOnlyWhenTheModelChanges() async throws {
    let factory = StubTranscriptionFactory()
    let engine = TranscriptionEngine(factory: factory)

    _ = try await engine.transcribe(
        audioPath: "/first.wav",
        model: "small",
        onProgress: { _ in }
    )
    _ = try await engine.transcribe(
        audioPath: "/second.wav",
        model: "large-v3-turbo",
        onProgress: { _ in }
    )

    #expect(await factory.requestedModels == ["small", "large-v3-turbo"])
}

@Test func transcriptionEngineCancellationReachesTheActiveBackend() async {
    let engine = TranscriptionEngine(factory: WaitingTranscriptionFactory())
    let transcription = Task {
        try await engine.transcribe(
            audioPath: "/waiting.wav",
            model: "small",
            onProgress: { _ in }
        )
    }

    await Task.yield()
    await engine.cancel()

    do {
        _ = try await transcription.value
        Issue.record("Expected transcription cancellation")
    } catch let error as Redact.WhisperError {
        #expect(error.isCancelled)
    } catch {
        Issue.record("Unexpected cancellation error")
    }
}

@Test func transcriptionEnginePublishesStablePartialTranscriptBlocks() async throws {
    let recorder = TranscriptionProgressRecorder()
    let engine = TranscriptionEngine(factory: PartialReportingFactory())

    _ = try await engine.transcribe(
        audioPath: "/partial.wav",
        model: "small",
        onProgress: { recorder.append($0) }
    )

    #expect(
        recorder.values.contains(
            TranscribeProgress(
                status: .transcribing,
                message: "2 words ready",
                completedTextPreview: "Hello world.",
                completedWordCount: 2
            )
        )
    )
}

@Test func completedTranscriptPreviewSortsParallelChunksBySourceOffset() throws {
    let accumulator = CompletedTranscriptAccumulator()
    let later = TranscriptionSegment(
        id: 1,
        seek: 2_000,
        text: "Later.",
        words: [
            WordTiming(word: "Later.", tokens: [], start: 2, end: 3, probability: 1),
        ]
    )
    let earlier = TranscriptionSegment(
        id: 0,
        seek: 0,
        text: "Earlier.",
        words: [
            WordTiming(word: "Earlier.", tokens: [], start: 0, end: 1, probability: 1),
        ]
    )

    _ = accumulator.add([later])
    let progress = try #require(accumulator.add([earlier]))

    #expect(progress.preview == "Earlier. Later.")
    #expect(progress.wordCount == 2)
}
