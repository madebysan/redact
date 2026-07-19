import Foundation

protocol MediaProcessing: Sendable {
    func getMediaInfo(
        filePath: String,
        operation: ProcessOperation
    ) async throws -> MediaInfo

    func extractAudio(
        from inputPath: String,
        outputPath: String,
        operation: ProcessOperation,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws

    func exportMedia(
        inputPath: String,
        outputPath: String,
        segments: [TimeRange],
        preset: ExportPreset,
        sourceInfo: MediaInfo,
        sourceIsUnchanged: Bool,
        quality: String?,
        speed: Double,
        enhanceAudio: Bool,
        operation: ProcessOperation,
        onProgress: (@Sendable (Double) -> Void)?,
        totalDuration: Double
    ) async throws
}

protocol ImportWorkflowProtocol: Sendable {
    func probeMedia(
        at sourceURL: URL,
        operation: ProcessOperation
    ) async throws -> MediaInfo

    func extractAudio(
        from sourceURL: URL,
        workspace: TemporaryWorkspace,
        operation: ProcessOperation,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> URL
}

struct ImportWorkflow: ImportWorkflowProtocol, Sendable {
    let mediaProcessor: any MediaProcessing

    func probeMedia(
        at sourceURL: URL,
        operation: ProcessOperation
    ) async throws -> MediaInfo {
        try await mediaProcessor.getMediaInfo(
            filePath: sourceURL.path,
            operation: operation
        )
    }

    func extractAudio(
        from sourceURL: URL,
        workspace: TemporaryWorkspace,
        operation: ProcessOperation,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws -> URL {
        let outputURL = try workspace.fileURL(named: "audio.wav")
        try await mediaProcessor.extractAudio(
            from: sourceURL.path,
            outputPath: outputURL.path,
            operation: operation,
            onProgress: onProgress
        )
        return outputURL
    }
}

struct ExportRequest: Sendable {
    let inputURL: URL
    let outputURL: URL
    let segments: [TimeRange]
    let preset: ExportPreset
    let sourceInfo: MediaInfo
    let sourceIsUnchanged: Bool
    let quality: String?
    let speed: Double
    let enhanceAudio: Bool
    let totalDuration: Double
}

protocol ExportWorkflowProtocol: Sendable {
    func export(
        _ request: ExportRequest,
        operation: ProcessOperation,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws
}

struct ExportWorkflow: ExportWorkflowProtocol, Sendable {
    let mediaProcessor: any MediaProcessing

    func export(
        _ request: ExportRequest,
        operation: ProcessOperation,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws {
        let temporaryURL = temporarySiblingURL(for: request.outputURL)
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: temporaryURL)
        defer { try? fileManager.removeItem(at: temporaryURL) }

        try await mediaProcessor.exportMedia(
            inputPath: request.inputURL.path,
            outputPath: temporaryURL.path,
            segments: request.segments,
            preset: request.preset,
            sourceInfo: request.sourceInfo,
            sourceIsUnchanged: request.sourceIsUnchanged,
            quality: request.quality,
            speed: request.speed,
            enhanceAudio: request.enhanceAudio,
            operation: operation,
            onProgress: onProgress,
            totalDuration: request.totalDuration
        )
        try Task.checkCancellation()

        if fileManager.fileExists(atPath: request.outputURL.path) {
            _ = try fileManager.replaceItemAt(
                request.outputURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: []
            )
        } else {
            try fileManager.moveItem(at: temporaryURL, to: request.outputURL)
        }
    }

    private func temporarySiblingURL(for destination: URL) -> URL {
        let extensionSuffix = destination.pathExtension.isEmpty
            ? ""
            : "." + destination.pathExtension
        let baseName = destination.deletingPathExtension().lastPathComponent
        let temporaryName = "." + baseName + ".redact-" + UUID().uuidString + extensionSuffix
        return destination.deletingLastPathComponent().appendingPathComponent(temporaryName)
    }
}

enum MediaImportError: LocalizedError {
    case missingAudioStream

    var errorDescription: String? {
        "This file has no audio stream to transcribe."
    }
}
