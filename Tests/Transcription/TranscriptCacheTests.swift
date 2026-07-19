import Foundation
import Testing
@testable import Redact

@Test func mediaFingerprintChangesWhenSampledContentChanges() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-fingerprint-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let mediaURL = directory.appendingPathComponent("private-name.mov")
    try Data("first content".utf8).write(to: mediaURL)
    let first = try MediaFingerprint.make(for: mediaURL)

    try Data("second content".utf8).write(to: mediaURL)
    let second = try MediaFingerprint.make(for: mediaURL)

    #expect(first != second)
    #expect(!first.contentDigest.contains("private-name"))
}

@Test func transcriptCacheRoundTripsWithoutPuttingMediaPathInItsKey() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-cache-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TranscriptCache(rootDirectory: root)
    let key = TranscriptCacheKey(
        fingerprint: MediaFingerprint(
            fileSize: 123,
            modificationTime: 456,
            contentDigest: "digest"
        ),
        model: "small",
        engineVersion: "whisperkit-0.15.0",
        optionsVersion: "word-timestamps-vad-v1"
    )
    let transcript = RawTranscript(
        segments: [
            RawSegment(
                id: 0,
                words: [RawWord(word: "hello", start: 0, end: 0.4, confidence: 0.9)]
            ),
        ],
        language: "en",
        duration: 1
    )

    try await cache.save(transcript, for: key)
    let loaded = try await cache.load(for: key)
    let files = try FileManager.default.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: nil
    )
    let attributes = try #require(
        files.first.map { try FileManager.default.attributesOfItem(atPath: $0.path) }
    )
    let permissions = attributes[.posixPermissions] as? NSNumber

    #expect(loaded == transcript)
    #expect(files.count == 1)
    #expect(!files[0].lastPathComponent.contains("small"))
    #expect(permissions?.intValue == 0o600)
}

@Test func transcriptCacheMissReturnsNil() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-cache-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TranscriptCache(rootDirectory: root)
    let key = TranscriptCacheKey(
        fingerprint: MediaFingerprint(fileSize: 1, modificationTime: 1, contentDigest: "missing"),
        model: "small",
        engineVersion: "whisperkit-0.15.0",
        optionsVersion: "word-timestamps-vad-v1"
    )

    #expect(try await cache.load(for: key) == nil)
}

@Test func transcriptCacheRemovesCorruptEntriesAndReturnsAMiss() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-cache-tests-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = TranscriptCache(rootDirectory: root)
    let key = TranscriptCacheKey(
        fingerprint: MediaFingerprint(fileSize: 10, modificationTime: 20, contentDigest: "corrupt"),
        model: "small",
        engineVersion: "whisperkit-0.15.0",
        optionsVersion: "word-timestamps-vad-v1"
    )
    let transcript = RawTranscript(segments: [], language: "en", duration: 1)

    try await cache.save(transcript, for: key)
    let cacheFile = try #require(
        FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).first
    )
    try Data("not-json".utf8).write(to: cacheFile)

    #expect(try await cache.load(for: key) == nil)
    #expect(
        try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ).isEmpty
    )
}
