import Foundation

/// Which companion files the export sheet asked for beside the media.
struct ExportSidecarOptions: Equatable, Sendable {
    var subtitles = false
    var edl = false
    var fcpxml = false

    static let none = ExportSidecarOptions()

    var isEmpty: Bool { !subtitles && !edl && !fcpxml }
}

/// A sidecar ready to be written after media export succeeds.
struct ExportSidecarFile: Equatable, Sendable {
    let url: URL
    let contents: String
    /// Short human name used in error messages, such as "subtitles".
    let label: String
}
