import Foundation
import Testing
@testable import Redact

private func makeLookupFixture() throws -> (root: URL, managed: URL, homebrew: URL, path: URL) {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-path-lookup-" + UUID().uuidString, isDirectory: true)
    let managed = root.appendingPathComponent("managed", isDirectory: true)
    let homebrew = root.appendingPathComponent("homebrew", isDirectory: true)
    let path = root.appendingPathComponent("path", isDirectory: true)
    for directory in [managed, homebrew, path] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return (root, managed, homebrew, path)
}

private func installFakeTool(named name: String, in directory: URL, executable: Bool = true) throws -> URL {
    let url = directory.appendingPathComponent(name)
    try Data("#!/bin/sh\necho \(name) version 0.0-fixture\n".utf8).write(to: url)
    try FileManager.default.setAttributes(
        [.posixPermissions: executable ? 0o755 : 0o644],
        ofItemAtPath: url.path
    )
    return url
}

@Test func lookupPrefersManagedCopyOverHomebrewAndPath() throws {
    let fixture = try makeLookupFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let managedTool = try installFakeTool(named: "ffmpeg", in: fixture.managed)
    _ = try installFakeTool(named: "ffmpeg", in: fixture.homebrew)
    let pathTool = try installFakeTool(named: "ffmpeg", in: fixture.path)

    let location = PathUtilities.locate(
        "ffmpeg",
        managedDirectory: fixture.managed,
        systemDirectories: [fixture.homebrew.path],
        pathLookup: { _ in pathTool.path }
    )

    #expect(location == PathUtilities.ToolLocation(path: managedTool.path, source: .managed))
}

@Test func lookupFallsBackToHomebrewWhenNoManagedCopyExists() throws {
    let fixture = try makeLookupFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let homebrewTool = try installFakeTool(named: "ffprobe", in: fixture.homebrew)
    let pathTool = try installFakeTool(named: "ffprobe", in: fixture.path)

    let location = PathUtilities.locate(
        "ffprobe",
        managedDirectory: fixture.managed,
        systemDirectories: [fixture.homebrew.path],
        pathLookup: { _ in pathTool.path }
    )

    #expect(location == PathUtilities.ToolLocation(path: homebrewTool.path, source: .homebrew))
}

@Test func lookupUsesPathOnlyAsLastResortAndIgnoresNonExecutables() throws {
    let fixture = try makeLookupFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    _ = try installFakeTool(named: "ffmpeg", in: fixture.managed, executable: false)
    let pathTool = try installFakeTool(named: "ffmpeg", in: fixture.path)

    let location = PathUtilities.locate(
        "ffmpeg",
        managedDirectory: fixture.managed,
        systemDirectories: [fixture.homebrew.path],
        pathLookup: { _ in pathTool.path }
    )

    #expect(location == PathUtilities.ToolLocation(path: pathTool.path, source: .path))
}

@Test func lookupReturnsNilWhenNothingIsInstalled() throws {
    let fixture = try makeLookupFixture()
    defer { try? FileManager.default.removeItem(at: fixture.root) }

    let location = PathUtilities.locate(
        "ffmpeg",
        managedDirectory: fixture.managed,
        systemDirectories: [fixture.homebrew.path],
        pathLookup: { _ in nil }
    )

    #expect(location == nil)
}

@Test func installationStatusDescribesEachSource() {
    let managed = FFmpegInstallationStatus(
        ffmpeg: PathUtilities.ToolLocation(path: "/managed/ffmpeg", source: .managed),
        ffprobe: PathUtilities.ToolLocation(path: "/managed/ffprobe", source: .managed),
        managedVersion: "9.0.2"
    )
    #expect(managed.isAvailable)
    #expect(managed.usesManagedCopy)
    #expect(managed.summary == "Using Redact's copy (FFmpeg 9.0.2)")

    let homebrew = FFmpegInstallationStatus(
        ffmpeg: PathUtilities.ToolLocation(path: "/opt/homebrew/bin/ffmpeg", source: .homebrew),
        ffprobe: PathUtilities.ToolLocation(path: "/opt/homebrew/bin/ffprobe", source: .homebrew),
        managedVersion: nil
    )
    #expect(!homebrew.usesManagedCopy)
    #expect(homebrew.summary == "Using Homebrew's FFmpeg at /opt/homebrew/bin/ffmpeg")

    let missingProbe = FFmpegInstallationStatus(
        ffmpeg: PathUtilities.ToolLocation(path: "/usr/bin/ffmpeg", source: .path),
        ffprobe: nil,
        managedVersion: nil
    )
    #expect(!missingProbe.isAvailable)
    #expect(missingProbe.summary == "Not installed")
}

@Test func distributionPinsBothToolsWithChecksums() {
    let distribution = FFmpegDistribution.current
    let tools = distribution.artifacts.map(\.tool)

    #expect(tools == ["ffmpeg", "ffprobe"])
    for artifact in distribution.artifacts {
        #expect(artifact.archiveSHA256.count == 64)
        #expect(artifact.archiveSHA256 == artifact.archiveSHA256.lowercased())
        #expect(artifact.archiveByteCount > 0)
        #expect(artifact.downloadURL.scheme == "https")
    }
    #expect(distribution.totalArchiveByteCount > 0)
    #expect(!distribution.formattedDownloadSize.isEmpty)
}
