import Foundation
import Testing
@testable import Redact

/// Builds a zip archive containing a shell script that answers `-version`
/// like the real tool does, so the installer can be exercised offline.
private struct InstallerFixture {
    let root: URL
    let installDirectory: URL
    let distribution: FFmpegDistribution

    static func make(
        tools: [String] = ["ffmpeg", "ffprobe"],
        corruptChecksumFor corrupted: String? = nil,
        brokenToolNamed broken: String? = nil
    ) throws -> InstallerFixture {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("redact-ffmpeg-installer-" + UUID().uuidString, isDirectory: true)
        let sources = root.appendingPathComponent("sources", isDirectory: true)
        try fileManager.createDirectory(at: sources, withIntermediateDirectories: true)

        var artifacts: [FFmpegDistribution.Artifact] = []
        for tool in tools {
            let script = sources.appendingPathComponent(tool)
            let banner = tool == broken ? "not the tool you wanted" : "\(tool) version 0.0-fixture"
            try Data("#!/bin/sh\necho '\(banner)'\n".utf8).write(to: script)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

            let archive = sources.appendingPathComponent(tool + ".zip")
            let zip = Process()
            zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
            zip.currentDirectoryURL = sources
            zip.arguments = ["-q", "-j", archive.path, script.path]
            zip.standardOutput = FileHandle.nullDevice
            zip.standardError = FileHandle.nullDevice
            try zip.run()
            zip.waitUntilExit()
            guard zip.terminationStatus == 0 else {
                throw ManagedFFmpegInstallError.extractionFailed(tool: tool)
            }

            var checksum = try ManagedFFmpegInstaller.sha256Hex(of: archive)
            if tool == corrupted {
                checksum = String(repeating: "0", count: 64)
            }
            let size = try fileManager.attributesOfItem(atPath: archive.path)[.size] as? Int64 ?? 0
            artifacts.append(FFmpegDistribution.Artifact(
                tool: tool,
                downloadURL: archive,
                archiveSHA256: checksum,
                archiveByteCount: size
            ))
        }

        let distribution = FFmpegDistribution(
            version: "0.0-fixture",
            sourceName: "Local fixture",
            sourceURL: root,
            licenseName: "Test",
            artifacts: artifacts
        )
        let installDirectory = root
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("Redact", isDirectory: true)
            .appendingPathComponent("ffmpeg", isDirectory: true)
        return InstallerFixture(root: root, installDirectory: installDirectory, distribution: distribution)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

@Test func sha256HexMatchesTheKnownVectorForABC() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-sha-" + UUID().uuidString)
    try Data("abc".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    let digest = try ManagedFFmpegInstaller.sha256Hex(of: url)

    #expect(digest == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
}

@Test func checksumVerificationRejectsAMismatchAndDeletesTheArchive() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-sha-mismatch-" + UUID().uuidString)
    try Data("abc".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    #expect(throws: ManagedFFmpegInstallError.checksumMismatch(tool: "ffmpeg")) {
        try ManagedFFmpegInstaller.verifySHA256(
            of: url,
            expectedHex: String(repeating: "f", count: 64),
            tool: "ffmpeg"
        )
    }
    #expect(!FileManager.default.fileExists(atPath: url.path))
}

@Test func checksumVerificationAcceptsUppercaseHex() throws {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-sha-upper-" + UUID().uuidString)
    try Data("abc".utf8).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }

    try ManagedFFmpegInstaller.verifySHA256(
        of: url,
        expectedHex: "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
        tool: "ffmpeg"
    )
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@Test func installerDownloadsVerifiesAndInstallsBothToolsFromLocalArchives() async throws {
    let fixture = try InstallerFixture.make()
    defer { fixture.cleanup() }
    let installer = ManagedFFmpegInstaller(
        distribution: fixture.distribution,
        directory: fixture.installDirectory
    )
    let progressBox = ProgressBox()

    let installation = try await installer.install { progress in
        progressBox.append(progress)
    }

    let fileManager = FileManager.default
    #expect(fileManager.isExecutableFile(atPath: installation.ffmpegURL.path))
    #expect(fileManager.isExecutableFile(atPath: installation.ffprobeURL.path))
    #expect(installation.manifest.version == "0.0-fixture")
    #expect(installation.manifest.tools.map(\.name) == ["ffmpeg", "ffprobe"])

    let manifest = try #require(ManagedFFmpegLocation.installedManifest(in: fixture.installDirectory))
    #expect(manifest.version == installation.manifest.version)
    #expect(manifest.tools == installation.manifest.tools)
    #expect(manifest.sourceName == "Local fixture")

    let located = PathUtilities.locate(
        "ffmpeg",
        managedDirectory: fixture.installDirectory,
        systemDirectories: [],
        pathLookup: { _ in nil }
    )
    #expect(located?.source == .managed)

    let phases = progressBox.snapshot().map(\.phase)
    #expect(phases.contains(.downloading("ffmpeg")))
    #expect(phases.contains(.verifying("ffmpeg")))
    #expect(phases.contains(.installing("ffprobe")))
    #expect(progressBox.snapshot().last?.fraction == 1)

    let stagingRoot = fixture.installDirectory.deletingLastPathComponent()
        .appendingPathComponent("ffmpeg-install", isDirectory: true)
    let leftovers = (try? fileManager.contentsOfDirectory(atPath: stagingRoot.path)) ?? []
    #expect(leftovers.isEmpty)
}

@Test func installerRefusesAnArchiveWhoseChecksumDoesNotMatch() async throws {
    let fixture = try InstallerFixture.make(corruptChecksumFor: "ffprobe")
    defer { fixture.cleanup() }
    let installer = ManagedFFmpegInstaller(
        distribution: fixture.distribution,
        directory: fixture.installDirectory
    )

    await #expect(throws: ManagedFFmpegInstallError.checksumMismatch(tool: "ffprobe")) {
        _ = try await installer.install()
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.installDirectory.path))
}

@Test func installerRefusesAToolThatDoesNotRunAsExpected() async throws {
    let fixture = try InstallerFixture.make(brokenToolNamed: "ffmpeg")
    defer { fixture.cleanup() }
    let installer = ManagedFFmpegInstaller(
        distribution: fixture.distribution,
        directory: fixture.installDirectory
    )

    await #expect(throws: ManagedFFmpegInstallError.smokeTestFailed(tool: "ffmpeg")) {
        _ = try await installer.install()
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.installDirectory.path))
}

@Test func reinstallReplacesAnExistingManagedCopy() async throws {
    let fixture = try InstallerFixture.make()
    defer { fixture.cleanup() }
    try FileManager.default.createDirectory(at: fixture.installDirectory, withIntermediateDirectories: true)
    let stale = fixture.installDirectory.appendingPathComponent("ffmpeg")
    try Data("stale".utf8).write(to: stale)

    let installer = ManagedFFmpegInstaller(
        distribution: fixture.distribution,
        directory: fixture.installDirectory
    )
    _ = try await installer.install()

    let contents = try String(contentsOf: stale, encoding: .utf8)
    #expect(contents.contains("ffmpeg version 0.0-fixture"))
}

/// Opt-in: downloads the real pinned build and runs it from a private
/// directory, the way the app does. Set `REDACT_RUN_FFMPEG_INSTALL_INTEGRATION=1`.
@Test func realDistributionInstallsAndEncodesWithManagedFFmpeg() async throws {
    guard ProcessInfo.processInfo.environment["REDACT_RUN_FFMPEG_INSTALL_INTEGRATION"] == "1" else {
        return
    }
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-ffmpeg-real-install-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("Redact/ffmpeg", isDirectory: true)

    let installer = ManagedFFmpegInstaller(distribution: .current, directory: directory)
    let installation = try await installer.install()

    let output = root.appendingPathComponent("probe.mp4")
    let encode = Process()
    encode.executableURL = installation.ffmpegURL
    encode.arguments = [
        "-nostdin", "-hide_banner", "-loglevel", "error",
        "-f", "lavfi", "-i", "color=c=black:s=64x64:d=1",
        "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
        "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", "-y", output.path,
    ]
    encode.standardOutput = FileHandle.nullDevice
    encode.standardError = FileHandle.nullDevice
    try encode.run()
    encode.waitUntilExit()
    #expect(encode.terminationStatus == 0)

    let probe = Process()
    probe.executableURL = installation.ffprobeURL
    probe.arguments = ["-v", "quiet", "-print_format", "json", "-show_format", "-show_streams", output.path]
    let probeOutput = Pipe()
    probe.standardOutput = probeOutput
    probe.standardError = FileHandle.nullDevice
    try probe.run()
    let probeData = probeOutput.fileHandleForReading.readDataToEndOfFile()
    probe.waitUntilExit()
    #expect(probe.terminationStatus == 0)
    let info = try MediaInfo.decodeFFprobeJSON(probeData)
    #expect(info.hasAudio)
}

private final class ProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [ManagedFFmpegInstallProgress] = []

    func append(_ progress: ManagedFFmpegInstallProgress) {
        lock.lock()
        values.append(progress)
        lock.unlock()
    }

    func snapshot() -> [ManagedFFmpegInstallProgress] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}
