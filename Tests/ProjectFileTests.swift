import Foundation
import Testing
@testable import Redact

private let sampleFingerprint = MediaFingerprint(
    fileSize: 1_024,
    modificationTime: 2_000_000_000,
    contentDigest: String(repeating: "a", count: 64)
)

private func makeTranscript(wordCount: Int = 2) -> SourceTranscript {
    SourceTranscript(
        words: (0..<wordCount).map { index in
            TranscriptWord(
                id: "w_\(index)",
                text: "word\(index)",
                start: Double(index),
                end: Double(index) + 0.5,
                confidence: 0.9,
                isSilence: false
            )
        },
        language: "en",
        duration: Double(wordCount)
    )
}

private func makeProjectFile() -> ProjectFile {
    ProjectFile(
        media: ProjectMediaReference(
            displayName: "sample.mov",
            fingerprint: sampleFingerprint,
            relativePath: "Media/sample.mov",
            bookmarkData: Data("bookmark".utf8)
        ),
        transcript: makeTranscript(),
        edits: EditDecisionList(deletedWordIDs: ["w_1"])
    )
}

private func v1FixtureData() throws -> Data {
    let url = try #require(
        Bundle.module.url(
            forResource: "project-v1",
            withExtension: "rdt",
            subdirectory: "Fixtures"
        )
    )
    return try Data(contentsOf: url)
}

@Test func projectFileV2_roundTripsCanonicalProjectData() throws {
    let original = makeProjectFile()

    let data = try ProjectFileCodec.encode(original)
    let decoded = try ProjectFileCodec.decode(data)

    #expect(decoded == original)
    #expect(decoded.version == 2)
    #expect(decoded.transcript.words.count == 2)
    #expect(decoded.edits.deletedWordIDs == ["w_1"])
}

@Test func projectFileV2_encodesNoAbsoluteMediaPath() throws {
    let data = try ProjectFileCodec.encode(makeProjectFile())
    let json = try #require(String(data: data, encoding: .utf8))
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let media = try #require(object["media"] as? [String: Any])

    #expect(!json.contains("/Users/example"))
    #expect(media["relativePath"] as? String == "Media/sample.mov")
}

@Test func projectFileV1_migratesToCanonicalVersionTwoInMemory() throws {
    let migrated = try ProjectFileCodec.decode(v1FixtureData())

    #expect(migrated.version == 2)
    #expect(migrated.media.displayName == "sample.mov")
    #expect(migrated.media.legacyAbsolutePath == "/Users/example/Videos/sample.mov")
    #expect(migrated.transcript.words.map(\.text) == ["Hello", "world."])
    #expect(migrated.edits.deletedWordIDs == ["w_1"])
}

@Test func projectFileV1_importIsReadOnlyAndReencodesAsVersionTwo() throws {
    let migrated = try ProjectFileCodec.decode(v1FixtureData())
    let encoded = try ProjectFileCodec.encode(migrated)
    let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])

    #expect(object["version"] as? Int == 2)
    #expect(object["videoPath"] == nil)
    #expect(object["segments"] == nil)
}

@Test func projectFileV2_rejectsDeletedWordIDsOutsideTranscript() {
    let invalid = ProjectFile(
        media: makeProjectFile().media,
        transcript: makeTranscript(wordCount: 1),
        edits: EditDecisionList(deletedWordIDs: ["missing"])
    )

    #expect(throws: ProjectFileError.self) {
        try ProjectFileCodec.encode(invalid)
    }
}

@Test func projectFileV2_rejectsDuplicateWordIDs() {
    let word = makeTranscript(wordCount: 1).words[0]
    let invalid = ProjectFile(
        media: makeProjectFile().media,
        transcript: SourceTranscript(words: [word, word], language: "en", duration: 1),
        edits: EditDecisionList()
    )

    #expect(throws: ProjectFileError.self) {
        try ProjectFileCodec.encode(invalid)
    }
}

@Test func projectFileV2_rejectsUnverifiedAndTraversingMediaReferences() {
    let unverified = ProjectFile(
        media: ProjectMediaReference(
            displayName: "sample.mov",
            fingerprint: nil,
            relativePath: "../../sample.mov",
            bookmarkData: nil
        ),
        transcript: makeTranscript(),
        edits: EditDecisionList()
    )
    let traversingName = ProjectFile(
        media: ProjectMediaReference(
            displayName: "../sample.mov",
            fingerprint: sampleFingerprint,
            relativePath: nil,
            bookmarkData: nil
        ),
        transcript: makeTranscript(),
        edits: EditDecisionList()
    )

    #expect(throws: ProjectFileError.self) {
        try ProjectFileCodec.encode(unverified)
    }
    #expect(throws: ProjectFileError.self) {
        try ProjectFileCodec.encode(traversingName)
    }
}

@Test func projectFile_rejectsUnsupportedVersion() {
    let data = Data("{\"version\":99}".utf8)

    #expect(throws: ProjectFileError.self) {
        try ProjectFileCodec.decode(data)
    }
}

@Test func projectFile_rejectsMalformedJSON() {
    #expect(throws: (any Error).self) {
        try ProjectFileCodec.decode(Data("{not-json}".utf8))
    }
}

@Test func projectFile_rejectsOversizedInputBeforeDecoding() {
    let data = Data(repeating: 0, count: ProjectFileLimits.maximumFileBytes + 1)

    #expect(throws: ProjectFileError.self) {
        try ProjectFileCodec.decode(data)
    }
}
