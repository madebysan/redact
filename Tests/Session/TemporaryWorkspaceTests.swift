import Foundation
import Testing
@testable import Redact

@Test func temporaryWorkspaceUsesAUniquePrivateDirectoryAndCleansItUp() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-workspace-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let workspace = try TemporaryWorkspace.create(in: root)
    let attributes = try FileManager.default.attributesOfItem(atPath: workspace.url.path)
    let permissions = attributes[.posixPermissions] as? NSNumber

    #expect(FileManager.default.fileExists(atPath: workspace.url.path))
    #expect(permissions?.intValue == 0o700)

    let outputURL = try workspace.fileURL(named: "audio.wav")
    #expect(outputURL.deletingLastPathComponent() == workspace.url)

    try workspace.cleanup()
    #expect(!FileManager.default.fileExists(atPath: workspace.url.path))
}

@Test func temporaryWorkspaceRejectsPathsThatCouldEscapeItsDirectory() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-workspace-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = try TemporaryWorkspace.create(in: root)

    #expect(throws: TemporaryWorkspaceError.self) {
        try workspace.fileURL(named: "../outside.wav")
    }
    #expect(throws: TemporaryWorkspaceError.self) {
        try workspace.fileURL(named: "nested/outside.wav")
    }
}

@Test func projectSessionCleansOperationWorkspacesOnReplacement() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-workspace-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = ProjectSession(workspaceRoot: root)
    let revision = await session.currentRevision()

    let workspace = try await session.makeWorkspace(
        for: .importMedia,
        revision: revision
    )
    #expect(FileManager.default.fileExists(atPath: workspace.url.path))

    _ = await session.replaceProject()
    #expect(!FileManager.default.fileExists(atPath: workspace.url.path))
}

@Test func projectSessionCleansOperationWorkspaceAfterSuccess() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-workspace-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = ProjectSession(workspaceRoot: root)
    let revision = await session.currentRevision()
    let task = Task<Void, Never> {}
    _ = await session.register(task, for: .importMedia, revision: revision)
    let workspace = try await session.makeWorkspace(for: .importMedia, revision: revision)

    await session.complete(.importMedia, revision: revision)

    #expect(!FileManager.default.fileExists(atPath: workspace.url.path))
}

@Test func projectSessionRemovesAbandonedWorkspacesWhenItStarts() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-workspace-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let abandoned = try TemporaryWorkspace.create(in: root)
    #expect(FileManager.default.fileExists(atPath: abandoned.url.path))

    _ = ProjectSession(workspaceRoot: root)

    #expect(!FileManager.default.fileExists(atPath: abandoned.url.path))
}
