import Foundation

/// FFmpeg subprocess wrapper for audio extraction and video export.
class FFmpegService {
    private var currentProcess: Process?

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
            "-i", inputPath,
            "-vn",
            "-acodec", "pcm_s16le",
            "-ar", "16000",
            "-ac", "1",
            "-y",
            outputPath,
        ]

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        currentProcess = process

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

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = FileHandle.nullDevice

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

        let fadeSec = 0.12

        var videoFilters: [String] = []
        var audioFilters: [String] = []
        var concatInputs: [String] = []

        for (i, seg) in segments.enumerated() {
            let segDur = seg.end - seg.start

            videoFilters.append("[0:v]trim=start=\(seg.start):end=\(seg.end),setpts=PTS-STARTPTS[v\(i)]")

            let fadeOut = max(0, segDur - fadeSec)
            var audioChain = "[0:a]atrim=start=\(seg.start):end=\(seg.end),asetpts=PTS-STARTPTS"
            if i > 0 {
                audioChain += ",afade=t=in:d=\(fadeSec)"
            }
            if i < segments.count - 1 {
                audioChain += ",afade=t=out:st=\(fadeOut):d=\(fadeSec)"
            }
            audioChain += "[a\(i)]"
            audioFilters.append(audioChain)

            concatInputs.append("[v\(i)][a\(i)]")
        }

        let n = segments.count
        let useSpeed = speed != 1.0

        var concatOut: String
        if useSpeed {
            concatOut = "\(concatInputs.joined())concat=n=\(n):v=1:a=1[cv][ca];[cv]setpts=PTS/\(speed)[outv];[ca]atempo=\(speed)[outa]"
        } else {
            concatOut = "\(concatInputs.joined())concat=n=\(n):v=1:a=1[outv][outa]"
        }

        let filterGraph = (videoFilters + audioFilters + [concatOut]).joined(separator: ";")

        var args: [String] = [
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

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = FileHandle.nullDevice

        currentProcess = process

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
