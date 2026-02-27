import Foundation
import WhisperKit
import AVFoundation

/// Native WhisperKit transcription service.
/// Uses CoreML + Metal for on-device speech recognition — no Python required.
class WhisperService {
    private var isCancelled = false

    /// Transcribe an audio file using WhisperKit.
    func transcribe(
        audioPath: String,
        model: String? = nil,
        onProgress: @escaping (TranscribeProgress) -> Void
    ) async throws -> RawTranscript {
        isCancelled = false
        let modelVariant = model ?? Settings.shared.whisperModel

        // Get audio duration for progress estimation
        let audioURL = URL(fileURLWithPath: audioPath)
        let asset = AVURLAsset(url: audioURL)
        let audioDuration = try await asset.load(.duration).seconds

        // Initialize WhisperKit — auto-downloads model on first use
        onProgress(TranscribeProgress(status: .loadingModel, message: "Loading model…"))

        let whisperKit: WhisperKit
        do {
            let config = WhisperKitConfig(
                model: modelVariant,
                verbose: false,
                prewarm: false,
                load: true,
                download: true
            )
            whisperKit = try await WhisperKit(config)
        } catch {
            throw WhisperError.modelLoadFailed(error.localizedDescription)
        }

        guard !isCancelled else { throw WhisperError.cancelled }

        // Configure decoding with word-level timestamps
        let options = DecodingOptions(
            wordTimestamps: true,
            chunkingStrategy: .vad
        )

        onProgress(TranscribeProgress(status: .transcribing, progress: 0, message: "Transcribing…"))

        // Transcribe with progress callback
        let totalWindows = max(1, Int(ceil(audioDuration / 30.0)))

        let results = try await whisperKit.transcribe(
            audioPath: audioPath,
            decodeOptions: options,
            callback: { [weak self] progress in
                guard let self else { return false }
                if self.isCancelled { return false }

                // Estimate percentage from window index
                let percent = min(99, Int(Double(progress.windowId + 1) / Double(totalWindows) * 100))
                onProgress(TranscribeProgress(
                    status: .transcribing,
                    progress: percent,
                    message: "Transcribing… \(percent)%"
                ))
                return true
            }
        )

        guard !isCancelled else { throw WhisperError.cancelled }

        guard !results.isEmpty else {
            throw WhisperError.transcriptionFailed("No transcription results returned")
        }

        onProgress(TranscribeProgress(status: .complete, message: "Transcription complete"))

        // Map WhisperKit results → RawTranscript
        return mapToRawTranscript(results: results, duration: audioDuration)
    }

    /// Cancel the running transcription.
    func cancel() {
        isCancelled = true
    }

    // MARK: - Result Mapping

    /// Convert WhisperKit TranscriptionResult array → RawTranscript.
    private func mapToRawTranscript(results: [TranscriptionResult], duration: Double) -> RawTranscript {
        var segmentId = 0
        var detectedLanguage = "en"

        let segments: [RawSegment] = results.flatMap { result -> [RawSegment] in
            detectedLanguage = result.language

            return result.segments.compactMap { segment -> RawSegment? in
                guard let wordTimings = segment.words, !wordTimings.isEmpty else { return nil }

                let words: [RawWord] = wordTimings.map { timing in
                    RawWord(
                        word: timing.word,
                        start: Double(timing.start),
                        end: Double(timing.end),
                        confidence: Double(timing.probability)
                    )
                }

                let seg = RawSegment(id: segmentId, words: words)
                segmentId += 1
                return seg
            }
        }

        return RawTranscript(segments: segments, language: detectedLanguage, duration: duration)
    }
}

enum WhisperError: LocalizedError, Equatable {
    static func == (lhs: WhisperError, rhs: WhisperError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled): return true
        case (.invalidOutput, .invalidOutput): return true
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
    case cancelled
    case invalidOutput

    var errorDescription: String? {
        switch self {
        case .modelLoadFailed(let msg):
            return "Failed to load transcription model: \(msg)"
        case .modelDownloadFailed(let msg):
            return "Failed to download transcription model: \(msg)"
        case .transcriptionFailed(let msg):
            return "Transcription failed: \(msg)"
        case .cancelled:
            return "Transcription cancelled"
        case .invalidOutput:
            return "Transcription produced invalid output"
        }
    }
}
