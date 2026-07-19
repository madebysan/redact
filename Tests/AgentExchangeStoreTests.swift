import Foundation
import Testing
@testable import Redact

@Test func agentExchangeStoreWritesPrivateSnapshotAndCopyReadyPrompt() throws {
    let root = temporaryAgentExchangeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AgentExchangeStore(rootDirectory: root)
    let snapshot = try makeStoreSnapshot(id: "00000000-0000-0000-0000-000000000011")

    let exchange = try store.prepare(snapshot: snapshot)

    #expect(FileManager.default.fileExists(atPath: exchange.paths.snapshotURL.path))
    #expect(FileManager.default.fileExists(atPath: exchange.paths.instructionsURL.path))
    #expect(exchange.prompt.contains(exchange.paths.snapshotURL.path))
    #expect(exchange.prompt.contains(exchange.paths.proposalURL.path))
    #expect(exchange.prompt.contains("Do not edit any .rdt file"))
    #expect(exchange.prompt.contains("Confirm that the snapshot is connected"))
    #expect(exchange.prompt.contains("ask me what I want changed"))

    let decoded = try AgentSnapshotCodec.decode(Data(contentsOf: exchange.paths.snapshotURL))
    #expect(decoded == snapshot)
    let attributes = try FileManager.default.attributesOfItem(atPath: exchange.paths.directoryURL.path)
    #expect((attributes[FileAttributeKey.posixPermissions] as? NSNumber)?.intValue == 0o700)
}

@Test func agentExchangeStoreRetriesPartialProposalAndIgnoresDuplicateDelivery() throws {
    let root = temporaryAgentExchangeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AgentExchangeStore(rootDirectory: root)
    let snapshot = try makeStoreSnapshot(id: "00000000-0000-0000-0000-000000000012")
    let exchange = try store.prepare(snapshot: snapshot)

    try Data("{\"version\":".utf8).write(to: exchange.paths.proposalURL, options: .atomic)
    #expect(throws: AgentProposalError.malformedJSON) {
        try store.loadProposalIfChanged(snapshotID: snapshot.snapshotID)
    }
    #expect(try store.loadProposalIfChanged(snapshotID: snapshot.snapshotID) == nil)

    let proposal = storeProposal(snapshot: snapshot)
    let temporaryURL = exchange.paths.directoryURL.appendingPathComponent("proposal.tmp")
    try AgentProposalCodec.encode(proposal).write(to: temporaryURL, options: .atomic)
    _ = try FileManager.default.replaceItemAt(
        exchange.paths.proposalURL,
        withItemAt: temporaryURL
    )

    #expect(try store.loadProposalIfChanged(snapshotID: snapshot.snapshotID) == proposal)
    #expect(try store.loadProposalIfChanged(snapshotID: snapshot.snapshotID) == nil)
}

@Test func agentExchangeStoreRestoresPendingProposalAndCompletesExplicitly() throws {
    let root = temporaryAgentExchangeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AgentExchangeStore(rootDirectory: root)
    let snapshot = try makeStoreSnapshot(id: "00000000-0000-0000-0000-000000000013")
    let exchange = try store.prepare(snapshot: snapshot)
    try AgentProposalCodec.encode(storeProposal(snapshot: snapshot))
        .write(to: exchange.paths.proposalURL, options: .atomic)

    let pending = try #require(store.pendingExchange(baseDigest: snapshot.baseDigest))
    #expect(pending.snapshot == snapshot)
    #expect(pending.paths.directoryURL == exchange.paths.directoryURL)

    try store.complete(snapshotID: snapshot.snapshotID)
    #expect(!FileManager.default.fileExists(atPath: exchange.paths.directoryURL.path))
    #expect(store.pendingExchange(baseDigest: snapshot.baseDigest) == nil)
}

@Test func agentExchangeWatcherNoticesAtomicProposalRename() async throws {
    let root = temporaryAgentExchangeRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = AgentExchangeStore(rootDirectory: root)
    let snapshot = try makeStoreSnapshot(id: "00000000-0000-0000-0000-000000000014")
    let exchange = try store.prepare(snapshot: snapshot)

    let signal = AsyncStream<Void>.makeStream()
    let watcher = AgentExchangeWatcher(directoryURL: exchange.paths.directoryURL) {
        signal.continuation.yield(())
    }
    try watcher.start()
    defer {
        watcher.stop()
        signal.continuation.finish()
    }

    let temporaryURL = exchange.paths.directoryURL.appendingPathComponent("proposal.tmp")
    try AgentProposalCodec.encode(storeProposal(snapshot: snapshot))
        .write(to: temporaryURL, options: .atomic)
    try FileManager.default.moveItem(at: temporaryURL, to: exchange.paths.proposalURL)

    var iterator = signal.stream.makeAsyncIterator()
    let noticed = await withTaskGroup(of: Bool.self) { group in
        group.addTask { await iterator.next() != nil }
        group.addTask {
            try? await Task.sleep(for: .seconds(2))
            return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
    }
    #expect(noticed)
}

private func temporaryAgentExchangeRoot() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-agent-exchange-tests-" + UUID().uuidString, isDirectory: true)
}

private func makeStoreSnapshot(id: String) throws -> AgentTranscriptSnapshot {
    let project = ProjectDocument()
    project.setTranscript(
        RawTranscript(
            segments: [
                RawSegment(
                    id: 0,
                    words: [RawWord(word: "Peter", start: 0, end: 0.4, confidence: 1)]
                ),
            ],
            language: "en",
            duration: 1
        )
    )
    return try AgentSnapshotBuilder.make(
        project: project,
        agent: .codex,
        snapshotID: id
    )
}

private func storeProposal(snapshot: AgentTranscriptSnapshot) -> AgentEditProposal {
    AgentEditProposal(
        version: AgentProposalCodec.currentVersion,
        snapshotID: snapshot.snapshotID,
        baseDigest: snapshot.baseDigest,
        agent: "Codex",
        goal: "Remove Peter",
        targetReductionSeconds: nil,
        groups: [
            AgentProposalGroup(
                id: "remove-peter",
                words: [AgentProposalWord(id: "w_0", expectedText: "Peter")],
                reason: "Remove the name",
                category: .namedTerm,
                requirement: .required,
                priority: 100
            ),
        ]
    )
}
