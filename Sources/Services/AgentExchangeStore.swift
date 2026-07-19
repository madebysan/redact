import Darwin
import CryptoKit
import Foundation

struct AgentExchangePaths: Equatable, Sendable {
    let directoryURL: URL
    let snapshotURL: URL
    let instructionsURL: URL
    let proposalURL: URL
}

struct PreparedAgentExchange: Equatable, Sendable {
    let snapshot: AgentTranscriptSnapshot
    let paths: AgentExchangePaths
    let prompt: String
}

final class AgentExchangeStore {
    static let shared = AgentExchangeStore()

    let rootDirectory: URL
    private let fileManager: FileManager
    private var lastSeenProposalDigests: [String: String] = [:]

    init(
        rootDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("Redact", isDirectory: true)
            .appendingPathComponent("Agent Exchange", isDirectory: true),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func prepare(snapshot: AgentTranscriptSnapshot) throws -> PreparedAgentExchange {
        let paths = try paths(snapshotID: snapshot.snapshotID)
        try createPrivateDirectory(rootDirectory)
        try createPrivateDirectory(paths.directoryURL)

        let snapshotData = try AgentSnapshotCodec.encode(snapshot)
        try writePrivate(snapshotData, to: paths.snapshotURL)
        let prompt = AgentPromptBuilder.prompt(snapshot: snapshot, paths: paths)
        try writePrivate(Data(prompt.utf8), to: paths.instructionsURL)

        return PreparedAgentExchange(
            snapshot: snapshot,
            paths: paths,
            prompt: prompt
        )
    }

    func exchange(snapshotID: String) throws -> PreparedAgentExchange {
        let paths = try paths(snapshotID: snapshotID)
        let snapshot = try AgentSnapshotCodec.decode(Data(contentsOf: paths.snapshotURL))
        let prompt = try String(contentsOf: paths.instructionsURL, encoding: .utf8)
        return PreparedAgentExchange(snapshot: snapshot, paths: paths, prompt: prompt)
    }

    func pendingExchange(baseDigest: String) -> PreparedAgentExchange? {
        guard let directoryURLs = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = directoryURLs.compactMap { directoryURL -> (Date, PreparedAgentExchange)? in
            guard (try? directoryURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
                return nil
            }
            let snapshotID = directoryURL.lastPathComponent
            guard let paths = try? paths(snapshotID: snapshotID),
                  let snapshotData = try? Data(contentsOf: paths.snapshotURL),
                  let snapshot = try? AgentSnapshotCodec.decode(snapshotData),
                  snapshot.baseDigest == baseDigest,
                  let prompt = try? String(contentsOf: paths.instructionsURL, encoding: .utf8) else {
                return nil
            }
            let date = (try? directoryURL.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            return (
                date,
                PreparedAgentExchange(snapshot: snapshot, paths: paths, prompt: prompt)
            )
        }
        return candidates.max { $0.0 < $1.0 }?.1
    }

    func loadProposalIfChanged(snapshotID: String) throws -> AgentEditProposal? {
        let proposalURL = try paths(snapshotID: snapshotID).proposalURL
        guard fileManager.fileExists(atPath: proposalURL.path) else { return nil }
        let attributes = try fileManager.attributesOfItem(atPath: proposalURL.path)
        if let size = attributes[.size] as? NSNumber,
           size.intValue > AgentExchangeLimits.maximumProposalBytes {
            throw AgentProposalError.fileTooLarge
        }

        let data = try Data(contentsOf: proposalURL)
        let digest = data.sha256Hex
        guard lastSeenProposalDigests[snapshotID] != digest else { return nil }
        // Remember malformed or partial payloads too. A corrected atomic write has a
        // different digest and will be evaluated on the next directory event.
        lastSeenProposalDigests[snapshotID] = digest
        return try AgentProposalCodec.decode(data)
    }

    func complete(snapshotID: String) throws {
        let directoryURL = try paths(snapshotID: snapshotID).directoryURL
        guard fileManager.fileExists(atPath: directoryURL.path) else { return }
        try fileManager.removeItem(at: directoryURL)
        lastSeenProposalDigests.removeValue(forKey: snapshotID)
    }

    func expireAbandonedExchanges(olderThan cutoff: Date) throws {
        guard fileManager.fileExists(atPath: rootDirectory.path) else { return }
        let directoryURLs = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directoryURL in directoryURLs {
            let values = try directoryURL.resourceValues(
                forKeys: [.contentModificationDateKey, .isDirectoryKey]
            )
            guard values.isDirectory == true,
                  let modificationDate = values.contentModificationDate,
                  modificationDate < cutoff,
                  (try? paths(snapshotID: directoryURL.lastPathComponent)) != nil else {
                continue
            }
            try fileManager.removeItem(at: directoryURL)
            lastSeenProposalDigests.removeValue(forKey: directoryURL.lastPathComponent)
        }
    }

    private func paths(snapshotID: String) throws -> AgentExchangePaths {
        guard let uuid = UUID(uuidString: snapshotID),
              uuid.uuidString.lowercased() == snapshotID.lowercased() else {
            throw AgentProposalError.invalidField("snapshot identifier")
        }
        let directoryURL = rootDirectory.appendingPathComponent(
            snapshotID.lowercased(),
            isDirectory: true
        )
        return AgentExchangePaths(
            directoryURL: directoryURL,
            snapshotURL: directoryURL.appendingPathComponent("snapshot.json"),
            instructionsURL: directoryURL.appendingPathComponent("instructions.md"),
            proposalURL: directoryURL.appendingPathComponent("proposal.json")
        )
    }

    private func createPrivateDirectory(_ url: URL) throws {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    private func writePrivate(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

enum AgentPromptBuilder {
    static func prompt(
        snapshot: AgentTranscriptSnapshot,
        paths: AgentExchangePaths
    ) -> String {
        """
        Connect this conversation to my Redact project.

        Read the privacy-safe transcript snapshot at:
        \(paths.snapshotURL.path)

        Do not propose edits yet. Confirm that the snapshot is connected, then ask me what I want changed. I will describe the edit in this conversation.

        After I give you the edit request, use that request as the proposal's "goal" and write one deletion-only proposal to:
        \(paths.proposalURL.path)

        Do not edit any .rdt file. Do not modify source media. Redact is the only application allowed to apply changes. Treat word IDs and expected text as exact data, and use only IDs present in the snapshot.

        Write valid JSON with this shape:

        {
          "version": \(AgentProposalCodec.currentVersion),
          "snapshotID": "\(snapshot.snapshotID)",
          "baseDigest": "\(snapshot.baseDigest)",
          "agent": "\(snapshot.agent.displayName)",
          "goal": "the edit request I gave you in this conversation",
          "targetReductionSeconds": 30,
          "groups": [
            {
              "id": "short-unique-id",
              "words": [{"id": "w_123", "expectedText": "Peter"}],
              "reason": "short explanation",
              "category": "namedTerm",
              "requirement": "required",
              "priority": 100
            }
          ]
        }

        Allowed categories are filler, pause, namedTerm, and semanticCut. Requirement is required or optional. Omit targetReductionSeconds or priority when they do not apply. Proposals may delete words only.

        Finish by writing to a temporary file in the same folder and atomically renaming it to proposal.json. Do not include paths, commands, transcript copies, or extra fields in the proposal.
        """
    }
}

final class AgentExchangeWatcher {
    private let directoryURL: URL
    private let queue: DispatchQueue
    private let onChange: @Sendable () -> Void
    private var descriptor: Int32 = -1
    private var source: DispatchSourceFileSystemObject?

    init(
        directoryURL: URL,
        queue: DispatchQueue = .main,
        onChange: @escaping @Sendable () -> Void
    ) {
        self.directoryURL = directoryURL
        self.queue = queue
        self.onChange = onChange
    }

    deinit {
        stop()
    }

    func start() throws {
        guard source == nil else { return }
        descriptor = Darwin.open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw CocoaError(.fileReadNoPermission)
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .attrib, .rename, .delete],
            queue: queue
        )
        source.setEventHandler(handler: onChange)
        source.setCancelHandler { [descriptor] in
            Darwin.close(descriptor)
        }
        self.source = source
        source.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        descriptor = -1
    }
}

private extension Data {
    var sha256Hex: String {
        SHA256.hash(data: self).map { String(format: "%02x", $0) }.joined()
    }
}
