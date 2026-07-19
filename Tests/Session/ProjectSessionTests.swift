import Foundation
import Testing
@testable import Redact

private actor InvocationProbe {
    private(set) var wasInvoked = false

    func markInvoked() {
        wasInvoked = true
    }
}

@Test func replacingProjectInvalidatesItsRevisionAndCancelsRegisteredTasks() async {
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-session-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: workspaceRoot) }

    let session = ProjectSession(workspaceRoot: workspaceRoot)
    let firstRevision = await session.currentRevision()
    let task = Task<Void, Never> {
        try? await Task.sleep(for: .seconds(60))
    }

    let registered = await session.register(
        task,
        for: .importMedia,
        revision: firstRevision
    )
    let secondRevision = await session.replaceProject()
    await Task.yield()

    #expect(registered)
    #expect(firstRevision != secondRevision)
    #expect(!(await session.isCurrent(firstRevision)))
    #expect(await session.isCurrent(secondRevision))
    #expect(task.isCancelled)
}

@Test func staleTasksCannotRegisterAgainstAReplacementProject() async {
    let session = ProjectSession()
    let staleRevision = await session.currentRevision()
    _ = await session.replaceProject()
    let task = Task<Void, Never> {}

    let registered = await session.register(
        task,
        for: .transcription,
        revision: staleRevision
    )

    #expect(!registered)
    #expect(task.isCancelled)
}

@Test func completingOneOperationDoesNotCancelAnother() async {
    let session = ProjectSession()
    let revision = await session.currentRevision()
    let importTask = Task<Void, Never> {}
    let exportTask = Task<Void, Never> {
        try? await Task.sleep(for: .seconds(60))
    }

    _ = await session.register(importTask, for: .importMedia, revision: revision)
    _ = await session.register(exportTask, for: .export, revision: revision)
    await session.complete(.importMedia, revision: revision)

    #expect(!exportTask.isCancelled)
    await session.cancel(.export)
    #expect(exportTask.isCancelled)
}

@Test func staleRevisionCannotStartWorkThatPublishesAResult() async {
    let session = ProjectSession()
    let staleRevision = await session.currentRevision()
    _ = await session.replaceProject()
    let probe = InvocationProbe()

    let started = await session.start(.importMedia, revision: staleRevision) {
        await probe.markInvoked()
    }
    await Task.yield()

    #expect(!started)
    #expect(!(await probe.wasInvoked))
}

@Test func operationTransitionMovesTaskOwnershipToTheNextStage() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-session-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let session = ProjectSession(workspaceRoot: root)
    let revision = await session.currentRevision()
    let task = Task<Void, Never> {
        try? await Task.sleep(for: .seconds(60))
    }
    _ = await session.register(task, for: .importMedia, revision: revision)
    let workspace = try await session.makeWorkspace(for: .importMedia, revision: revision)

    let transitioned = await session.transition(
        from: .importMedia,
        to: .transcription,
        revision: revision
    )
    await session.cancel(.importMedia)
    #expect(!task.isCancelled)
    #expect(FileManager.default.fileExists(atPath: workspace.url.path))

    await session.cancel(.transcription)
    #expect(transitioned)
    #expect(task.isCancelled)
    #expect(!FileManager.default.fileExists(atPath: workspace.url.path))
}
