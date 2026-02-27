import Foundation

/// Whisper transcription subprocess wrapper.
/// Spawns python3 with whisper-transcribe.py, parses progress from stderr, collects JSON from stdout.
class WhisperService {
    private var currentProcess: Process?

    /// Transcribe an audio file using Whisper.
    func transcribe(
        audioPath: String,
        model: String? = nil,
        onProgress: @escaping (TranscribeProgress) -> Void
    ) async throws -> RawTranscript {
        let model = model ?? Settings.shared.whisperModel
        // Find Python — prefer venv, fall back to system
        let pythonPath: String
        if let venv = PathUtilities.findVenv() {
            pythonPath = venv + "/bin/python3"
        } else if let system = PathUtilities.findPython3() {
            pythonPath = system
        } else {
            throw WhisperError.pythonNotFound
        }

        // Find the whisper script — bundled in app resources
        let scriptPath: String
        if let bundled = Bundle.main.path(forResource: "whisper-transcribe", ofType: "py") {
            scriptPath = bundled
        } else {
            // Fallback: check known locations
            let candidates = [
                NSHomeDirectory() + "/Projects/Redact-Swift/scripts/whisper-transcribe.py",
                NSHomeDirectory() + "/Projects/redact/scripts/whisper-transcribe.py",
            ]
            scriptPath = candidates.first { FileManager.default.fileExists(atPath: $0) }
                ?? "whisper-transcribe.py"
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["--file", audioPath, "--model", model]

        // If using venv python, the script is passed as first arg
        process.arguments = [scriptPath, "--file", audioPath, "--model", model]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        currentProcess = process

        return try await withCheckedThrowingContinuation { continuation in
            var stdoutData = Data()

            // Read stderr for progress updates
            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }

                // Parse progress messages line by line
                for line in text.split(separator: "\n") {
                    let msg = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !msg.isEmpty else { continue }

                    if msg.contains("Loading model") {
                        onProgress(TranscribeProgress(status: .loadingModel, message: msg))
                    } else if msg.contains("Transcribing") {
                        onProgress(TranscribeProgress(status: .transcribing, message: msg))
                    } else if msg.contains("Refining") {
                        onProgress(TranscribeProgress(status: .refining, message: msg))
                    } else if msg.contains("complete") {
                        onProgress(TranscribeProgress(status: .complete, message: msg))
                    } else if let percentRange = msg.range(of: "\\d+%", options: .regularExpression) {
                        let percentStr = msg[percentRange].dropLast() // Remove %
                        let percent = Int(percentStr) ?? 0
                        onProgress(TranscribeProgress(status: .transcribing, progress: percent, message: msg))
                    }
                }
            }

            // Collect stdout
            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if !data.isEmpty {
                    stdoutData.append(data)
                }
            }

            process.terminationHandler = { [weak self] proc in
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                self?.currentProcess = nil

                if proc.terminationStatus == 15 || proc.terminationStatus == 9 {
                    continuation.resume(throwing: WhisperError.cancelled)
                    return
                }

                if proc.terminationStatus != 0 {
                    continuation.resume(throwing: WhisperError.transcriptionFailed(proc.terminationStatus))
                    return
                }

                // Parse JSON from stdout — find first '{' to skip any preamble
                let output = String(data: stdoutData, encoding: .utf8) ?? ""
                guard let jsonStart = output.firstIndex(of: "{") else {
                    continuation.resume(throwing: WhisperError.invalidOutput)
                    return
                }

                let jsonStr = String(output[jsonStart...])
                guard let jsonData = jsonStr.data(using: .utf8) else {
                    continuation.resume(throwing: WhisperError.invalidOutput)
                    return
                }

                do {
                    let transcript = try JSONDecoder().decode(RawTranscript.self, from: jsonData)
                    continuation.resume(returning: transcript)
                } catch {
                    continuation.resume(throwing: WhisperError.parseFailed(error.localizedDescription))
                }
            }

            do {
                try process.run()
            } catch {
                currentProcess = nil
                continuation.resume(throwing: WhisperError.launchFailed(error.localizedDescription))
            }
        }
    }

    /// Cancel the running transcription.
    func cancel() {
        currentProcess?.terminate()
        currentProcess = nil
    }
}

enum WhisperError: LocalizedError, Equatable {
    static func == (lhs: WhisperError, rhs: WhisperError) -> Bool {
        switch (lhs, rhs) {
        case (.cancelled, .cancelled): return true
        case (.pythonNotFound, .pythonNotFound): return true
        case (.scriptNotFound, .scriptNotFound): return true
        case (.invalidOutput, .invalidOutput): return true
        default: return false
        }
    }

    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }

    case pythonNotFound
    case scriptNotFound
    case launchFailed(String)
    case transcriptionFailed(Int32)
    case cancelled
    case invalidOutput
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonNotFound:
            return "Python 3 not found. Install it via Homebrew: brew install python3"
        case .scriptNotFound:
            return "Whisper transcription script not found"
        case .launchFailed(let msg):
            return "Failed to launch transcription: \(msg)"
        case .transcriptionFailed(let code):
            return "Transcription failed (exit code \(code))"
        case .cancelled:
            return "Transcription cancelled"
        case .invalidOutput:
            return "Transcription produced invalid output"
        case .parseFailed(let msg):
            return "Failed to parse transcript: \(msg)"
        }
    }
}
