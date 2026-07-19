import AppKit
import Testing
@testable import Redact

@Test @MainActor func exportSheetStartsKeyboardNavigationAtFormatControl() throws {
    let sheet = ExportSheetView(
        frame: NSRect(x: 0, y: 0, width: 520, height: 400),
        presets: [.mp4Video]
    )
    let window = NSWindow(contentRect: sheet.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = sheet

    #expect(sheet.focusInitialControl(in: window))
    let focusedView = try #require(window.firstResponder as? NSView)
    #expect(focusedView.accessibilityLabel() == "Export format")
}

@Test @MainActor func completedExportFocusesADefaultDoneAction() throws {
    let sheet = ExportSheetView(
        frame: NSRect(x: 0, y: 0, width: 520, height: 400),
        presets: [.mp4Video]
    )
    let window = NSWindow(contentRect: sheet.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = sheet

    sheet.showProgressMode(status: "Exporting video...")
    sheet.showComplete()

    let doneButton = try #require(
        sheet.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Done" }
    )
    #expect(window.firstResponder === doneButton)
    #expect(doneButton.keyEquivalent == "\r")
}

@Test @MainActor func exportSheetDefaultsToUnmodifiedAudioAndExplainsEnhancement() throws {
    let sheet = ExportSheetView(
        frame: NSRect(x: 0, y: 0, width: 520, height: 400),
        presets: [.mp4Video]
    )

    #expect(!sheet.isAudioEnhancementEnabled)
    #expect(!sheet.isSubtitleExportEnabled)
    #expect(sheet.subviews.contains { $0.accessibilityLabel() == "Enhance audio" })
    #expect(sheet.subviews.contains { view in
        (view as? NSTextField)?.stringValue.contains("background noise") == true
    })
    let qualityPopup = try #require(
        sheet.subviews.compactMap { $0 as? NSPopUpButton }
            .first { $0.accessibilityLabel() == "Export quality" }
    )
    #expect(qualityPopup.itemTitle(at: 0) == "Same as source")

    var submittedEnhancementValue: Bool?
    sheet.onExport = { _, _, _, enhanceAudio, _ in
        submittedEnhancementValue = enhanceAudio
    }
    let exportButton = try #require(
        sheet.subviews
            .compactMap { $0 as? NSButton }
            .first { $0.title == "Export Video" }
    )
    exportButton.performClick(nil)

    #expect(submittedEnhancementValue == false)
}

@Test @MainActor func exportSheetExplainsOutputCodecAndHEVCConversionRisk() throws {
    let sourceInfo = MediaInfo(
        duration: 60,
        containerNames: ["mov", "mp4"],
        streams: [
            MediaStreamInfo(
                index: 0,
                kind: .video,
                codecName: "hevc",
                width: 1920,
                height: 1080,
                averageFrameRate: 24,
                realFrameRate: 24
            ),
            MediaStreamInfo(
                index: 1,
                kind: .audio,
                codecName: "aac",
                sampleRate: 48_000,
                channels: 2
            ),
        ]
    )
    let sheet = ExportSheetView(
        frame: NSRect(x: 0, y: 0, width: 520, height: 400),
        presets: [.mp4Video],
        sourceInfo: sourceInfo
    )

    let presentation = sheet.subviews
        .compactMap { $0 as? NSTextField }
        .map(\.stringValue)
        .joined(separator: " ")
    #expect(presentation.contains("Output: H.264 video + AAC audio"))
    #expect(presentation.contains("HEVC source will be converted to H.264"))
    #expect(presentation.contains("export may be larger"))
}

@Test @MainActor func exportSheetSummarizesAndRemembersTheChosenExport() throws {
    let suiteName = "redact-export-preferences-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = Settings(defaults: defaults)
    settings.exportPresetID = ExportPreset.mp4Video.id
    settings.exportQuality = "720p"
    settings.exportSpeed = 1.5
    settings.exportEnhanceAudio = true
    settings.exportSubtitles = true
    let sourceInfo = MediaInfo(
        duration: 300,
        containerNames: ["mov"],
        streams: [
            MediaStreamInfo(
                index: 0,
                kind: .video,
                codecName: "h264",
                width: 1920,
                height: 1080,
                averageFrameRate: 30,
                realFrameRate: 30
            ),
            MediaStreamInfo(
                index: 1,
                kind: .audio,
                codecName: "aac",
                sampleRate: 48_000,
                channels: 2
            ),
        ]
    )
    let sheet = ExportSheetView(
        frame: NSRect(x: 0, y: 0, width: 520, height: 400),
        presets: [.mp4Video, .m4aAudio],
        sourceInfo: sourceInfo,
        finalDuration: 240,
        canExportSubtitles: true,
        settings: settings
    )

    #expect(sheet.exportSummaryText == "MP4 · 720p · 1.5x · 02:40 final")
    #expect(sheet.isAudioEnhancementEnabled)
    #expect(sheet.isSubtitleExportEnabled)

    var submitted: (String, String?, Double, Bool, Bool)?
    sheet.onExport = { preset, quality, speed, enhanceAudio, subtitles in
        submitted = (preset.id, quality, speed, enhanceAudio, subtitles)
    }
    let exportButton = try #require(
        sheet.subviews.compactMap { $0 as? NSButton }
            .first { $0.title == "Export Video" }
    )
    exportButton.performClick(nil)

    #expect(submitted?.0 == ExportPreset.mp4Video.id)
    #expect(submitted?.1 == "720p")
    #expect(submitted?.2 == 1.5)
    #expect(submitted?.3 == true)
    #expect(submitted?.4 == true)
    #expect(settings.exportPresetID == ExportPreset.mp4Video.id)
    #expect(settings.exportQuality == "720p")
    #expect(settings.exportSpeed == 1.5)
    #expect(settings.exportEnhanceAudio)
    #expect(settings.exportSubtitles)
}

@Test @MainActor func exportSheetReportsElapsedTimeAndEstimatedRemainingTime() throws {
    var uptime = 100.0
    let sheet = ExportSheetView(
        frame: NSRect(x: 0, y: 0, width: 520, height: 400),
        presets: [.mp4Video]
    )
    sheet.progressClock = { uptime }

    sheet.showProgressMode(status: "Preparing export...")
    uptime = 110
    sheet.updateProgress(25)

    let progressText = try #require(
        sheet.subviews
            .compactMap { $0 as? NSTextField }
            .first { $0.stringValue.contains("25%") }
    )
    let progressIndicator = try #require(
        sheet.subviews.compactMap { $0 as? NSProgressIndicator }.first
    )
    #expect(progressText.stringValue == "25% · 00:10 elapsed · ~00:30 remaining")
    #expect(!progressIndicator.isIndeterminate)
    #expect(progressIndicator.doubleValue == 25)

    uptime = 120
    sheet.showComplete()
    #expect(progressText.stringValue == "100% · 00:20 elapsed")
}

@Test @MainActor func exportSheetNamesConfigurationAndProgressControlsForVoiceOver() {
    let sheet = ExportSheetView(
        frame: NSRect(x: 0, y: 0, width: 520, height: 400),
        presets: [.mp4Video]
    )
    let optionLabels = Set(sheet.subviews.compactMap { $0.accessibilityLabel() })
    #expect(optionLabels.contains("Export format"))
    #expect(optionLabels.contains("Export quality"))
    #expect(optionLabels.contains("Export speed"))
    #expect(optionLabels.contains("Enhance audio"))
    #expect(optionLabels.contains("Also export subtitles"))
    #expect(optionLabels.contains("Export summary"))

    sheet.showProgressMode(status: "Preparing export...")
    let progressLabels = Set(sheet.subviews.compactMap { $0.accessibilityLabel() })
    #expect(progressLabels.contains("Export progress"))
    #expect(progressLabels.contains("Export timing"))
}

@Test @MainActor func captureExportSheetWhenRequested() throws {
    guard let outputPath = ProcessInfo.processInfo.environment["REDACT_UI_CAPTURE_DIR"] else {
        return
    }

    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    let application = NSApplication.shared
    let originalAppearance = application.appearance
    defer { application.appearance = originalAppearance }
    let appearanceValue = ProcessInfo.processInfo.environment["REDACT_UI_APPEARANCE"] ?? "dark"
    let appearanceName: NSAppearance.Name = appearanceValue == "light" ? .aqua : .darkAqua
    application.appearance = NSAppearance(named: appearanceName)
    let sourceInfo = MediaInfo(
        duration: 60,
        containerNames: ["mov", "mp4"],
        streams: [
            MediaStreamInfo(
                index: 0,
                kind: .video,
                codecName: "hevc",
                width: 1920,
                height: 1080,
                averageFrameRate: 24,
                realFrameRate: 24
            ),
            MediaStreamInfo(
                index: 1,
                kind: .audio,
                codecName: "aac",
                sampleRate: 48_000,
                channels: 2
            ),
        ]
    )
    let sheet = ExportSheetView(
        frame: NSRect(x: 0, y: 0, width: 520, height: 400),
        presets: ExportCatalog.videoPresets + ExportCatalog.audioPresets,
        sourceInfo: sourceInfo,
        finalDuration: 240
    )
    let captureWindow = NSWindow(
        contentRect: sheet.bounds,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    captureWindow.contentView = sheet
    captureWindow.orderFrontRegardless()
    defer { captureWindow.close() }
    sheet.layoutSubtreeIfNeeded()

    guard let representation = sheet.bitmapImageRepForCachingDisplay(in: sheet.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    sheet.cacheDisplay(in: sheet.bounds, to: representation)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: outputURL.appendingPathComponent("export-sheet-\(appearanceValue).png"))

    var uptime = 100.0
    sheet.progressClock = { uptime }
    sheet.showProgressMode(status: "Exporting video...")
    uptime = 110
    sheet.updateProgress(25)
    sheet.layoutSubtreeIfNeeded()
    sheet.displayIfNeeded()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    guard let progressRepresentation = sheet.bitmapImageRepForCachingDisplay(in: sheet.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    sheet.cacheDisplay(in: sheet.bounds, to: progressRepresentation)
    guard let progressData = progressRepresentation.representation(
        using: .png,
        properties: [:]
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try progressData.write(
        to: outputURL.appendingPathComponent("export-progress-\(appearanceValue).png")
    )
}
