import AppKit

extension Notification.Name {
    static let settingsChanged = Notification.Name("com.redact.settingsChanged")
}

/// UserDefaults-backed app settings singleton.
class Settings {
    static let shared = Settings()

    static let defaultTranscriptFontSize: CGFloat = 15
    static let defaultTranscriptFontFamily = "Avenir Next"
    static let defaultTranscriptLetterSpacing: CGFloat = -0.2
    static let defaultTranscriptLineSpacing: CGFloat = 4
    static let defaultHighlightColor = NSColor(
        red: 0.231,
        green: 0.51,
        blue: 0.965,
        alpha: 1
    )

    struct TranscriptFontOption: Equatable {
        let label: String
        let fontFamily: String
    }

    static let transcriptFontOptions: [TranscriptFontOption] = [
        TranscriptFontOption(label: "SF Pro", fontFamily: "System"),
        TranscriptFontOption(label: "American Typewriter", fontFamily: "American Typewriter"),
        TranscriptFontOption(label: "Avenir Next", fontFamily: "Avenir Next"),
        TranscriptFontOption(label: "Baskerville", fontFamily: "Baskerville"),
        TranscriptFontOption(label: "Charter", fontFamily: "Charter"),
        TranscriptFontOption(label: "Georgia", fontFamily: "Georgia"),
        TranscriptFontOption(label: "Gill Sans", fontFamily: "Gill Sans"),
        TranscriptFontOption(label: "Helvetica Neue", fontFamily: "Helvetica Neue"),
        TranscriptFontOption(label: "Hoefler Text", fontFamily: "Hoefler Text"),
        TranscriptFontOption(label: "Menlo", fontFamily: "Menlo"),
        TranscriptFontOption(label: "New York", fontFamily: "New York"),
        TranscriptFontOption(label: "Optima", fontFamily: "Optima"),
        TranscriptFontOption(label: "Palatino", fontFamily: "Palatino"),
        TranscriptFontOption(label: "Times New Roman", fontFamily: "Times New Roman"),
    ]

    private let defaults: UserDefaults

    // MARK: - Keys

    private enum Key {
        static let theme = "theme"
        static let transcriptFontSize = "transcriptFontSize"
        static let transcriptFontFamily = "transcriptFontFamily"
        static let transcriptLetterSpacing = "transcriptLetterSpacing"
        static let transcriptLineSpacing = "transcriptLineSpacing"
        static let highlightColor = "highlightColor"
        static let whisperModel = "whisperModel"
        static let playbackVolume = "playbackVolume"
        static let playbackMuted = "playbackMuted"
        static let exportPresetID = "exportPresetID"
        static let exportQuality = "exportQuality"
        static let exportSpeed = "exportSpeed"
        static let exportEnhanceAudio = "exportEnhanceAudio"
        static let exportSubtitles = "exportSubtitles"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        Self.removeRetiredCredentialValues(from: defaults)
        defaults.set("dark", forKey: Key.theme)
    }

    static func removeRetiredCredentialValues(from defaults: UserDefaults) {
        [
            "elevenLabsApiKey",
            "elevenLabsVoiceSource",
            "elevenLabsVoiceId",
            "elevenLabsCustomVoiceId",
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    // MARK: - Theme

    /// Compatibility surface retained while the old theme plumbing is phased out.
    var theme: String {
        get { "dark" }
        set {
            defaults.set("dark", forKey: Key.theme)
            applyAppearance()
            notifyChanged()
        }
    }

    // MARK: - Transcript Font Size

    var transcriptFontSize: CGFloat {
        get {
            let value = defaults.double(forKey: Key.transcriptFontSize)
            return Self.clamp(
                value > 0 ? CGFloat(value) : Self.defaultTranscriptFontSize,
                to: 10...24
            )
        }
        set {
            defaults.set(Double(Self.clamp(newValue, to: 10...24)), forKey: Key.transcriptFontSize)
            notifyChanged()
        }
    }

    // MARK: - Transcript Font Family

    /// Font family name, or "System" for the default system font.
    var transcriptFontFamily: String {
        get {
            let stored = defaults.string(forKey: Key.transcriptFontFamily)
                ?? Self.defaultTranscriptFontFamily
            return Self.transcriptFontOptions.contains(where: { $0.fontFamily == stored })
                ? stored
                : Self.defaultTranscriptFontFamily
        }
        set {
            let family = Self.transcriptFontOptions.contains(where: { $0.fontFamily == newValue })
                ? newValue
                : Self.defaultTranscriptFontFamily
            defaults.set(family, forKey: Key.transcriptFontFamily)
            notifyChanged()
        }
    }

    /// Returns the appropriate NSFont for the transcript at the given size.
    func transcriptFont(ofSize size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        if transcriptFontFamily == "System" {
            return NSFont.systemFont(ofSize: size, weight: weight)
        }
        return NSFont(name: transcriptFontFamily, size: size)
            ?? NSFont.systemFont(ofSize: size, weight: weight)
    }

    // MARK: - Transcript Typography

    var transcriptLetterSpacing: CGFloat {
        get {
            guard defaults.object(forKey: Key.transcriptLetterSpacing) != nil else {
                return Self.defaultTranscriptLetterSpacing
            }
            return Self.clamp(CGFloat(defaults.double(forKey: Key.transcriptLetterSpacing)), to: -0.5...1)
        }
        set {
            defaults.set(
                Double(Self.clamp(newValue, to: -0.5...1)),
                forKey: Key.transcriptLetterSpacing
            )
            notifyChanged()
        }
    }

    var transcriptLineSpacing: CGFloat {
        get {
            guard defaults.object(forKey: Key.transcriptLineSpacing) != nil else {
                return Self.defaultTranscriptLineSpacing
            }
            return Self.clamp(CGFloat(defaults.double(forKey: Key.transcriptLineSpacing)), to: 4...18)
        }
        set {
            defaults.set(
                Double(Self.clamp(newValue, to: 4...18)),
                forKey: Key.transcriptLineSpacing
            )
            notifyChanged()
        }
    }

    // MARK: - Highlight Color

    var highlightColor: NSColor {
        get {
            if let data = defaults.data(forKey: Key.highlightColor),
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                return color
            }
            return Self.defaultHighlightColor
        }
        set {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true) {
                defaults.set(data, forKey: Key.highlightColor)
            }
            notifyChanged()
        }
    }

    func restoreTranscriptDefaults() {
        defaults.set(Double(Self.defaultTranscriptFontSize), forKey: Key.transcriptFontSize)
        defaults.set(Self.defaultTranscriptFontFamily, forKey: Key.transcriptFontFamily)
        defaults.set(
            Double(Self.defaultTranscriptLetterSpacing),
            forKey: Key.transcriptLetterSpacing
        )
        defaults.set(
            Double(Self.defaultTranscriptLineSpacing),
            forKey: Key.transcriptLineSpacing
        )
        if let data = try? NSKeyedArchiver.archivedData(
            withRootObject: Self.defaultHighlightColor,
            requiringSecureCoding: true
        ) {
            defaults.set(data, forKey: Key.highlightColor)
        }
        notifyChanged()
    }

    // MARK: - Playback

    var playbackVolume: Float {
        get {
            guard defaults.object(forKey: Key.playbackVolume) != nil else { return 1 }
            return Float(Self.clamp(defaults.double(forKey: Key.playbackVolume), to: 0...1))
        }
        set {
            defaults.set(Self.clamp(Double(newValue), to: 0...1), forKey: Key.playbackVolume)
        }
    }

    var playbackMuted: Bool {
        get { defaults.bool(forKey: Key.playbackMuted) }
        set { defaults.set(newValue, forKey: Key.playbackMuted) }
    }

    // MARK: - Export

    var exportPresetID: String? {
        get { defaults.string(forKey: Key.exportPresetID) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.exportPresetID)
            } else {
                defaults.removeObject(forKey: Key.exportPresetID)
            }
        }
    }

    var exportQuality: String? {
        get {
            guard let value = defaults.string(forKey: Key.exportQuality),
                  ["1080p", "720p"].contains(value) else {
                return nil
            }
            return value
        }
        set {
            if let newValue, ["1080p", "720p"].contains(newValue) {
                defaults.set(newValue, forKey: Key.exportQuality)
            } else {
                defaults.removeObject(forKey: Key.exportQuality)
            }
        }
    }

    var exportSpeed: Double {
        get {
            let value = defaults.double(forKey: Key.exportSpeed)
            return [0.5, 0.75, 1, 1.25, 1.5, 2].contains(value) ? value : 1
        }
        set {
            let value = [0.5, 0.75, 1, 1.25, 1.5, 2].contains(newValue) ? newValue : 1
            defaults.set(value, forKey: Key.exportSpeed)
        }
    }

    var exportEnhanceAudio: Bool {
        get { defaults.bool(forKey: Key.exportEnhanceAudio) }
        set { defaults.set(newValue, forKey: Key.exportEnhanceAudio) }
    }

    var exportSubtitles: Bool {
        get { defaults.bool(forKey: Key.exportSubtitles) }
        set { defaults.set(newValue, forKey: Key.exportSubtitles) }
    }

    // MARK: - Whisper Model

    /// Available whisper models: name, description, approximate size.
    struct WhisperModelInfo {
        let id: String
        let label: String
        let size: String
        let isEnglishOnly: Bool
        let isRecommended: Bool

        var menuTitle: String {
            let language = isEnglishOnly ? "English only" : "Multilingual"
            let recommendation = isRecommended ? " · Recommended" : ""
            return "\(label) · \(language)\(recommendation) (\(size))"
        }
    }

    static let availableModels: [WhisperModelInfo] = [
        WhisperModelInfo(id: "openai_whisper-tiny", label: "Tiny", size: "~40 MB", isEnglishOnly: false, isRecommended: false),
        WhisperModelInfo(id: "openai_whisper-tiny.en", label: "Tiny", size: "~40 MB", isEnglishOnly: true, isRecommended: false),
        WhisperModelInfo(id: "openai_whisper-base", label: "Base", size: "~80 MB", isEnglishOnly: false, isRecommended: false),
        WhisperModelInfo(id: "openai_whisper-base.en", label: "Base", size: "~80 MB", isEnglishOnly: true, isRecommended: false),
        WhisperModelInfo(id: "openai_whisper-small", label: "Small", size: "~250 MB", isEnglishOnly: false, isRecommended: true),
        WhisperModelInfo(id: "openai_whisper-small.en", label: "Small", size: "~250 MB", isEnglishOnly: true, isRecommended: false),
        WhisperModelInfo(id: "openai_whisper-medium", label: "Medium", size: "~800 MB", isEnglishOnly: false, isRecommended: false),
        WhisperModelInfo(id: "openai_whisper-medium.en", label: "Medium", size: "~800 MB", isEnglishOnly: true, isRecommended: false),
        WhisperModelInfo(id: "openai_whisper-large-v3", label: "Large v3", size: "~1.6 GB", isEnglishOnly: false, isRecommended: false),
        WhisperModelInfo(id: "openai_whisper-large-v3-turbo", label: "Large v3 Turbo", size: "~900 MB", isEnglishOnly: false, isRecommended: false),
    ]

    /// Map legacy model IDs (from faster-whisper era) to WhisperKit variant names.
    private static let legacyModelMap: [String: String] = [
        "tiny": "openai_whisper-tiny",
        "base": "openai_whisper-base",
        "small": "openai_whisper-small",
        "medium": "openai_whisper-medium",
        "large-v3": "openai_whisper-large-v3",
    ]

    var whisperModel: String {
        get {
            let stored = defaults.string(forKey: Key.whisperModel) ?? "openai_whisper-small"
            // Migrate legacy model IDs from the Python/faster-whisper era
            if let mapped = Self.legacyModelMap[stored] {
                defaults.set(mapped, forKey: Key.whisperModel)
                return mapped
            }
            return stored
        }
        set {
            defaults.set(newValue, forKey: Key.whisperModel)
            notifyChanged()
        }
    }

    // MARK: - Appearance

    /// Redact currently supports Dark Aqua only.
    func applyAppearance() {
        defaults.set("dark", forKey: Key.theme)
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    /// Whether the current effective appearance is dark.
    var isDark: Bool {
        true
    }

    // MARK: - Private

    private func notifyChanged() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    private static func clamp(_ value: CGFloat, to range: ClosedRange<CGFloat>) -> CGFloat {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
