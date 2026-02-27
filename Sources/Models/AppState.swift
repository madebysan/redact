import Foundation

/// The current state of the application.
enum AppState: String, Codable {
    case empty
    case importing
    case transcribing
    case editing
    case exporting
}

/// Progress information during transcription.
struct TranscribeProgress {
    enum Status {
        case loadingModel
        case transcribing
        case refining
        case complete
        case error
    }

    var status: Status
    var progress: Int?
    var message: String?
}
