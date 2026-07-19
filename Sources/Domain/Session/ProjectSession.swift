import Foundation

struct SessionRevision: Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

enum ProjectOperation: Hashable, Sendable {
    case importMedia
    case transcription
    case export
}

enum ProjectSessionError: Error, Equatable {
    case staleRevision
}

actor ProjectSession {
    private struct RegisteredTask {
        let revision: SessionRevision
        let task: Task<Void, Never>
    }

    private var revision = SessionRevision()
    private var tasks: [ProjectOperation: RegisteredTask] = [:]
    private var workspaces: [ProjectOperation: TemporaryWorkspace] = [:]
    private let workspaceRoot: URL

    init(
        workspaceRoot: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("com.redact.app", isDirectory: true)
    ) {
        self.workspaceRoot = workspaceRoot
        try? TemporaryWorkspace.cleanupAbandoned(in: workspaceRoot)
    }

    func currentRevision() -> SessionRevision {
        revision
    }

    func isCurrent(_ candidate: SessionRevision) -> Bool {
        revision == candidate
    }

    @discardableResult
    func replaceProject() -> SessionRevision {
        cancelAllOperations()
        cleanupAllWorkspaces()
        revision = SessionRevision()
        return revision
    }

    @discardableResult
    func register(
        _ task: Task<Void, Never>,
        for operation: ProjectOperation,
        revision candidate: SessionRevision
    ) -> Bool {
        guard candidate == revision else {
            task.cancel()
            return false
        }

        tasks[operation]?.task.cancel()
        tasks[operation] = RegisteredTask(revision: candidate, task: task)
        return true
    }

    @discardableResult
    func start(
        _ operation: ProjectOperation,
        revision candidate: SessionRevision,
        body: @escaping @Sendable () async -> Void
    ) -> Bool {
        guard candidate == revision else { return false }

        tasks[operation]?.task.cancel()
        let task = Task { await body() }
        tasks[operation] = RegisteredTask(revision: candidate, task: task)
        return true
    }

    func makeWorkspace(
        for operation: ProjectOperation,
        revision candidate: SessionRevision
    ) throws -> TemporaryWorkspace {
        guard candidate == revision else {
            throw ProjectSessionError.staleRevision
        }

        try? workspaces.removeValue(forKey: operation)?.cleanup()
        let workspace = try TemporaryWorkspace.create(in: workspaceRoot)
        workspaces[operation] = workspace
        return workspace
    }

    @discardableResult
    func transition(
        from source: ProjectOperation,
        to destination: ProjectOperation,
        revision candidate: SessionRevision
    ) -> Bool {
        guard source != destination,
              candidate == revision,
              let registeredTask = tasks[source],
              registeredTask.revision == candidate else {
            return false
        }

        tasks[destination]?.task.cancel()
        try? workspaces.removeValue(forKey: destination)?.cleanup()
        tasks.removeValue(forKey: source)
        tasks[destination] = registeredTask

        if let workspace = workspaces.removeValue(forKey: source) {
            workspaces[destination] = workspace
        }
        return true
    }

    func complete(
        _ operation: ProjectOperation,
        revision candidate: SessionRevision
    ) {
        guard candidate == revision,
              tasks[operation]?.revision == candidate else {
            return
        }

        tasks.removeValue(forKey: operation)
        try? workspaces.removeValue(forKey: operation)?.cleanup()
    }

    func cancel(_ operation: ProjectOperation) {
        tasks.removeValue(forKey: operation)?.task.cancel()
        try? workspaces.removeValue(forKey: operation)?.cleanup()
    }

    func close() {
        cancelAllOperations()
        cleanupAllWorkspaces()
        revision = SessionRevision()
    }

    private func cancelAllOperations() {
        for registeredTask in tasks.values {
            registeredTask.task.cancel()
        }
        tasks.removeAll()
    }

    private func cleanupAllWorkspaces() {
        for workspace in workspaces.values {
            try? workspace.cleanup()
        }
        workspaces.removeAll()
    }
}
