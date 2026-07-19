import AVFoundation
import Foundation
import WhisperKit

final class TranscriptionCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

protocol TranscriptionBackend: Sendable {
    func transcribe(
        audioPath: String,
        cancellation: TranscriptionCancellation,
        onProgress: @escaping @Sendable (TranscribeProgress) -> Void
    ) async throws -> RawTranscript
}

protocol TranscriptionBackendFactory: Sendable {
    func makeBackend(model: String) async throws -> any TranscriptionBackend
}

private struct CompletedTranscriptBlock {
    let seek: Int
    let firstSegmentID: Int
    let text: String
    let wordCount: Int
}

final class CompletedTranscriptAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var blocks: [String: CompletedTranscriptBlock] = [:]

    func add(_ segments: [TranscriptionSegment]) -> (preview: String, wordCount: Int)? {
        let wordCount = segments.reduce(0) { partialCount, segment in
            partialCount + (segment.words?.count ?? 0)
        }
        let text = segments
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSegment = segments.min(by: { $0.seek < $1.seek }),
              wordCount > 0,
              !text.isEmpty else {
            return nil
        }

        lock.lock()
        defer { lock.unlock() }
        let key = "\(firstSegment.seek):\(firstSegment.id)"
        blocks[key] = CompletedTranscriptBlock(
            seek: firstSegment.seek,
            firstSegmentID: firstSegment.id,
            text: text,
            wordCount: wordCount
        )
        let orderedBlocks = blocks.values.sorted {
            if $0.seek == $1.seek {
                return $0.firstSegmentID < $1.firstSegmentID
            }
            return $0.seek < $1.seek
        }
        let completedWordCount = orderedBlocks.reduce(0) { $0 + $1.wordCount }
        let orderedText = orderedBlocks.map(\.text).joined(separator: " ")
        let preview = String(orderedText.prefix(4_000))
        return (preview, completedWordCount)
    }
}

struct WhisperKitTranscriptionFactory: TranscriptionBackendFactory, Sendable {
    func makeBackend(model: String) async throws -> any TranscriptionBackend {
        do {
            let configuration = WhisperKitConfig(
                model: model,
                verbose: false,
                prewarm: false,
                load: true,
                download: true
            )
            return WhisperKitTranscriptionBackend(
                whisperKit: try await WhisperKit(configuration)
            )
        } catch {
            throw WhisperError.modelLoadFailed(error.localizedDescription)
        }
    }
}

private final class WhisperKitTranscriptionBackend: TranscriptionBackend, @unchecked Sendable {
    private let whisperKit: WhisperKit

    init(whisperKit: WhisperKit) {
        self.whisperKit = whisperKit
    }

    func transcribe(
        audioPath: String,
        cancellation: TranscriptionCancellation,
        onProgress: @escaping @Sendable (TranscribeProgress) -> Void
    ) async throws -> RawTranscript {
        let asset = AVURLAsset(url: URL(fileURLWithPath: audioPath))
        let duration = try await asset.load(.duration).seconds
        let options = DecodingOptions(
            wordTimestamps: true,
            chunkingStrategy: .vad
        )
        let completedTranscript = CompletedTranscriptAccumulator()
        whisperKit.segmentDiscoveryCallback = { segments in
            guard let progress = completedTranscript.add(segments) else { return }
            onProgress(
                TranscribeProgress(
                    status: .transcribing,
                    message: "\(progress.wordCount) words ready",
                    completedTextPreview: progress.preview,
                    completedWordCount: progress.wordCount
                )
            )
        }
        defer { whisperKit.segmentDiscoveryCallback = nil }

        onProgress(TranscribeProgress(status: .transcribing, message: "Transcribing…"))
        let results = try await whisperKit.transcribe(
            audioPath: audioPath,
            decodeOptions: options,
            callback: { _ in !cancellation.isCancelled && !Task.isCancelled }
        )

        guard !cancellation.isCancelled, !Task.isCancelled else {
            throw WhisperError.cancelled
        }
        guard !results.isEmpty else {
            throw WhisperError.transcriptionFailed("No transcription results returned")
        }

        onProgress(TranscribeProgress(status: .complete, message: "Transcription complete"))
        return Self.map(results: results, duration: duration)
    }

    private static func map(
        results: [TranscriptionResult],
        duration: Double
    ) -> RawTranscript {
        var segmentID = 0
        var detectedLanguage = "en"
        let segments = results.flatMap { result -> [RawSegment] in
            detectedLanguage = result.language
            return result.segments.compactMap { segment in
                guard let timings = segment.words, !timings.isEmpty else { return nil }
                defer { segmentID += 1 }
                return RawSegment(
                    id: segmentID,
                    words: timings.map {
                        RawWord(
                            word: $0.word,
                            start: Double($0.start),
                            end: Double($0.end),
                            confidence: Double($0.probability)
                        )
                    }
                )
            }
        }
        return RawTranscript(
            segments: segments,
            language: detectedLanguage,
            duration: duration
        )
    }
}

actor TranscriptionEngine {
    private let factory: any TranscriptionBackendFactory
    private var loadedModel: String?
    private var backend: (any TranscriptionBackend)?
    private var activeCancellation: TranscriptionCancellation?

    init(factory: any TranscriptionBackendFactory = WhisperKitTranscriptionFactory()) {
        self.factory = factory
    }

    func transcribe(
        audioPath: String,
        model: String? = nil,
        onProgress: @escaping @Sendable (TranscribeProgress) -> Void
    ) async throws -> RawTranscript {
        guard activeCancellation == nil else {
            throw WhisperError.transcriptionInProgress
        }

        let requestedModel = model ?? Settings.shared.whisperModel
        let cancellation = TranscriptionCancellation()
        activeCancellation = cancellation
        defer {
            if activeCancellation === cancellation {
                activeCancellation = nil
            }
        }

        if backend == nil || loadedModel != requestedModel {
            onProgress(TranscribeProgress(status: .loadingModel, message: "Loading model…"))
            backend = try await factory.makeBackend(model: requestedModel)
            loadedModel = requestedModel
        }

        guard !cancellation.isCancelled else {
            throw WhisperError.cancelled
        }
        guard let backend else {
            throw WhisperError.modelLoadFailed("Model backend was not created")
        }

        return try await withTaskCancellationHandler {
            try await backend.transcribe(
                audioPath: audioPath,
                cancellation: cancellation,
                onProgress: onProgress
            )
        } onCancel: {
            cancellation.cancel()
        }
    }

    func cancel() {
        activeCancellation?.cancel()
    }
}

enum WhisperError: LocalizedError, Equatable {
    static func == (lhs: WhisperError, rhs: WhisperError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled): return true
        case (.invalidOutput, .invalidOutput): return true
        case (.transcriptionInProgress, .transcriptionInProgress): return true
        case (.modelLoadFailed, .modelLoadFailed): return true
        case (.modelDownloadFailed, .modelDownloadFailed): return true
        default: return false
        }
    }

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    case modelLoadFailed(String)
    case modelDownloadFailed(String)
    case transcriptionFailed(String)
    case transcriptionInProgress
    case cancelled
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let message):
            return "Failed to load transcription model: \(message)"
        case .modelDownloadFailed(let message):
            return "Failed to download transcription model: \(message)"
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .transcriptionInProgress:
            return "A transcription is already running"
        case .cancelled:
            return "Transcription cancelled"
        case .invalidOutput:
            return "Transcription produced invalid output"
        }
    }
}
