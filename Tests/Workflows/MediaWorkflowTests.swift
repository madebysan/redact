import Foundation
import Testing
@testable import Redact

private enum StubMediaError: Error {
    case failed
}

private enum StubExportOutcome {
    case success
    case failure
    case cancellation
}

private final class StubMediaProcessor: MediaProcessing, @unchecked Sendable {
    let exportOutcome: StubExportOutcome
    private(set) var exportOutputPaths: [String] = []
    private(set) var audioEnhancementValues: [Bool] = []

    init(exportOutcome: StubExportOutcome = .success) {
        self.exportOutcome = exportOutcome
    }

    func getMediaInfo(
        filePath: String,
        operation: ProcessOperation
    ) async throws -> MediaInfo {
        MediaInfo(
            duration: 1,
            containerNames: ["mov"],
            streams: [
                MediaStreamInfo(index: 0, kind: .video, codecName: "h264"),
                MediaStreamInfo(index: 1, kind: .audio, codecName: "aac"),
            ]
        )
    }

    func extractAudio(
        from inputPath: String,
        outputPath: String,
        operation: ProcessOperation,
        onProgress: (@Sendable (String) -> Void)?
    ) async throws {
        try Data("audio".utf8).write(to: URL(fileURLWithPath: outputPath))
    }

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
    ) async throws {
        exportOutputPaths.append(outputPath)
        audioEnhancementValues.append(enhanceAudio)
        try Data("new export".utf8).write(to: URL(fileURLWithPath: outputPath))
        switch exportOutcome {
        case .success:
            return
        case .failure:
            throw StubMediaError.failed
        case .cancellation:
            throw CancellationError()
        }
    }
}

@Test func importWorkflowWritesAudioInsideItsSessionWorkspace() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-import-workflow-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let workspace = try TemporaryWorkspace.create(in: root)
    let workflow = ImportWorkflow(mediaProcessor: StubMediaProcessor())

    let outputURL = try await workflow.extractAudio(
        from: URL(fileURLWithPath: "/source.mov"),
        workspace: workspace,
        operation: ProcessOperation(),
        onProgress: nil
    )

    #expect(outputURL == workspace.url.appendingPathComponent("audio.wav"))
    #expect(FileManager.default.fileExists(atPath: outputURL.path))
}

@Test func importWorkflowReturnsTypedMediaProbe() async throws {
    let workflow = ImportWorkflow(mediaProcessor: StubMediaProcessor())

    let info = try await workflow.probeMedia(
        at: URL(fileURLWithPath: "/source.mov"),
        operation: ProcessOperation()
    )

    #expect(info.hasVideo)
    #expect(info.hasAudio)
    #expect(info.videoStream?.codecName == "h264")
    #expect(info.audioStream?.codecName == "aac")
}

@Test func exportWorkflowReplacesDestinationOnlyAfterSuccessfulRender() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-export-workflow-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent("result.mp4")
    try Data("old export".utf8).write(to: destination)
    let processor = StubMediaProcessor()
    let workflow = ExportWorkflow(mediaProcessor: processor)
    let request = ExportRequest(
        inputURL: URL(fileURLWithPath: "/source.mov"),
        outputURL: destination,
        segments: [TimeRange(start: 0, end: 1)],
        preset: .mp4Video,
        sourceInfo: stubMediaInfo(),
        sourceIsUnchanged: false,
        quality: nil,
        speed: 1,
        enhanceAudio: true,
        totalDuration: 1
    )

    try await workflow.export(
        request,
        operation: ProcessOperation(),
        onProgress: nil
    )

    #expect(try String(contentsOf: destination, encoding: .utf8) == "new export")
    #expect(processor.exportOutputPaths.first != destination.path)
    #expect(processor.audioEnhancementValues == [true])
    #expect(try temporaryExportFiles(in: directory).isEmpty)
}

@Test func failedExportPreservesDestinationAndRemovesPartialSibling() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-export-workflow-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent("result.mp4")
    try Data("safe original".utf8).write(to: destination)
    let workflow = ExportWorkflow(mediaProcessor: StubMediaProcessor(exportOutcome: .failure))
    let request = ExportRequest(
        inputURL: URL(fileURLWithPath: "/source.mov"),
        outputURL: destination,
        segments: [TimeRange(start: 0, end: 1)],
        preset: .mp4Video,
        sourceInfo: stubMediaInfo(),
        sourceIsUnchanged: false,
        quality: nil,
        speed: 1,
        enhanceAudio: false,
        totalDuration: 1
    )

    await #expect(throws: StubMediaError.self) {
        try await workflow.export(
            request,
            operation: ProcessOperation(),
            onProgress: nil
        )
    }

    #expect(try String(contentsOf: destination, encoding: .utf8) == "safe original")
    #expect(try temporaryExportFiles(in: directory).isEmpty)
}

@Test func cancelledExportPreservesDestinationAndRemovesPartialSibling() async throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("redact-export-workflow-" + UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let destination = directory.appendingPathComponent("result.mp4")
    try Data("safe original".utf8).write(to: destination)
    let workflow = ExportWorkflow(mediaProcessor: StubMediaProcessor(exportOutcome: .cancellation))
    let request = ExportRequest(
        inputURL: URL(fileURLWithPath: "/source.mov"),
        outputURL: destination,
        segments: [TimeRange(start: 0, end: 1)],
        preset: .mp4Video,
        sourceInfo: stubMediaInfo(),
        sourceIsUnchanged: false,
        quality: nil,
        speed: 1,
        enhanceAudio: false,
        totalDuration: 1
    )

    await #expect(throws: CancellationError.self) {
        try await workflow.export(
            request,
            operation: ProcessOperation(),
            onProgress: nil
        )
    }

    #expect(try String(contentsOf: destination, encoding: .utf8) == "safe original")
    #expect(try temporaryExportFiles(in: directory).isEmpty)
}

private func stubMediaInfo() -> MediaInfo {
    MediaInfo(
        duration: 1,
        containerNames: ["mov"],
        streams: [
            MediaStreamInfo(index: 0, kind: .video, codecName: "h264"),
            MediaStreamInfo(index: 1, kind: .audio, codecName: "aac"),
        ]
    )
}

private func temporaryExportFiles(in directory: URL) throws -> [URL] {
    try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: nil
    ).filter { $0.lastPathComponent.contains(".redact-") }
}
