import AppKit
import Testing
@testable import Redact

/// Renders each sheet offscreen into REDACT_UI_CAPTURE_DIR for visual review.
@Test @MainActor func captureSheetsWhenRequested() throws {
    guard let outputPath = ProcessInfo.processInfo.environment["REDACT_UI_CAPTURE_DIR"] else { return }
    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let suggestions = [
        TranscriptCleanupSuggestion(id: "a", kind: .fillerWords, wordIDs: ["w1"], changeDescription: "Remove “um,”",
                                    context: "… spoken audio, and, [um,] why …", startTime: 6, removedDuration: 0.4),
        TranscriptCleanupSuggestion(id: "b", kind: .fillerWords, wordIDs: ["w2"], changeDescription: "Remove “Um,”",
                                    context: "… dropping markers. [Um,] it is …", startTime: 38, removedDuration: 0.3),
        TranscriptCleanupSuggestion(id: "c", kind: .repeatedWords, wordIDs: ["w3"], changeDescription: "Keep one “that is”",
                                    context: "… [that is,] that is a lot …", startTime: 16, removedDuration: 0.5),
    ]
    let sheets: [(String, NSView)] = [
        ("p4-cleanup", CleanupReviewView(frame: NSRect(x: 0, y: 0, width: 700, height: 520), suggestions: suggestions)),
        ("p4-agent", AgentPreparationView(frame: NSRect(x: 0, y: 0, width: 540, height: 280))),
        ("p2-export-final", ExportSheetView(frame: NSRect(x: 0, y: 0, width: 520, height: 430), presets: [.mp4Video])),
    ]
    for (name, view) in sheets {
        let window = NSWindow(contentRect: view.bounds, styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: outputURL.appendingPathComponent("\(name).png"))
    }
}
