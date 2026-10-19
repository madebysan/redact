import CryptoKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.redact.app", category: "FFmpegInstall")

/// Where Redact keeps the FFmpeg it downloaded itself:
/// `~/Library/Application Support/Redact/ffmpeg/{ffmpeg,ffprobe,manifest.json}`.
enum ManagedFFmpegLocation {
    static let ffmpegToolName = "ffmpeg"
    static let ffprobeToolName = "ffprobe"
    static let manifestFileName = "manifest.json"

    static func directory(fileManager: FileManager = .default) -> URL? {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Redact", isDirectory: true)
            .appendingPathComponent("ffmpeg", isDirectory: true)
    }

    /// The record written by the last successful install, if any.
    static func installedManifest(in directory: URL? = directory()) -> ManagedFFmpegManifest? {
        guard let directory else { return nil }
        let manifestURL = directory.appendingPathComponent(manifestFileName)
        guard let data = try? Data(contentsOf: manifestURL) else { return nil }
        return try? ManagedFFmpegManifest.decoder.decode(ManagedFFmpegManifest.self, from: data)
    }
}

/// Written beside the installed executables so Settings can say what is there.
struct ManagedFFmpegManifest: Codable, Equatable, Sendable {
    struct Tool: Codable, Equatable, Sendable {
        let name: String
        let archiveSHA256: String
    }

    let version: String
    let sourceName: String
    let licenseName: String
    let installedAt: Date
    let tools: [Tool]

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

struct ManagedFFmpegInstallProgress: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case downloading(String)
        case verifying(String)
        case installing(String)
    }

    let phase: Phase
    let completedBytes: Int64
    let totalBytes: Int64

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(completedBytes) / Double(totalBytes))
    }

    var statusText: String {
        switch phase {
        case .downloading(let tool):
            return "Downloading \(tool)…"
        case .verifying(let tool):
            return "Verifying \(tool)…"
        case .installing(let tool):
            return "Installing \(tool)…"
        }
    }

    var detailText: String {
        "\(FFmpegDistribution.formatBytes(completedBytes)) of \(FFmpegDistribution.formatBytes(totalBytes))"
    }
}

struct ManagedFFmpegInstallation: Equatable, Sendable {
    let directory: URL
    let manifest: ManagedFFmpegManifest

    var ffmpegURL: URL {
        directory.appendingPathComponent(ManagedFFmpegLocation.ffmpegToolName)
    }

    var ffprobeURL: URL {
        directory.appendingPathComponent(ManagedFFmpegLocation.ffprobeToolName)
    }
}

enum ManagedFFmpegInstallError: LocalizedError, Equatable {
    case downloadFailed(tool: String, statusCode: Int)
    case checksumMismatch(tool: String)
    case extractionFailed(tool: String)
    case executableMissing(tool: String)
    case smokeTestFailed(tool: String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let tool, let statusCode):
            return "The \(tool) download failed (HTTP \(statusCode)). Check your connection and try again."
        case .checksumMismatch(let tool):
            return "The downloaded \(tool) did not match its published checksum, so Redact did not install it. Try again later."
        case .extractionFailed(let tool):
            return "Redact could not unpack the downloaded \(tool) archive."
        case .executableMissing(let tool):
            return "The downloaded archive did not contain \(tool)."
        case .smokeTestFailed(let tool):
            return "The downloaded \(tool) did not run on this Mac, so Redact did not install it."
        case .cancelled:
            return "FFmpeg install cancelled."
        }
    }
}

/// Downloads the pinned static FFmpeg build, verifies it, and installs it into
/// Application Support. Every step runs in a private staging workspace; the
/// final directory only changes after both tools downloaded, matched their
/// checksums, and ran.
final class ManagedFFmpegInstaller: @unchecked Sendable {
    let distribution: FFmpegDistribution
    let directory: URL
    private let session: URLSession

    init(
        distribution: FFmpegDistribution = .current,
        directory: URL,
        session: URLSession = .shared
    ) {
        self.distribution = distribution
        self.directory = directory
        self.session = session
    }

    func install(
        onProgress: (@Sendable (ManagedFFmpegInstallProgress) -> Void)? = nil
    ) async throws -> ManagedFFmpegInstallation {
        let fileManager = FileManager.default
        let stagingRoot = directory.deletingLastPathComponent()
            .appendingPathComponent("ffmpeg-install", isDirectory: true)
        try? TemporaryWorkspace.cleanupAbandoned(in: stagingRoot)
        let workspace = try TemporaryWorkspace.create(in: stagingRoot)
        defer { try? workspace.cleanup() }

        let totalBytes = distribution.totalArchiveByteCount
        var completedBefore: Int64 = 0
        var stagedExecutables: [(tool: String, url: URL)] = []

        do {
            for artifact in distribution.artifacts {
                let tool = artifact.tool
                let archiveURL = try workspace.fileURL(named: tool + ".zip")

                onProgress?(ManagedFFmpegInstallProgress(
                    phase: .downloading(tool),
                    completedBytes: completedBefore,
                    totalBytes: totalBytes
                ))
                logger.info("install: downloading \(tool, privacy: .public)")
                try await download(artifact, to: archiveURL) { bytes in
                    onProgress?(ManagedFFmpegInstallProgress(
                        phase: .downloading(tool),
                        completedBytes: completedBefore + bytes,
                        totalBytes: totalBytes
                    ))
                }
                completedBefore += artifact.archiveByteCount

                onProgress?(ManagedFFmpegInstallProgress(
                    phase: .verifying(tool),
                    completedBytes: completedBefore,
                    totalBytes: totalBytes
                ))
                try Self.verifySHA256(of: archiveURL, expectedHex: artifact.archiveSHA256, tool: tool)
                try Task.checkCancellation()

                onProgress?(ManagedFFmpegInstallProgress(
                    phase: .installing(tool),
                    completedBytes: completedBefore,
                    totalBytes: totalBytes
                ))
                let extractDirectory = try workspace.fileURL(named: tool + "-extracted")
                let executable = try Self.extractArchive(archiveURL, tool: tool, into: extractDirectory)
                try Self.prepareExecutable(at: executable)
                try Self.smokeTest(executable, tool: tool)
                stagedExecutables.append((tool, executable))
                try Task.checkCancellation()
            }
        } catch is CancellationError {
            throw ManagedFFmpegInstallError.cancelled
        } catch let error as URLError where error.code == .cancelled {
            throw ManagedFFmpegInstallError.cancelled
        }

        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o755]
        )
        for staged in stagedExecutables {
            let destination = directory.appendingPathComponent(staged.tool)
            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: staged.url,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: staged.url, to: destination)
            }
        }

        let manifest = ManagedFFmpegManifest(
            version: distribution.version,
            sourceName: distribution.sourceName,
            licenseName: distribution.licenseName,
            installedAt: Date(),
            tools: distribution.artifacts.map {
                ManagedFFmpegManifest.Tool(name: $0.tool, archiveSHA256: $0.archiveSHA256)
            }
        )
        let manifestData = try ManagedFFmpegManifest.encoder.encode(manifest)
        try manifestData.write(
            to: directory.appendingPathComponent(ManagedFFmpegLocation.manifestFileName),
            options: .atomic
        )
        logger.info("install: finished FFmpeg \(manifest.version, privacy: .public)")

        return ManagedFFmpegInstallation(directory: directory, manifest: manifest)
    }

    // MARK: - Steps

    private func download(
        _ artifact: FFmpegDistribution.Artifact,
        to destination: URL,
        onBytes: @Sendable (Int64) -> Void
    ) async throws {
        let (bytes, response) = try await session.bytes(from: artifact.downloadURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ManagedFFmpegInstallError.downloadFailed(
                tool: artifact.tool,
                statusCode: http.statusCode
            )
        }

        let fileManager = FileManager.default
        try? fileManager.removeItem(at: destination)
        guard fileManager.createFile(
            atPath: destination.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw ManagedFFmpegInstallError.extractionFailed(tool: artifact.tool)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        let chunkSize = 1 << 20
        var buffer = Data()
        buffer.reserveCapacity(chunkSize)
        var written: Int64 = 0

        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= chunkSize {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                onBytes(written)
                try Task.checkCancellation()
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            written += Int64(buffer.count)
        }
        onBytes(written)
    }

    /// Lowercase hex SHA-256 of a file, streamed so large archives never load into memory.
    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verifySHA256(of fileURL: URL, expectedHex: String, tool: String) throws {
        let actual = try sha256Hex(of: fileURL)
        guard actual == expectedHex.lowercased() else {
            logger.error("install: checksum mismatch for \(tool, privacy: .public)")
            try? FileManager.default.removeItem(at: fileURL)
            throw ManagedFFmpegInstallError.checksumMismatch(tool: tool)
        }
    }

    /// Unpacks the archive with the system `unzip` and returns the tool inside it.
    static func extractArchive(_ archiveURL: URL, tool: String, into directory: URL) throws -> URL {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", "-q", archiveURL.path, "-d", directory.path]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ManagedFFmpegInstallError.extractionFailed(tool: tool)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw ManagedFFmpegInstallError.extractionFailed(tool: tool)
        }

        let executable = directory.appendingPathComponent(tool)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: executable.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ManagedFFmpegInstallError.executableMissing(tool: tool)
        }
        return executable
    }

    /// Marks the verified file executable and clears quarantine on that file only.
    static func prepareExecutable(at url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        let result = removexattr(url.path, "com.apple.quarantine", XATTR_NOFOLLOW)
        if result != 0, errno != ENOATTR {
            logger.warning("install: could not clear quarantine (errno \(errno))")
        }
    }

    /// Runs `<tool> -version` and requires the expected banner.
    static func smokeTest(_ executable: URL, tool: String) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-version"]
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw ManagedFFmpegInstallError.smokeTestFailed(tool: tool)
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let banner = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0, banner.hasPrefix("\(tool) version") else {
            throw ManagedFFmpegInstallError.smokeTestFailed(tool: tool)
        }
    }
}
