import Foundation
import os.log

private let logger = Logger(subsystem: "com.redact.app", category: "FFmpeg")

/// FFmpeg subprocess wrapper for audio extraction and video export.
class FFmpegService {
    private var currentProcess: Process?

    /// Common setup for all FFmpeg/FFprobe processes: redirect stdin to /dev/null.
    private func configureProcess(_ process: Process) {
        process.standardInput = FileHandle.nullDevice
    }

    /// Extract audio from a video file as 16kHz mono WAV (for Whisper).
    func extractAudio(from inputPath: String, onProgress: ((String) -> Void)? = nil) async throws -> String {
        guard let ffmpeg = PathUtilities.findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }

        let outputPath = PathUtilities.tempDir + "/audio.wav"

        // Remove existing file if present
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

        currentProcess = process
        logger.info("extractAudio: starting — input=\(inputPath) output=\(outputPath)")

        return try await withCheckedThrowingContinuation { continuation in
            // Read stderr for progress in background
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    // Parse FFmpeg progress: look for "time=HH:MM:SS.ms"
                    if let range = text.range(of: "time=\\d{2}:\\d{2}:\\d{2}\\.\\d+", options: .regularExpression) {
                        onProgress?(String(text[range]))
                    }
                }
            }

            process.terminationHandler = { [weak self] proc in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                self?.currentProcess = nil
                logger.info("extractAudio: finished with exit code \(proc.terminationStatus)")

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: outputPath)
                } else if proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                    continuation.resume(throwing: FFmpegError.cancelled)
                } else {
                    continuation.resume(throwing: FFmpegError.extractionFailed(proc.terminationStatus))
                }
            }

            do {
                try process.run()
                logger.info("extractAudio: process launched (pid \(process.processIdentifier))")
            } catch {
                currentProcess = nil
                logger.error("extractAudio: launch failed — \(error.localizedDescription)")
                continuation.resume(throwing: FFmpegError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Get media info using ffprobe.
    func getMediaInfo(filePath: String) async throws -> MediaInfo {
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

        logger.info("getMediaInfo: probing \(filePath)")

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { proc in
                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

                if proc.terminationStatus != 0 {
                    continuation.resume(throwing: FFmpegError.probeError)
                    return
                }

                do {
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    let format = json?["format"] as? [String: Any]
                    let durationStr = format?["duration"] as? String
                    let duration = durationStr.flatMap(Double.init) ?? 0

                    let streams = json?["streams"] as? [[String: Any]] ?? []
                    let hasVideo = streams.contains { ($0["codec_type"] as? String) == "video" }
                    let hasAudio = streams.contains { ($0["codec_type"] as? String) == "audio" }

                    continuation.resume(returning: MediaInfo(
                        duration: duration,
                        hasVideo: hasVideo,
                        hasAudio: hasAudio
                    ))
                } catch {
                    continuation.resume(throwing: FFmpegError.probeError)
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: FFmpegError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Export video with kept segments, using filter graph for frame-accurate cuts.
    func exportVideo(
        inputPath: String,
        outputPath: String,
        segments: [TimeRange],
        format: String = "mp4",
        quality: String? = nil,
        speed: Double = 1.0,
        onProgress: ((Double) -> Void)? = nil,
        totalDuration: Double = 0
    ) async throws {
        guard let ffmpeg = PathUtilities.findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }

        guard !segments.isEmpty else {
            throw FFmpegError.noSegments
        }

        let n = segments.count
        let segDurations = segments.map { $0.end - $0.start }
        let minSegDur = segDurations.min() ?? 0

        // Use the user's crossfade setting, clamped to 40% of shortest segment
        let crossfadeSec = Settings.shared.crossfadeSec
        let xf = min(crossfadeSec, minSegDur * 0.4)
        let useSpeed = speed != 1.0

        var filterParts: [String] = []

        // Trim all segments
        for (i, seg) in segments.enumerated() {
            let s = String(format: "%.4f", seg.start)
            let e = String(format: "%.4f", seg.end)
            filterParts.append("[0:v]trim=start=\(s):end=\(e),setpts=PTS-STARTPTS[v\(i)]")
            filterParts.append("[0:a]atrim=start=\(s):end=\(e),asetpts=PTS-STARTPTS[a\(i)]")
        }

        if n == 1 {
            // Single segment — passthrough or speed adjust
            if useSpeed {
                filterParts.append("[v0]setpts=PTS/\(speed)[outv]")
                filterParts.append("[a0]atempo=\(speed)[outa]")
            } else {
                filterParts.append("[v0]null[outv]")
                filterParts.append("[a0]anull[outa]")
            }
        } else if xf >= 0.01 {
            // Chain xfade for video (true dissolve overlap)
            let xfStr = String(format: "%.4f", xf)
            var prevVideo = "v0"
            var runningDur = segDurations[0]
            for i in 1..<n {
                let offset = String(format: "%.4f", max(0, runningDur - xf))
                let isLast = i == n - 1
                let label = isLast ? (useSpeed ? "cv" : "outv") : "vx\(i)"
                filterParts.append("[\(prevVideo)][v\(i)]xfade=transition=fade:duration=\(xfStr):offset=\(offset)[\(label)]")
                prevVideo = label
                runningDur += segDurations[i] - xf
            }

            // Chain acrossfade for audio (true audio overlap)
            var prevAudio = "a0"
            for i in 1..<n {
                let isLast = i == n - 1
                let label = isLast ? (useSpeed ? "ca" : "outa") : "ax\(i)"
                filterParts.append("[\(prevAudio)][a\(i)]acrossfade=d=\(xfStr):c1=tri:c2=tri[\(label)]")
                prevAudio = label
            }

            if useSpeed {
                filterParts.append("[cv]setpts=PTS/\(speed)[outv]")
                filterParts.append("[ca]atempo=\(speed)[outa]")
            }
        } else {
            // Crossfade too small — fall back to hard concat
            let inputs = (0..<n).map { "[v\($0)][a\($0)]" }.joined()
            if useSpeed {
                filterParts.append("\(inputs)concat=n=\(n):v=1:a=1[cv][ca]")
                filterParts.append("[cv]setpts=PTS/\(speed)[outv]")
                filterParts.append("[ca]atempo=\(speed)[outa]")
            } else {
                filterParts.append("\(inputs)concat=n=\(n):v=1:a=1[outv][outa]")
            }
        }

        let filterGraph = filterParts.joined(separator: ";")

        var args: [String] = [
            "-nostdin",
            "-i", inputPath,
            "-filter_complex", filterGraph,
            "-map", "[outv]",
            "-map", "[outa]",
        ]

        // Video encoding settings
        if quality == "1080p" {
            args += ["-vf", "scale=-2:1080"]
        } else if quality == "720p" {
            args += ["-vf", "scale=-2:720"]
        }
        args += ["-c:v", "libx264", "-preset", "fast", "-crf", "18"]
        args += ["-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart"]
        args += ["-y", outputPath]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = args
        configureProcess(process)

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        currentProcess = process
        logger.info("exportVideo: starting — \(segments.count) segments, format=\(format)")

        return try await withCheckedThrowingContinuation { continuation in
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    // Parse "time=HH:MM:SS.ms" for progress
                    if let range = text.range(of: "time=(\\d{2}):(\\d{2}):(\\d{2})\\.(\\d+)", options: .regularExpression) {
                        let timeStr = text[range].dropFirst(5) // Remove "time="
                        let parts = timeStr.split(separator: ":")
                        if parts.count >= 3 {
                            let h = Double(parts[0]) ?? 0
                            let m = Double(parts[1]) ?? 0
                            let sAndMs = parts[2].split(separator: ".")
                            let s = Double(sAndMs[0]) ?? 0
                            let ms = sAndMs.count > 1 ? (Double(sAndMs[1]) ?? 0) / 100.0 : 0
                            let currentTime = h * 3600 + m * 60 + s + ms
                            if totalDuration > 0 {
                                let percent = min(100, (currentTime / totalDuration) * 100)
                                onProgress?(percent)
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { [weak self] proc in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                self?.currentProcess = nil

                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else if proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                    continuation.resume(throwing: FFmpegError.cancelled)
                } else {
                    continuation.resume(throwing: FFmpegError.exportFailed(proc.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                currentProcess = nil
                continuation.resume(throwing: FFmpegError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Extract audio from a video file as 44.1kHz mono WAV (for ElevenLabs STS).
    func extractAudioForSTS(from inputPath: String) async throws -> String {
        guard let ffmpeg = PathUtilities.findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }

        let outputPath = PathUtilities.tempDir + "/temp_audio.wav"
        try? FileManager.default.removeItem(atPath: outputPath)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-nostdin",
            "-i", inputPath,
            "-vn",
            "-acodec", "pcm_s16le",
            "-ar", "44100",
            "-ac", "1",
            "-y",
            outputPath,
        ]
        configureProcess(process)

        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        currentProcess = process
        logger.info("extractAudioForSTS: starting — input=\(inputPath)")

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { [weak self] proc in
                self?.currentProcess = nil
                logger.info("extractAudioForSTS: finished with exit code \(proc.terminationStatus)")
                if proc.terminationStatus == 0 {
                    continuation.resume(returning: outputPath)
                } else if proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                    continuation.resume(throwing: FFmpegError.cancelled)
                } else {
                    continuation.resume(throwing: FFmpegError.extractionFailed(proc.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                currentProcess = nil
                continuation.resume(throwing: FFmpegError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Replace the audio track in a video with a different audio file.
    /// Copies the video stream (no re-encoding) and maps the new audio.
    func replaceAudio(
        videoPath: String,
        audioPath: String,
        outputPath: String,
        onProgress: ((Double) -> Void)? = nil,
        totalDuration: Double = 0
    ) async throws {
        guard let ffmpeg = PathUtilities.findFFmpeg() else {
            throw FFmpegError.ffmpegNotFound
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpeg)
        process.arguments = [
            "-nostdin",
            "-i", videoPath,
            "-i", audioPath,
            "-c:v", "copy",
            "-map", "0:v:0",
            "-map", "1:a:0",
            "-shortest",
            "-y",
            outputPath,
        ]
        configureProcess(process)

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        currentProcess = process
        logger.info("replaceAudio: starting — video=\(videoPath) audio=\(audioPath)")

        return try await withCheckedThrowingContinuation { continuation in
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                    if let range = text.range(of: "time=(\\d{2}):(\\d{2}):(\\d{2})\\.(\\d+)", options: .regularExpression) {
                        let timeStr = text[range].dropFirst(5)
                        let parts = timeStr.split(separator: ":")
                        if parts.count >= 3 {
                            let h = Double(parts[0]) ?? 0
                            let m = Double(parts[1]) ?? 0
                            let sAndMs = parts[2].split(separator: ".")
                            let s = Double(sAndMs[0]) ?? 0
                            let ms = sAndMs.count > 1 ? (Double(sAndMs[1]) ?? 0) / 100.0 : 0
                            let currentTime = h * 3600 + m * 60 + s + ms
                            if totalDuration > 0 {
                                let percent = min(100, (currentTime / totalDuration) * 100)
                                onProgress?(percent)
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { [weak self] proc in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                self?.currentProcess = nil

                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else if proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                    continuation.resume(throwing: FFmpegError.cancelled)
                } else {
                    continuation.resume(throwing: FFmpegError.exportFailed(proc.terminationStatus))
                }
            }

            do {
                try process.run()
            } catch {
                currentProcess = nil
                continuation.resume(throwing: FFmpegError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Cancel any running FFmpeg process.
    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }
}

// MARK: - Types

struct MediaInfo {
    let duration: Double
    let hasVideo: Bool
    let hasAudio: Bool
}

enum FFmpegError: LocalizedError {
    case ffmpegNotFound
    case extractionFailed(Int32)
    case exportFailed(Int32)
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
        case .exportFailed(let code):
            return "Video export failed (exit code \(code))"
        case .launchFailed(let msg):
            return "Failed to launch FFmpeg: \(msg)"
        case .cancelled:
            return "Operation cancelled"
        case .probeError:
            return "Failed to read media info"
        case .noSegments:
            return "No segments to export"
        }
    }
}
