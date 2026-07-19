import Foundation

enum ProjectFileLimits {
    static let maximumFileBytes = 32 * 1_024 * 1_024
    static let maximumWords = 250_000
    static let maximumBookmarkBytes = 512 * 1_024
    static let maximumPathBytes = 8 * 1_024
    static let maximumDisplayNameBytes = 1_024
    static let maximumLanguageBytes = 128
    static let maximumWordIDBytes = 512
    static let maximumWordTextBytes = 4 * 1_024
    static let maximumDuration = 7 * 24 * 60 * 60.0
}

/// A durable reference to source media. The bookmark is the primary locator;
/// the relative path is a portable fallback when the project and media move together.
struct ProjectMediaReference: Codable, Equatable, Sendable {
    let displayName: String
    let fingerprint: MediaFingerprint?
    let relativePath: String?
    let bookmarkData: Data?

    /// Used only while importing v1 files. It is deliberately never encoded in v2.
    let legacyAbsolutePath: String?

    init(
        displayName: String,
        fingerprint: MediaFingerprint?,
        relativePath: String?,
        bookmarkData: Data?,
        legacyAbsolutePath: String? = nil
    ) {
        self.displayName = displayName
        self.fingerprint = fingerprint
        self.relativePath = relativePath
        self.bookmarkData = bookmarkData
        self.legacyAbsolutePath = legacyAbsolutePath
    }

    private enum CodingKeys: String, CodingKey {
        case displayName
        case fingerprint
        case relativePath
        case bookmarkData
    }

    static func make(mediaURL: URL, projectURL: URL?) throws -> ProjectMediaReference {
        ProjectMediaReference(
            displayName: mediaURL.lastPathComponent,
            fingerprint: try MediaFingerprint.make(for: mediaURL),
            relativePath: projectURL.flatMap {
                relativePath(from: $0.deletingLastPathComponent(), to: mediaURL)
            },
            bookmarkData: try? mediaURL.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        )
    }

    func resolvedURL(relativeTo projectURL: URL) -> URL? {
        if let bookmarkData {
            var isStale = false
            if let bookmarkedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ), isMatchingMedia(bookmarkedURL) {
                return bookmarkedURL
            }
        }

        if let relativePath {
            let relativeURL = projectURL.deletingLastPathComponent()
                .appendingPathComponent(relativePath)
                .standardizedFileURL
            if isMatchingMedia(relativeURL) {
                return relativeURL
            }
        }

        if let legacyAbsolutePath {
            let legacyURL = URL(fileURLWithPath: legacyAbsolutePath)
            if isMatchingMedia(legacyURL) {
                return legacyURL
            }
        }

        let adjacentURL = projectURL.deletingLastPathComponent()
            .appendingPathComponent(displayName)
        return isMatchingMedia(adjacentURL) ? adjacentURL : nil
    }

    private func isMatchingMedia(_ url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let fingerprint else { return true }
        guard let candidate = try? MediaFingerprint.make(for: url) else { return false }
        return candidate.fileSize == fingerprint.fileSize
            && candidate.contentDigest == fingerprint.contentDigest
    }

    private static func relativePath(from directoryURL: URL, to fileURL: URL) -> String? {
        let directoryComponents = directoryURL.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        var sharedCount = 0
        while sharedCount < min(directoryComponents.count, fileComponents.count),
              directoryComponents[sharedCount] == fileComponents[sharedCount] {
            sharedCount += 1
        }
        guard sharedCount > 0 else { return nil }

        let parentComponents = Array(
            repeating: "..",
            count: directoryComponents.count - sharedCount
        )
        let childComponents = fileComponents.dropFirst(sharedCount)
        let components = parentComponents + childComponents
        return components.isEmpty ? fileURL.lastPathComponent : components.joined(separator: "/")
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        fingerprint = try container.decodeIfPresent(MediaFingerprint.self, forKey: .fingerprint)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)
        bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        legacyAbsolutePath = nil
    }
}

/// The current .rdt schema. V2 stores the canonical transcript and edit decisions
/// directly so every downstream result can be rebuilt from the same state.
struct ProjectFile: Codable, Equatable, Sendable {
    let version: Int
    let media: ProjectMediaReference
    let transcript: SourceTranscript
    let edits: EditDecisionList
    let segmentStartWordIDs: [String]

    init(
        media: ProjectMediaReference,
        transcript: SourceTranscript,
        edits: EditDecisionList,
        segmentStartWordIDs: [String] = []
    ) {
        version = ProjectFileCodec.currentVersion
        self.media = media
        self.transcript = transcript
        self.edits = edits
        self.segmentStartWordIDs = segmentStartWordIDs
    }
}

enum ProjectFileCodec {
    static let currentVersion = 2

    static func encode(_ project: ProjectFile) throws -> Data {
        try validate(project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(project)
    }

    static func decode(_ data: Data) throws -> ProjectFile {
        guard data.count <= ProjectFileLimits.maximumFileBytes else {
            throw ProjectFileError.fileTooLarge
        }

        let decoder = JSONDecoder()
        let envelope = try decoder.decode(VersionEnvelope.self, from: data)
        let project: ProjectFile

        switch envelope.version {
        case 1:
            project = try migrateV1(decoder.decode(ProjectFileV1.self, from: data))
        case currentVersion:
            project = try decoder.decode(ProjectFile.self, from: data)
        default:
            throw ProjectFileError.unsupportedVersion(envelope.version)
        }

        try validate(project)
        return project
    }

    private static func migrateV1(_ legacy: ProjectFileV1) throws -> ProjectFile {
        let words = legacy.segments.flatMap(\.words)
        return ProjectFile(
            media: ProjectMediaReference(
                displayName: legacy.videoFile,
                fingerprint: nil,
                relativePath: nil,
                bookmarkData: nil,
                legacyAbsolutePath: legacy.videoPath
            ),
            transcript: SourceTranscript(
                v1Words: words,
                language: legacy.language,
                duration: legacy.duration
            ),
            edits: EditDecisionList(v1Words: words),
            segmentStartWordIDs: legacy.segments.compactMap { $0.words.first?.id }
        )
    }

    private static func validate(_ project: ProjectFile) throws {
        guard project.version == currentVersion else {
            throw ProjectFileError.unsupportedVersion(project.version)
        }

        try validateString(
            project.media.displayName,
            maximumBytes: ProjectFileLimits.maximumDisplayNameBytes,
            field: "media display name",
            allowEmpty: false
        )
        guard !project.media.displayName.contains("/"),
              project.media.displayName != ".",
              project.media.displayName != ".." else {
            throw ProjectFileError.invalidField("media display name")
        }
        if let relativePath = project.media.relativePath {
            try validateString(
                relativePath,
                maximumBytes: ProjectFileLimits.maximumPathBytes,
                field: "relative media path",
                allowEmpty: false
            )
            guard !(relativePath as NSString).isAbsolutePath else {
                throw ProjectFileError.invalidField("relative media path")
            }
        }
        if let bookmarkData = project.media.bookmarkData,
           bookmarkData.count > ProjectFileLimits.maximumBookmarkBytes {
            throw ProjectFileError.invalidField("media bookmark")
        }
        if let fingerprint = project.media.fingerprint {
            guard fingerprint.fileSize >= 0,
                  fingerprint.modificationTime >= 0,
                  fingerprint.contentDigest.count == 64,
                  fingerprint.contentDigest.allSatisfy({ $0.isHexDigit }) else {
                throw ProjectFileError.invalidField("media fingerprint")
            }
        } else if project.media.relativePath != nil || project.media.bookmarkData != nil {
            throw ProjectFileError.invalidField("media reference without a fingerprint")
        }

        let transcript = project.transcript
        guard transcript.words.count <= ProjectFileLimits.maximumWords else {
            throw ProjectFileError.tooManyWords
        }
        try validateString(
            transcript.language,
            maximumBytes: ProjectFileLimits.maximumLanguageBytes,
            field: "language"
        )
        guard transcript.duration.isFinite,
              transcript.duration >= 0,
              transcript.duration <= ProjectFileLimits.maximumDuration else {
            throw ProjectFileError.invalidField("duration")
        }

        var wordIDs = Set<String>()
        wordIDs.reserveCapacity(transcript.words.count)
        for word in transcript.words {
            try validateString(
                word.id,
                maximumBytes: ProjectFileLimits.maximumWordIDBytes,
                field: "word id",
                allowEmpty: false
            )
            try validateString(
                word.text,
                maximumBytes: ProjectFileLimits.maximumWordTextBytes,
                field: "word text"
            )
            guard word.start.isFinite,
                  word.end.isFinite,
                  word.confidence.isFinite,
                  word.start >= 0,
                  word.end >= word.start,
                  word.end <= ProjectFileLimits.maximumDuration,
                  (0...1).contains(word.confidence) else {
                throw ProjectFileError.invalidField("word timing or confidence")
            }
            guard wordIDs.insert(word.id).inserted else {
                throw ProjectFileError.duplicateWordID(word.id)
            }
        }

        guard project.edits.deletedWordIDs.isSubset(of: wordIDs) else {
            throw ProjectFileError.unknownEditedWord
        }
        guard Set(project.segmentStartWordIDs).count == project.segmentStartWordIDs.count,
              Set(project.segmentStartWordIDs).isSubset(of: wordIDs) else {
            throw ProjectFileError.invalidField("segment boundaries")
        }
    }

    private static func validateString(
        _ value: String,
        maximumBytes: Int,
        field: String,
        allowEmpty: Bool = true
    ) throws {
        guard (allowEmpty || !value.isEmpty), value.utf8.count <= maximumBytes else {
            throw ProjectFileError.invalidField(field)
        }
    }
}

private struct VersionEnvelope: Decodable {
    let version: Int
}

/// Exact v1 wire shape. This type is decode-only by design.
private struct ProjectFileV1: Decodable {
    let version: Int
    let videoFile: String
    let videoPath: String?
    let language: String
    let duration: Double
    let segments: [Segment]
}

enum ProjectFileError: LocalizedError, Equatable {
    case fileTooLarge
    case invalidField(String)
    case tooManyWords
    case duplicateWordID(String)
    case unknownEditedWord
    case unsupportedVersion(Int)

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "This Redact project is larger than the supported 32 MB limit."
        case .invalidField(let field):
            "The Redact project contains an invalid \(field)."
        case .tooManyWords:
            "This Redact project contains more than 250,000 transcript words."
        case .duplicateWordID(let id):
            "The Redact project contains a duplicate word identifier: \(id)."
        case .unknownEditedWord:
            "The Redact project contains an edit for a word that is not in the transcript."
        case .unsupportedVersion(let version):
            "Unsupported Redact project version: \(version)."
        }
    }
}
