import AppKit
import Foundation
import UniformTypeIdentifiers

final class RedactDocument: NSDocument {
    static let typeIdentifier = "com.santiagoalonso.redact.project"

    let project = ProjectDocument()
    private(set) var mediaReference: ProjectMediaReference?
    private var loadedProjectFile: ProjectFile?
    private var serializationProjectURL: URL?

    override init() {
        super.init()
        fileType = Self.typeIdentifier
    }

    override class var autosavesInPlace: Bool {
        true
    }

    @MainActor override func makeWindowControllers() {
        let controller = MainWindowController(project: project, document: self)
        addWindowController(controller)

        if let loadedProjectFile, let fileURL {
            controller.installLoadedProject(loadedProjectFile, projectURL: fileURL)
        }
    }

    override func data(ofType typeName: String) throws -> Data {
        guard let transcript = project.sourceTranscript else {
            throw RedactDocumentError.transcriptUnavailable
        }

        let currentMediaReference: ProjectMediaReference
        if let filePath = project.filePath,
           !filePath.isEmpty,
           FileManager.default.fileExists(atPath: filePath) {
            currentMediaReference = try ProjectMediaReference.make(
                mediaURL: URL(fileURLWithPath: filePath),
                projectURL: serializationProjectURL ?? fileURL
            )
        } else if let mediaReference {
            currentMediaReference = mediaReference
        } else {
            throw RedactDocumentError.mediaUnavailable
        }
        mediaReference = currentMediaReference

        let projectFile = ProjectFile(
            media: currentMediaReference,
            transcript: transcript,
            edits: project.editDecisionList,
            segmentStartWordIDs: project.segments.compactMap { $0.words.first?.id }
        )
        return try ProjectFileCodec.encode(projectFile)
    }

    override func read(from data: Data, ofType typeName: String) throws {
        let projectFile = try ProjectFileCodec.decode(data)
        loadedProjectFile = projectFile
        mediaReference = projectFile.media
    }

    func load(from url: URL) throws {
        fileURL = url
        fileType = Self.typeIdentifier
        fileModificationDate = try url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
        try read(from: Data(contentsOf: url), ofType: Self.typeIdentifier)
    }

    override func save(
        to url: URL,
        ofType typeName: String,
        for saveOperation: NSDocument.SaveOperationType,
        completionHandler: @escaping (Error?) -> Void
    ) {
        serializationProjectURL = url
        super.save(
            to: url,
            ofType: typeName,
            for: saveOperation
        ) { [weak self] error in
            self?.serializationProjectURL = nil
            completionHandler(error)
        }
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        if let projectType = UTType(filenameExtension: "rdt") {
            savePanel.allowedContentTypes = [projectType]
        }
        savePanel.nameFieldStringValue = fileURL?.lastPathComponent ?? "project.rdt"
        return true
    }

    func setSourceMediaURL(_ url: URL) {
        project.filePath = url.path
        mediaReference = nil
    }

    func setResolvedMediaURL(_ url: URL) {
        project.filePath = url.path
        if let fileURL {
            mediaReference = try? ProjectMediaReference.make(
                mediaURL: url,
                projectURL: fileURL
            )
        }
    }
}

enum RedactDocumentError: LocalizedError {
    case transcriptUnavailable
    case mediaUnavailable

    var errorDescription: String? {
        switch self {
        case .transcriptUnavailable:
            "The transcript is not ready to save."
        case .mediaUnavailable:
            "The source media reference is unavailable."
        }
    }
}
