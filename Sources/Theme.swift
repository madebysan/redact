import AppKit

/// Centralized colors. Each non-static value is a dynamic NSColor that resolves
/// light/dark from the current view's effectiveAppearance, so AppKit handles
/// appearance switching natively. No NotificationCenter listener required for
/// regular NSColor properties (foregroundColor, contentTintColor, window.backgroundColor, etc.).
///
/// For CALayer-backed views that use `layer.backgroundColor = cgColor`, the layer
/// holds a snapshot — those views override `viewDidChangeEffectiveAppearance()`
/// to re-apply their background.
enum Theme {

    // MARK: - Surfaces (darkest to lightest)

    static let surface0 = dyn(
        light: NSColor(white: 1.0, alpha: 1),
        dark: NSColor(red: 0.039, green: 0.039, blue: 0.039, alpha: 1)
    )

    static let surface1 = dyn(
        light: NSColor(white: 0.96, alpha: 1),
        dark: NSColor(red: 0.078, green: 0.078, blue: 0.078, alpha: 1)
    )

    static let surface2 = dyn(
        light: NSColor(white: 0.93, alpha: 1),
        dark: NSColor(red: 0.102, green: 0.102, blue: 0.102, alpha: 1)
    )

    static let surface3 = dyn(
        light: NSColor(white: 0.88, alpha: 1),
        dark: NSColor(red: 0.165, green: 0.165, blue: 0.165, alpha: 1)
    )

    // MARK: - Accent / Error

    static let accent = NSColor(red: 0.231, green: 0.51, blue: 0.965, alpha: 1)  // #3b82f6
    static let error = NSColor(red: 0.937, green: 0.267, blue: 0.267, alpha: 1)  // #ef4444
    static let errorBackground = error.withAlphaComponent(0.1)

    // MARK: - Text

    static let textPrimary = dyn(
        light: NSColor(white: 0.13, alpha: 1),
        dark: NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 1)
    )

    static let textSecondary = dyn(
        light: NSColor(white: 0.4, alpha: 1),
        dark: NSColor(white: 0.6, alpha: 1)
    )

    static let textTertiary = dyn(
        light: NSColor(white: 0.45, alpha: 1),
        dark: NSColor(white: 0.5, alpha: 1)
    )

    static let textDimmed = dyn(
        light: NSColor(white: 0.6, alpha: 1),
        dark: NSColor(white: 0.35, alpha: 1)
    )

    // MARK: - Waveform

    static let waveformBar = dyn(
        light: NSColor(white: 0.7, alpha: 1),
        dark: NSColor(white: 0.23, alpha: 1)
    )

    static let waveformCursor = accent

    // MARK: - Divider

    static let divider = dyn(
        light: NSColor(white: 0.82, alpha: 1),
        dark: NSColor(white: 0.15, alpha: 1)
    )

    // MARK: - Transcript word states

    static let wordNormal = textPrimary

    static let wordDeleted = dyn(
        light: NSColor(white: 0.13, alpha: 0.35),
        dark: NSColor(red: 0.831, green: 0.831, blue: 0.831, alpha: 0.35)
    )

    static let wordDeletedStrikethrough = error

    static let wordSelectedBackground = accent.withAlphaComponent(0.3)

    // MARK: - Silence tokens

    static let silenceText = dyn(
        light: NSColor(white: 0.55, alpha: 1),
        dark: NSColor(white: 0.4, alpha: 1)
    )

    // MARK: - Helper

    private static func dyn(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }
}
