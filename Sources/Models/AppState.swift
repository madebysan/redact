import Foundation

/// The current state of the application.
enum AppState: String, Codable {
    case empty
    case importing
    case transcribing
    case editing
    case missingMedia
    case exporting
}

/// Progress information during transcription.
/// Indeterminate by design — Whisper's window count isn't monotonic,
/// so a numeric percent lies more than it informs.
struct TranscribeProgress: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case loadingModel
        case transcribing
        case complete
        case error
    }

    var status: Status
    var message: String?
    var completedTextPreview: String? = nil
    var completedWordCount: Int? = nil
}
