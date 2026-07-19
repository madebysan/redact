import CryptoKit
import Foundation

struct TranscriptCacheKey: Codable, Equatable, Hashable, Sendable {
    let fingerprint: MediaFingerprint
    let model: String
    let engineVersion: String
    let optionsVersion: String

    static func current(fingerprint: MediaFingerprint, model: String) -> TranscriptCacheKey {
        TranscriptCacheKey(
            fingerprint: fingerprint,
            model: model,
            engineVersion: "whisperkit-0.15.0",
            optionsVersion: "word-timestamps-vad-v1"
        )
    }
}

actor TranscriptCache {
    private let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    init(
        rootDirectory: URL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("Redact", isDirectory: true)
        .appendingPathComponent("TranscriptCache", isDirectory: true)
    ) {
        self.rootDirectory = rootDirectory
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    func load(for key: TranscriptCacheKey) throws -> RawTranscript? {
        let fileURL = try cacheFileURL(for: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        do {
            return try decoder.decode(
                RawTranscript.self,
                from: Data(contentsOf: fileURL)
            )
        } catch {
            try? FileManager.default.removeItem(at: fileURL)
            return nil
        }
    }

    func save(_ transcript: RawTranscript, for key: TranscriptCacheKey) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: rootDirectory.path
        )

        let fileURL = try cacheFileURL(for: key)
        try encoder.encode(transcript).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: fileURL.path
        )
    }

    private func cacheFileURL(for key: TranscriptCacheKey) throws -> URL {
        let keyData = try encoder.encode(key)
        let digest = SHA256.hash(data: keyData).map {
            String(format: "%02x", $0)
        }.joined()
        return rootDirectory.appendingPathComponent(digest + ".json")
    }
}
