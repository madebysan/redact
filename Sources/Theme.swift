import AppKit

/// Centralized color constants matching the Electron app's Tailwind config.
enum Theme {
    // Surface hierarchy (darkest to lightest)
    static let surface0 = NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)  // #0a0a0a
    static let surface1 = NSColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1)  // #141414
    static let surface2 = NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)  // #1a1a1a
    static let surface3 = NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)  // #2a2a2a

    // Accent
    static let accent = NSColor(red: 0.231, green: 0.51, blue: 0.965, alpha: 1)     // #3b82f6

    // Text
    static let textPrimary = NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1)  // #d4d4d4
    static let textSecondary = NSColor(white: 0.6, alpha: 1)
    static let textTertiary = NSColor(white: 0.5, alpha: 1)
    static let textDimmed = NSColor(white: 0.35, alpha: 1)

    // Waveform
    static let waveformBar = NSColor(white: 0.23, alpha: 1)        // #3a3a3a
    static let waveformCursor = accent

    // Divider
    static let divider = NSColor(white: 0.15, alpha: 1)

    // Error
    static let error = NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)  // #ef4444
    static let errorBackground = NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 0.1)

    // Transcript word states
    static let wordNormal = textPrimary
    static let wordDeleted = NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 0.35)
    static let wordDeletedStrikethrough = error
    static let wordSelectedBackground = accent.withAlphaComponent(0.3)
    static let wordHighlightBackground = accent.withAlphaComponent(0.2)

    // Silence tokens
    static let silenceText = NSColor(white: 0.4, alpha: 1)
}
