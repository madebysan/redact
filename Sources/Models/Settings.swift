import AppKit

extension Notification.Name {
    static let settingsChanged = Notification.Name("com.redact.settingsChanged")
}

/// UserDefaults-backed app settings singleton.
class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    // MARK: - Keys

    private enum Key {
        static let theme = "theme"
        static let transcriptFontSize = "transcriptFontSize"
        static let transcriptFontFamily = "transcriptFontFamily"
        static let highlightColor = "highlightColor"
        static let whisperModel = "whisperModel"
        static let crossfadeMs = "crossfadeMs"
        static let elevenLabsApiKey = "elevenLabsApiKey"
        static let elevenLabsVoiceSource = "elevenLabsVoiceSource"
        static let elevenLabsVoiceId = "elevenLabsVoiceId"
        static let elevenLabsCustomVoiceId = "elevenLabsCustomVoiceId"
    }

    // MARK: - Theme

    /// "dark", "light", or "system"
    var theme: String {
        get { defaults.string(forKey: Key.theme) ?? "dark" }
        set {
            defaults.set(newValue, forKey: Key.theme)
            applyAppearance()
            notifyChanged()
        }
    }

    // MARK: - Transcript Font Size

    var transcriptFontSize: CGFloat {
        get {
            let value = defaults.double(forKey: Key.transcriptFontSize)
            return value > 0 ? CGFloat(value) : 15.0
        }
        set {
            defaults.set(Double(newValue), forKey: Key.transcriptFontSize)
            notifyChanged()
        }
    }

    // MARK: - Transcript Font Family

    /// Font family name, or "System" for the default system font.
    var transcriptFontFamily: String {
        get { defaults.string(forKey: Key.transcriptFontFamily) ?? "System" }
        set {
            defaults.set(newValue, forKey: Key.transcriptFontFamily)
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

    // MARK: - Highlight Color

    var highlightColor: NSColor {
        get {
            if let data = defaults.data(forKey: Key.highlightColor),
               let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                return color
            }
            // Default: blue #3b82f6
            return NSColor(red: 0.231, green: 0.51, blue: 0.965, alpha: 1)
        }
        set {
            if let data = try? NSKeyedArchiver.archivedData(withRootObject: newValue, requiringSecureCoding: true) {
                defaults.set(data, forKey: Key.highlightColor)
            }
            notifyChanged()
        }
    }

    // MARK: - Whisper Model

    /// Available whisper models: name, description, approximate size.
    struct WhisperModelInfo {
        let id: String
        let label: String
        let size: String
    }

    static let availableModels: [WhisperModelInfo] = [
        WhisperModelInfo(id: "openai_whisper-tiny", label: "Tiny", size: "~40 MB"),
        WhisperModelInfo(id: "openai_whisper-tiny.en", label: "Tiny (English)", size: "~40 MB"),
        WhisperModelInfo(id: "openai_whisper-base", label: "Base", size: "~80 MB"),
        WhisperModelInfo(id: "openai_whisper-base.en", label: "Base (English)", size: "~80 MB"),
        WhisperModelInfo(id: "openai_whisper-small", label: "Small", size: "~250 MB"),
        WhisperModelInfo(id: "openai_whisper-small.en", label: "Small (English)", size: "~250 MB"),
        WhisperModelInfo(id: "openai_whisper-medium", label: "Medium", size: "~800 MB"),
        WhisperModelInfo(id: "openai_whisper-medium.en", label: "Medium (English)", size: "~800 MB"),
        WhisperModelInfo(id: "openai_whisper-large-v3", label: "Large v3", size: "~1.6 GB"),
        WhisperModelInfo(id: "openai_whisper-large-v3-turbo", label: "Large v3 Turbo", size: "~900 MB"),
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

    // MARK: - Crossfade Duration

    /// Audio crossfade duration in milliseconds (10–500ms, default 200ms).
    var crossfadeMs: Double {
        get {
            let value = defaults.double(forKey: Key.crossfadeMs)
            return value > 0 ? value : 200
        }
        set {
            defaults.set(newValue, forKey: Key.crossfadeMs)
            notifyChanged()
        }
    }

    /// Crossfade duration in seconds (for PlaybackController).
    var crossfadeSec: Double { crossfadeMs / 1000.0 }

    // MARK: - ElevenLabs Voice

    /// ElevenLabs API key (stored in UserDefaults, not Keychain — personal local app).
    var elevenLabsApiKey: String {
        get { defaults.string(forKey: Key.elevenLabsApiKey) ?? "" }
        set {
            defaults.set(newValue, forKey: Key.elevenLabsApiKey)
            notifyChanged()
        }
    }

    /// Voice source: "popular" or "custom".
    var elevenLabsVoiceSource: String {
        get { defaults.string(forKey: Key.elevenLabsVoiceSource) ?? "popular" }
        set {
            defaults.set(newValue, forKey: Key.elevenLabsVoiceSource)
            notifyChanged()
        }
    }

    /// Selected voice ID from the popular voices list.
    var elevenLabsVoiceId: String {
        get { defaults.string(forKey: Key.elevenLabsVoiceId) ?? "EXAVITQu4vr4xnSDxMaL" }
        set {
            defaults.set(newValue, forKey: Key.elevenLabsVoiceId)
            notifyChanged()
        }
    }

    /// Custom voice ID entered manually.
    var elevenLabsCustomVoiceId: String {
        get { defaults.string(forKey: Key.elevenLabsCustomVoiceId) ?? "" }
        set {
            defaults.set(newValue, forKey: Key.elevenLabsCustomVoiceId)
            notifyChanged()
        }
    }

    /// Curated popular voices for the picker.
    struct ElevenLabsVoice {
        let id: String
        let name: String
        let description: String
    }

    static let popularVoices: [ElevenLabsVoice] = [
        ElevenLabsVoice(id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", description: "Soft female"),
        ElevenLabsVoice(id: "21m00Tcm4TlvDq8ikWAM", name: "Rachel", description: "Calm female"),
        ElevenLabsVoice(id: "pNInz6obpgDQGcFmaJgB", name: "Adam", description: "Deep male"),
        ElevenLabsVoice(id: "ErXwobaYiN019PkySvjV", name: "Antoni", description: "Well-rounded male"),
        ElevenLabsVoice(id: "TxGEqnHWrfWFTfGW9XjX", name: "Josh", description: "Young male"),
        ElevenLabsVoice(id: "VR6AewLTigWG4xSOukaG", name: "Arnold", description: "Crisp male"),
    ]

    /// Returns the effective voice ID based on source setting.
    var effectiveVoiceId: String {
        if elevenLabsVoiceSource == "custom" {
            return elevenLabsCustomVoiceId
        }
        return elevenLabsVoiceId
    }

    // MARK: - Appearance

    /// Apply the saved theme to NSApp.appearance.
    func applyAppearance() {
        switch theme {
        case "light":
            NSApp.appearance = NSAppearance(named: .aqua)
        case "system":
            NSApp.appearance = nil
        default:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Whether the current effective appearance is dark.
    var isDark: Bool {
        let appearance = NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: - Private

    private func notifyChanged() {
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }
}
