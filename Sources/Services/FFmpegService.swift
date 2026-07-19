import Foundation
import os.log

private let logger = Logger(subsystem: "com.redact.app", category: "FFmpeg")

private final class ProcessOutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let maximumBytes: Int

    init(maximumBytes: Int = 8_192) {
        self.maximumBytes = maximumBytes
    }

    func append(_ newData: Data) {
        guard !newData.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        data.append(newData)
        if data.count > maximumBytes {
            data = data.suffix(maximumBytes)
        }
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        let decoded = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded
            .split(separator: "\n")
            .suffix(6)
            .map { String($0.suffix(500)) }
            .joined(separator: "\n")
    }
}

/// Stateless FFmpeg subprocess wrapper. Each call owns a separate
/// `ProcessOperation`, so cancelling one operation cannot terminate another.
final class FFmpegService: MediaProcessing, @unchecked Sendable {
    private func configureProcess(_ process: Process) {
        process.standardInput = FileHandle.nullDevice
    }

    func extractAudio(
        from inputPath: String,
        outputPath: String,
        operation: ProcessOperation,
        onProgress: (@Sendable (String) -> Void)? = nil
    ) async throws {
        guard let ffmpeg = PathUtilities.findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }

        try? FileManager.default.removeItem(atPath: outputPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-nostdin",
            "-i", inputPath,
            "-vn",
            "-acodec", "pcm_s16le",
            "-ar", "16000",
            "-ac", "1",
            "-y",
            outputPath,
        ]
        configureProcess(process)

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        logger.info("extractAudio: starting")

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty,
                       let text = String(data: data, encoding: .utf8),
                       let range = text.range(
                           of: "time=\\d{2}:\\d{2}:\\d{2}\\.\\d+",
                           options: .regularExpression
                       ) {
                        onProgress?(String(text[range]))
                    }
                }

                process.terminationHandler = { completedProcess in
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    operation.clear(completedProcess)
                    logger.info(
                        "extractAudio: finished with exit code \(completedProcess.terminationStatus)"
                    )

                    if completedProcess.terminationStatus == 0 {
                        continuation.resume()
                    } else if Self.wasCancelled(completedProcess) || operation.isCancelled {
                        continuation.resume(throwing: FFmpegError.cancelled)
                    } else {
                        continuation.resume(
                            throwing: FFmpegError.extractionFailed(completedProcess.terminationStatus)
                        )
                    }
                }

                do {
                    guard try operation.launch(process) else {
                        continuation.resume(throwing: FFmpegError.cancelled)
                        return
                    }
                    logger.info("extractAudio: process launched")
                } catch {
                    operation.clear(process)
                    continuation.resume(
                        throwing: FFmpegError.launchFailed(error.localizedDescription)
                    )
                }
            }
        } onCancel: {
            operation.cancel()
        }
    }

    func getMediaInfo(
        filePath: String,
        operation: ProcessOperation = ProcessOperation()
    ) async throws -> MediaInfo {
        guard let ffprobe = PathUtilities.findFFprobe() else {
            throw FFmpegError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            "-show_streams",
            filePath,
        ]
        configureProcess(process)

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { completedProcess in
                    operation.clear(completedProcess)
                    let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

                    guard completedProcess.terminationStatus == 0 else {
                        let error: FFmpegError = Self.wasCancelled(completedProcess) || operation.isCancelled
                            ? .cancelled
                            : .probeError
                        continuation.resume(throwing: error)
                        return
                    }

                    do {
                        continuation.resume(returning: try MediaInfo.decodeFFprobeJSON(data))
                    } catch {
                        continuation.resume(throwing: FFmpegError.probeError)
                    }
                }

                do {
                    guard try operation.launch(process) else {
                        continuation.resume(throwing: FFmpegError.cancelled)
                        return
                    }
                } catch {
                    operation.clear(process)
                    continuation.resume(
                        throwing: FFmpegError.launchFailed(error.localizedDescription)
                    )
                }
            }
        } onCancel: {
            operation.cancel()
        }
    }

    func exportMedia(
        inputPath: String,
        outputPath: String,
        segments: [TimeRange],
        preset: ExportPreset,
        sourceInfo: MediaInfo,
        sourceIsUnchanged: Bool,
        quality: String? = nil,
        speed: Double = 1,
        enhanceAudio: Bool = false,
        operation: ProcessOperation,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        totalDuration: Double = 0
    ) async throws {
        guard let ffmpeg = PathUtilities.findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }
        guard !segments.isEmpty else {
            throw FFmpegError.noSegments
        }

        let plan = FFmpegExportPlan(
            inputPath: inputPath,
            outputPath: outputPath,
            segments: segments,
            preset: preset,
            quality: quality,
            speed: speed,
            enhanceAudio: enhanceAudio,
            sourceInfo: sourceInfo,
            sourceIsUnchanged: sourceIsUnchanged
        )

        if plan.strategy == .batchedSelectionTranscode {
            try await exportBatchedSelection(
                ffmpegPath: ffmpeg,
                inputPath: inputPath,
                outputPath: outputPath,
                segments: segments,
                preset: preset,
                sourceInfo: sourceInfo,
                quality: quality,
                speed: speed,
                enhanceAudio: enhanceAudio,
                operation: operation,
                onProgress: onProgress,
                totalDuration: totalDuration
            )
            return
        }

        try await executeFFmpeg(
            ffmpegPath: ffmpeg,
            arguments: plan.arguments,
            operation: operation,
            onProgress: onProgress,
            totalDuration: totalDuration
        )
    }

    private func exportBatchedSelection(
        ffmpegPath: String,
        inputPath: String,
        outputPath: String,
        segments: [TimeRange],
        preset: ExportPreset,
        sourceInfo: MediaInfo,
        quality: String?,
        speed: Double,
        enhanceAudio: Bool,
        operation: ProcessOperation,
        onProgress: (@Sendable (Double) -> Void)?,
        totalDuration: Double
    ) async throws {
        let workspaceRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("redact-export-batches", isDirectory: true)
        let workspace = try TemporaryWorkspace.create(in: workspaceRoot)
        defer { try? workspace.cleanup() }

        let measuredDuration = segments.reduce(0) { $0 + $1.duration }
        let overallDuration = totalDuration > 0 ? totalDuration : measuredDuration
        var completedDuration = 0.0
        var batchArtifacts: [(url: URL, duration: Double)] = []

        let maximumBatchSize = FFmpegExportPlan.selectionFilterMaximumRangeCount
        let batchTotal = (segments.count + maximumBatchSize - 1) / maximumBatchSize
        let baseBatchSize = segments.count / batchTotal
        let largerBatchCount = segments.count % batchTotal
        let intermediatePreset = ExportPreset(
            id: "batch-intermediate",
            title: "Private batch intermediate",
            pathExtension: "mkv",
            mediaKind: .video,
            videoCodec: preset.videoCodec,
            audioCodec: "pcm_s16le"
        )
        var batchStart = 0
        for batchIndex in 0..<batchTotal {
            guard !Task.isCancelled, !operation.isCancelled else {
                throw FFmpegError.cancelled
            }
            let batchCount = baseBatchSize + (batchIndex < largerBatchCount ? 1 : 0)
            let batchEnd = batchStart + batchCount
            let batch = Array(segments[batchStart..<batchEnd])
            guard let first = batch.first, let last = batch.last else {
                throw FFmpegError.noSegments
            }

            let sourceOffset = first.start
            let inputDuration = last.end - sourceOffset
            let sourceBatchDuration = batch.reduce(0) { $0 + $1.duration }
            let batchDuration = sourceBatchDuration / speed
            let batchURL = try workspace.fileURL(
                named: "batch-\(batchArtifacts.count).mkv"
            )
            let batchPlan = FFmpegExportPlan(
                inputPath: inputPath,
                outputPath: batchURL.path,
                segments: batch,
                preset: intermediatePreset,
                quality: quality,
                speed: speed,
                enhanceAudio: false,
                sourceInfo: sourceInfo,
                sourceIsUnchanged: false,
                inputSeek: sourceOffset,
                inputDuration: inputDuration
            )
            guard batchPlan.strategy == .selectionFilterTranscode else {
                throw FFmpegError.exportFailed(1, "Could not create a bounded export batch")
            }

            let completedBeforeBatch = completedDuration
            try await executeFFmpeg(
                ffmpegPath: ffmpegPath,
                arguments: batchPlan.arguments,
                operation: operation,
                onProgress: { progress in
                    guard overallDuration > 0 else { return }
                    let completed = completedBeforeBatch + batchDuration * progress / 100
                    onProgress?(min(100, completed / overallDuration * 100))
                },
                totalDuration: batchDuration
            )
            completedDuration += batchDuration
            batchArtifacts.append((url: batchURL, duration: batchDuration))
            batchStart = batchEnd
        }

        let manifestURL = try workspace.fileURL(named: "concat.txt")
        let manifest = batchArtifacts
            .map {
                "file '\($0.url.path)'\nduration \(String(format: "%.6f", $0.duration))"
            }
            .joined(separator: "\n") + "\n"
        try Data(manifest.utf8).write(to: manifestURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: manifestURL.path
        )

        let concatArguments = Self.batchedConcatArguments(
            manifestPath: manifestURL.path,
            outputPath: outputPath,
            preset: preset,
            enhanceAudio: enhanceAudio,
            expectedDuration: overallDuration
        )
        try await executeFFmpeg(
            ffmpegPath: ffmpegPath,
            arguments: concatArguments,
            operation: operation,
            onProgress: nil,
            totalDuration: 0
        )
        onProgress?(100)
    }

    static func batchedConcatArguments(
        manifestPath: String,
        outputPath: String,
        preset: ExportPreset,
        enhanceAudio: Bool,
        expectedDuration: Double
    ) -> [String] {
        var arguments = [
            "-nostdin",
            "-f", "concat",
            "-safe", "0",
            "-i", manifestPath,
            "-c:v", "copy",
            "-c:a", preset.audioCodec,
        ]
        if enhanceAudio {
            arguments += ["-af", FFmpegExportPlan.lightAudioEnhancementFilter]
        }
        if preset.audioCodec != "pcm_s16le" {
            arguments += ["-b:a", "192k"]
        }
        if preset.pathExtension == "mp4" || preset.pathExtension == "m4a" {
            arguments += ["-movflags", "+faststart"]
        }
        arguments += ["-t", String(format: "%.6f", expectedDuration)]
        arguments += ["-y", outputPath]
        return arguments
    }

    private func executeFFmpeg(
        ffmpegPath: String,
        arguments: [String],
        operation: ProcessOperation,
        onProgress: (@Sendable (Double) -> Void)?,
        totalDuration: Double
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = arguments
        configureProcess(process)

        let stderrPipe = Pipe()
        let errorBuffer = ProcessOutputBuffer()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        logger.info("exportMedia: starting FFmpeg process")

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    errorBuffer.append(data)
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8),
                          let time = Self.parseProgressTime(text),
                          totalDuration > 0 else {
                        return
                    }
                    onProgress?(min(100, (time / totalDuration) * 100))
                }

                process.terminationHandler = { completedProcess in
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    errorBuffer.append(stderrPipe.fileHandleForReading.readDataToEndOfFile())
                    operation.clear(completedProcess)

                    if completedProcess.terminationStatus == 0 {
                        continuation.resume()
                    } else if Self.wasCancelled(completedProcess) || operation.isCancelled {
                        continuation.resume(throwing: FFmpegError.cancelled)
                    } else {
                        continuation.resume(
                            throwing: FFmpegError.exportFailed(
                                completedProcess.terminationStatus,
                                errorBuffer.text
                            )
                        )
                    }
                }

                do {
                    guard try operation.launch(process) else {
                        continuation.resume(throwing: FFmpegError.cancelled)
                        return
                    }
                } catch {
                    operation.clear(process)
                    continuation.resume(
                        throwing: FFmpegError.launchFailed(error.localizedDescription)
                    )
                }
            }
        } onCancel: {
            operation.cancel()
        }
    }

    private static func wasCancelled(_ process: Process) -> Bool {
        process.terminationStatus == 15 || process.terminationStatus == 9
    }

    private static func parseProgressTime(_ text: String) -> Double? {
        guard let range = text.range(
            of: "time=(\\d{2}):(\\d{2}):(\\d{2})\\.(\\d+)",
            options: .regularExpression
        ) else {
            return nil
        }

        let components = text[range].dropFirst(5).split(separator: ":")
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1]) else {
            return nil
        }

        let secondComponents = components[2].split(separator: ".", maxSplits: 1)
        guard let seconds = secondComponents.first.flatMap({ Double($0) }) else {
            return nil
        }
        let fraction = secondComponents.count == 2
            ? Double("0." + secondComponents[1]) ?? 0
            : 0
        return hours * 3600 + minutes * 60 + seconds + fraction
    }
}

enum FFmpegError: LocalizedError, Equatable {
    case ffmpegNotFound
    case extractionFailed(Int32)
    case exportFailed(Int32, String)
    case launchFailed(String)
    case cancelled
    case probeError
    case noSegments

    var errorDescription: String? {
        switch self {
        case .ffmpegNotFound:
            return "FFmpeg not found. Install it via Homebrew: brew install ffmpeg"
        case .extractionFailed(let code):
            return "Audio extraction failed (exit code \(code))"
        case .exportFailed(let code, let details):
            let suffix = details.isEmpty ? "" : "\n\n" + details
            return "Media export failed (exit code \(code))" + suffix
        case .launchFailed(let message):
            return "Failed to launch FFmpeg: \(message)"
        case .cancelled:
            return "Operation cancelled"
        case .probeError:
            return "Failed to read media info"
        case .noSegments:
            return "No segments to export"
        }
    }
}
