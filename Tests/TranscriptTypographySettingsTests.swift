import AppKit
import Foundation
import Testing
@testable import Redact

@Test func transcriptFontOptionsUseDistinctAvailableMacOSFamilies() {
    let options = Settings.transcriptFontOptions

    #expect(options.count == 14)
    #expect(Set(options.map(\.label)).count == options.count)
    #expect(Set(options.map(\.fontFamily)).count == options.count)
    #expect(options.first == Settings.TranscriptFontOption(label: "SF Pro", fontFamily: "System"))
    #expect(options.allSatisfy { option in
        option.fontFamily == "System" || NSFont(name: option.fontFamily, size: 15) != nil
    })
}

@Test func transcriptTypographyUsesTheApprovedDefaults() throws {
    let suiteName = "redact-transcript-defaults-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = Settings(defaults: defaults)

    #expect(settings.transcriptFontFamily == "Avenir Next")
    #expect(settings.transcriptFontSize == 15)
    #expect(settings.transcriptLetterSpacing == -0.2)
    #expect(settings.transcriptLineSpacing == 4)
    #expect(settings.whisperModel == "openai_whisper-small")
}

@Test func restoringTranscriptDefaultsLeavesPlaybackAndModelPreferencesAlone() throws {
    let suiteName = "redact-restore-transcript-defaults-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = Settings(defaults: defaults)
    settings.transcriptFontFamily = "Menlo"
    settings.transcriptFontSize = 22
    settings.transcriptLetterSpacing = 1
    settings.transcriptLineSpacing = 18
    settings.highlightColor = .systemOrange
    settings.whisperModel = "openai_whisper-medium"
    settings.playbackVolume = 0.4
    settings.playbackMuted = true

    settings.restoreTranscriptDefaults()

    #expect(settings.transcriptFontFamily == Settings.defaultTranscriptFontFamily)
    #expect(settings.transcriptFontSize == Settings.defaultTranscriptFontSize)
    #expect(settings.transcriptLetterSpacing == Settings.defaultTranscriptLetterSpacing)
    #expect(settings.transcriptLineSpacing == Settings.defaultTranscriptLineSpacing)
    #expect(settings.whisperModel == "openai_whisper-medium")
    #expect(settings.playbackVolume == 0.4)
    #expect(settings.playbackMuted)
}

@Test func transcriptFontSelectionDoesNotResetIndependentSpacingControls() throws {
    let suiteName = "redact-transcript-fonts-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = Settings(defaults: defaults)
    settings.transcriptFontSize = 19
    settings.transcriptLetterSpacing = 0.5
    settings.transcriptLineSpacing = 14

    for option in Settings.transcriptFontOptions {
        settings.transcriptFontFamily = option.fontFamily

        #expect(settings.transcriptFontFamily == option.fontFamily)
        #expect(settings.transcriptFontSize == 19)
        #expect(settings.transcriptLetterSpacing == 0.5)
        #expect(settings.transcriptLineSpacing == 14)
    }
}

@Test func transcriptTypographyValuesStayWithinReadableBounds() throws {
    let suiteName = "redact-transcript-typography-bounds-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let settings = Settings(defaults: defaults)

    settings.transcriptFontSize = 100
    settings.transcriptLetterSpacing = -10
    settings.transcriptLineSpacing = 100

    #expect(settings.transcriptFontSize == 24)
    #expect(settings.transcriptLetterSpacing == -0.5)
    #expect(settings.transcriptLineSpacing == 18)
}
