import AppKit
import Foundation
import Testing
@testable import Redact

@MainActor
@Test func redactDocumentUsesNativeDirtyTrackingAndAutosave() {
    let document = RedactDocument()

    #expect(RedactDocument.autosavesInPlace)
    #expect(!document.isDocumentEdited)

    document.updateChangeCount(.changeDone)
    #expect(document.isDocumentEdited)

    document.updateChangeCount(.changeUndone)
    #expect(!document.isDocumentEdited)
}

@MainActor
@Test func redactDocumentWritesCanonicalVersionTwoData() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-document-tests-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let mediaURL = directory.appendingPathComponent("source.mov")
    try Data("media".utf8).write(to: mediaURL)
    let projectURL = directory.appendingPathComponent("project.rdt")
    let document = RedactDocument()
    document.fileURL = projectURL
    document.setSourceMediaURL(mediaURL)
    document.project.setTranscript(
        RawTranscript(
            segments: [
                RawSegment(
                    id: 0,
                    words: [
                        RawWord(word: "hello", start: 0, end: 0.5, confidence: 0.9),
                    ]
                ),
            ],
            language: "en",
            duration: 1
        )
    )

    let data = try document.data(ofType: RedactDocument.typeIdentifier)
    let decoded = try ProjectFileCodec.decode(data)

    #expect(decoded.version == 2)
    #expect(decoded.media.fingerprint != nil)
    #expect(decoded.media.relativePath == "source.mov")
    #expect(decoded.transcript.words.map(\.text) == ["hello"])

    try FileManager.default.removeItem(at: mediaURL)
    let recoveryData = try document.data(ofType: RedactDocument.typeIdentifier)
    #expect(try ProjectFileCodec.decode(recoveryData).transcript == decoded.transcript)
}

@MainActor
@Test func redactDocumentSaveAsUsesDestinationForRelativeMediaReference() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-save-as-tests-" + UUID().uuidString, isDirectory: true)
    let mediaDirectory = directory.appendingPathComponent("Media", isDirectory: true)
    try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let mediaURL = mediaDirectory.appendingPathComponent("source.mov")
    try Data("media".utf8).write(to: mediaURL)
    let projectURL = directory.appendingPathComponent("project.rdt")
    let document = RedactDocument()
    document.setSourceMediaURL(mediaURL)
    document.project.setTranscript(
        RawTranscript(
            segments: [
                RawSegment(
                    id: 0,
                    words: [
                        RawWord(word: "hello", start: 0, end: 0.5, confidence: 0.9),
                    ]
                ),
            ],
            language: "en",
            duration: 1
        )
    )
    document.updateChangeCount(.changeDone)

    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        document.save(
            to: projectURL,
            ofType: RedactDocument.typeIdentifier,
            for: .saveAsOperation
        ) { error in
            if let error {
                continuation.resume(throwing: error)
            } else {
                continuation.resume()
            }
        }
    }

    let decoded = try ProjectFileCodec.decode(Data(contentsOf: projectURL))
    #expect(decoded.media.relativePath == "Media/source.mov")
    #expect(document.fileURL == projectURL)
    #expect(!document.isDocumentEdited)
}

@Test func projectMediaReferenceUsesRelativeFallbackAndFingerprint() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-reference-tests-" + UUID().uuidString, isDirectory: true)
    let mediaDirectory = directory.appendingPathComponent("Media", isDirectory: true)
    try FileManager.default.createDirectory(at: mediaDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let mediaURL = mediaDirectory.appendingPathComponent("source.mov")
    try Data("media".utf8).write(to: mediaURL)
    let projectURL = directory.appendingPathComponent("project.rdt")
    let reference = ProjectMediaReference(
        displayName: "source.mov",
        fingerprint: try MediaFingerprint.make(for: mediaURL),
        relativePath: "Media/source.mov",
        bookmarkData: nil
    )

    #expect(reference.resolvedURL(relativeTo: projectURL) == mediaURL)

    try Data("different media".utf8).write(to: mediaURL)
    #expect(reference.resolvedURL(relativeTo: projectURL) == nil)
}
