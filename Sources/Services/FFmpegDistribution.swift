import Foundation

/// The static FFmpeg build Redact offers to download when no FFmpeg is installed.
///
/// Every value here is pinned: the app only accepts an archive whose SHA-256
/// matches, so a changed or tampered download is rejected rather than run.
/// Update the version, URLs, and checksums together, and keep
/// THIRD_PARTY_NOTICES.md in step with the source and license named here.
struct FFmpegDistribution: Equatable, Sendable {
    struct Artifact: Equatable, Sendable {
        /// `ffmpeg` or `ffprobe`; also the file name inside the archive.
        let tool: String
        let downloadURL: URL
        /// Lowercase hex SHA-256 of the archive as published beside it.
        let archiveSHA256: String
        let archiveByteCount: Int64
    }

    let version: String
    let sourceName: String
    let sourceURL: URL
    let licenseName: String
    let artifacts: [Artifact]

    var totalArchiveByteCount: Int64 {
        artifacts.reduce(0) { $0 + $1.archiveByteCount }
    }

    /// Download size as shown to people, for example "57 MB".
    var formattedDownloadSize: String {
        Self.formatBytes(totalArchiveByteCount)
    }

    static func formatBytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: count)
    }

    /// FFmpeg 9.0.2, Apple Silicon, static, from Martin Riedl's build server.
    ///
    /// Signed with Martin Riedl's Developer ID and built with `--enable-gpl
    /// --enable-version3`, so the binaries are GPL-3.0. Redact runs them as
    /// separate processes and never ships them inside the app bundle; the
    /// download happens only after the person accepts the install sheet.
    static let current = FFmpegDistribution(
        version: "9.0.2",
        sourceName: "Martin Riedl's FFmpeg build server",
        sourceURL: URL(string: "https://ffmpeg.martin-riedl.de/")!,
        licenseName: "GPL-3.0",
        artifacts: [
            Artifact(
                tool: "ffmpeg",
                downloadURL: URL(
                    string: "https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffmpeg.zip"
                )!,
                archiveSHA256: "c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924",
                archiveByteCount: 28_395_699
            ),
            Artifact(
                tool: "ffprobe",
                downloadURL: URL(
                    string: "https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2/ffprobe.zip"
                )!,
                archiveSHA256: "fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6",
                archiveByteCount: 28_317_701
            ),
        ]
    )
}
