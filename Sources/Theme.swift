import AppKit

/// Centralized color constants. Switches between dark and light palettes based on Settings.shared.
enum Theme {
    // MARK: - Surface hierarchy (darkest to lightest)

    static var surface0: NSColor {
        Settings.shared.isDark
            ? NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)   // #0a0a0a
            : NSColor(white: 1.0, alpha: 1)                                // white
    }

    static var surface1: NSColor {
        Settings.shared.isDark
            ? NSColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1)   // #141414
            : NSColor(white: 0.96, alpha: 1)                               // #f5f5f5
    }

    static var surface2: NSColor {
        Settings.shared.isDark
            ? NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)   // #1a1a1a
            : NSColor(white: 0.93, alpha: 1)                               // #ededed
    }

    static var surface3: NSColor {
        Settings.shared.isDark
            ? NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)   // #2a2a2a
            : NSColor(white: 0.88, alpha: 1)                               // #e0e0e0
    }

    // MARK: - Accent

    static let accent = NSColor(red: 0.231, green: 0.51, blue: 0.965, alpha: 1)  // #3b82f6

    // MARK: - Text

    static var textPrimary: NSColor {
        Settings.shared.isDark
            ? NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1)   // #d4d4d4
            : NSColor(white: 0.13, alpha: 1)                               // #212121
    }

    static var textSecondary: NSColor {
        Settings.shared.isDark
            ? NSColor(white: 0.6, alpha: 1)
            : NSColor(white: 0.4, alpha: 1)
    }

    static var textTertiary: NSColor {
        Settings.shared.isDark
            ? NSColor(white: 0.5, alpha: 1)
            : NSColor(white: 0.45, alpha: 1)
    }

    static var textDimmed: NSColor {
        Settings.shared.isDark
            ? NSColor(white: 0.35, alpha: 1)
            : NSColor(white: 0.6, alpha: 1)
    }

    // MARK: - Waveform

    static var waveformBar: NSColor {
        Settings.shared.isDark
            ? NSColor(white: 0.23, alpha: 1)    // #3a3a3a
            : NSColor(white: 0.7, alpha: 1)
    }

    static var waveformCursor: NSColor { accent }

    // MARK: - Divider

    static var divider: NSColor {
        Settings.shared.isDark
            ? NSColor(white: 0.15, alpha: 1)
            : NSColor(white: 0.82, alpha: 1)
    }

    // MARK: - Error

    static let error = NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)       // #ef4444
    static let errorBackground = NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 0.1)

    // MARK: - Transcript word states

    static var wordNormal: NSColor { textPrimary }

    static var wordDeleted: NSColor {
        Settings.shared.isDark
            ? NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 0.35)
            : NSColor(white: 0.13, alpha: 0.35)
    }

    static var wordDeletedStrikethrough: NSColor { error }

    static var wordSelectedBackground: NSColor { accent.withAlphaComponent(0.3) }

    static var wordHighlightBackground: NSColor {
        Settings.shared.highlightColor.withAlphaComponent(0.2)
    }

    // MARK: - Silence tokens

    static var silenceText: NSColor {
        Settings.shared.isDark
            ? NSColor(white: 0.4, alpha: 1)
            : NSColor(white: 0.55, alpha: 1)
    }
}
