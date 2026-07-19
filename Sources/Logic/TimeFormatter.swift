import Foundation

/// Format seconds as "MM:SS" for transport bar display.
func formatTime(_ seconds: Double) -> String {
    let totalSeconds = Int(seconds)
    let mins = totalSeconds / 60
    let secs = totalSeconds % 60
    return String(format: "%02d:%02d", mins, secs)
}

/// Format seconds as "H:MM:SS" (if >1h) or "MM:SS.mmm" (if <1h).
func formatTimeFull(_ seconds: Double) -> String {
    let hrs = Int(seconds) / 3600
    let mins = (Int(seconds) % 3600) / 60
    let secs = Int(seconds) % 60
    let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 1000)

    if hrs > 0 {
        return String(format: "%d:%02d:%02d", hrs, mins, secs)
    }
    return String(format: "%02d:%02d.%03d", mins, secs, ms)
}

/// Format seconds as SRT timestamp "HH:MM:SS,mmm".
func formatSrtTime(_ seconds: Double) -> String {
    let totalMilliseconds = Int((max(0, seconds) * 1000).rounded())
    let hrs = totalMilliseconds / 3_600_000
    let mins = (totalMilliseconds % 3_600_000) / 60_000
    let secs = (totalMilliseconds % 60_000) / 1000
    let ms = totalMilliseconds % 1000
    return String(format: "%02d:%02d:%02d,%03d", hrs, mins, secs, ms)
}
