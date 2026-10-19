import Foundation

/// Finds the FFmpeg and FFprobe executables Redact runs.
///
/// Lookup order:
/// 1. the copy Redact downloaded itself into Application Support (see `ManagedFFmpegInstaller`),
/// 2. Homebrew's bin directories,
/// 3. the user's PATH, via `which`.
///
/// A Mac that already has Homebrew's FFmpeg keeps using it until the managed copy is installed.
enum PathUtilities {
    enum ToolSource: Equatable, Sendable {
        case managed
        case homebrew
        case path
    }

    struct ToolLocation: Equatable, Sendable {
        let path: String
        let source: ToolSource
    }

    /// Where Redact looks before falling back to `which`.
    static let homebrewDirectories = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    /// Developer override. Set it to `1` to ignore Homebrew and PATH so the
    /// in-app install can be exercised on a Mac that already has FFmpeg.
    static let ignoreSystemToolsEnvironmentKey = "REDACT_IGNORE_SYSTEM_FFMPEG"

    static var ignoresSystemTools: Bool {
        ProcessInfo.processInfo.environment[ignoreSystemToolsEnvironmentKey] == "1"
    }

    /// Find the FFmpeg executable.
    static func findFFmpeg() -> String? {
        locate(ManagedFFmpegLocation.ffmpegToolName)?.path
    }

    /// Find the FFprobe executable.
    static func findFFprobe() -> String? {
        locate(ManagedFFmpegLocation.ffprobeToolName)?.path
    }

    /// Both tools must be present for import and export to work.
    static var hasFFmpegAndFFprobe: Bool {
        findFFmpeg() != nil && findFFprobe() != nil
    }

    static func locate(_ tool: String) -> ToolLocation? {
        if ignoresSystemTools {
            return locate(
                tool,
                managedDirectory: ManagedFFmpegLocation.directory(),
                systemDirectories: [],
                pathLookup: { _ in nil }
            )
        }
        return locate(
            tool,
            managedDirectory: ManagedFFmpegLocation.directory(),
            systemDirectories: homebrewDirectories,
            pathLookup: findInPath
        )
    }

    /// Testable lookup with every search location injected.
    static func locate(
        _ tool: String,
        managedDirectory: URL?,
        systemDirectories: [String],
        fileManager: FileManager = .default,
        pathLookup: (String) -> String?
    ) -> ToolLocation? {
        if let managedDirectory {
            let managedPath = managedDirectory.appendingPathComponent(tool).path
            if fileManager.isExecutableFile(atPath: managedPath) {
                return ToolLocation(path: managedPath, source: .managed)
            }
        }

        for directory in systemDirectories {
            let candidate = (directory as NSString).appendingPathComponent(tool)
            if fileManager.isExecutableFile(atPath: candidate) {
                return ToolLocation(path: candidate, source: .homebrew)
            }
        }

        if let found = pathLookup(tool), !found.isEmpty,
           fileManager.isExecutableFile(atPath: found) {
            return ToolLocation(path: found, source: .path)
        }

        return nil
    }

    /// Use `which` to find a binary in PATH.
    static func findInPath(_ binary: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Silently fail — binary not found
        }

        return nil
    }
}

/// What Settings shows about the FFmpeg Redact is using right now.
struct FFmpegInstallationStatus: Equatable, Sendable {
    let ffmpeg: PathUtilities.ToolLocation?
    let ffprobe: PathUtilities.ToolLocation?
    let managedVersion: String?

    static func current() -> FFmpegInstallationStatus {
        FFmpegInstallationStatus(
            ffmpeg: PathUtilities.locate(ManagedFFmpegLocation.ffmpegToolName),
            ffprobe: PathUtilities.locate(ManagedFFmpegLocation.ffprobeToolName),
            managedVersion: ManagedFFmpegLocation.installedManifest()?.version
        )
    }

    var isAvailable: Bool {
        ffmpeg != nil && ffprobe != nil
    }

    var usesManagedCopy: Bool {
        ffmpeg?.source == .managed && ffprobe?.source == .managed
    }

    var summary: String {
        guard let ffmpeg, ffprobe != nil else {
            return "Not installed"
        }
        switch ffmpeg.source {
        case .managed:
            if let managedVersion {
                return "Using Redact's copy (FFmpeg \(managedVersion))"
            }
            return "Using Redact's copy"
        case .homebrew:
            return "Using Homebrew's FFmpeg at \(ffmpeg.path)"
        case .path:
            return "Using FFmpeg from your PATH at \(ffmpeg.path)"
        }
    }
}
