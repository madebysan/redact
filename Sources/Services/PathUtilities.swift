import Foundation

/// Utility for finding external tool paths and managing temp directories.
enum PathUtilities {
    /// Temp directory for intermediate files (audio extraction, etc.)
    static var tempDir: String {
        let path = "/tmp/redact"
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    /// Find FFmpeg binary. Checks Homebrew paths first, then falls back to `which`.
    static func findFFmpeg() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Fallback: use `which` to find it in PATH
        return findInPath("ffmpeg")
    }

    /// Find FFprobe binary.
    static func findFFprobe() -> String? {
        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return findInPath("ffprobe")
    }

    /// Find python3 binary.
    static func findPython3() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]

        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        return findInPath("python3")
    }

    /// Find the Python venv from the Electron project (reuse existing packages).
    static func findVenv() -> String? {
        let candidates = [
            NSHomeDirectory() + "/Projects/redact/.venv",
        ]

        for path in candidates {
            let pythonPath = path + "/bin/python3"
            if FileManager.default.isExecutableFile(atPath: pythonPath) {
                return path
            }
        }

        return nil
    }

    /// Clean up temp directory.
    static func cleanTempDir() {
        try? FileManager.default.removeItem(atPath: tempDir)
    }

    /// Use `which` to find a binary in PATH.
    private static func findInPath(_ binary: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [binary]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let path, !path.isEmpty {
                    return path
                }
            }
        } catch {
            // Silently fail — binary not found
        }

        return nil
    }
}
