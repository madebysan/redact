import AppKit
import Foundation
import Testing
@testable import Redact

@Test @MainActor func legacyAppearancePreferencesResolveToDarkAqua() throws {
    let suiteName = "redact-dark-mode-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    defaults.set("light", forKey: "theme")

    let application = NSApplication.shared
    let originalAppearance = application.appearance
    defer { application.appearance = originalAppearance }

    let settings = Settings(defaults: defaults)
    settings.applyAppearance()

    #expect(settings.theme == "dark")
    #expect(defaults.string(forKey: "theme") == "dark")
    #expect(application.appearance?.name == .darkAqua)

    settings.theme = "system"

    #expect(settings.theme == "dark")
    #expect(defaults.string(forKey: "theme") == "dark")
    #expect(application.appearance?.name == .darkAqua)
}

@Test @MainActor func settingsWindowDoesNotOfferAnAppearanceSwitcher() throws {
    let controller = SettingsWindowController()
    let window = try #require(controller.window)
    let contentView = try #require(window.contentView)
    let labels = descendantViews(of: contentView, as: NSTextField.self).map(\.stringValue)
    let segmentedLabels = descendantViews(of: contentView, as: NSSegmentedControl.self)
        .flatMap { control in
            (0..<control.segmentCount).compactMap { control.label(forSegment: $0) }
        }

    #expect(window.title == "Settings")
    #expect(contentView.frame.height == 560)
    #expect(!labels.contains("Appearance"))
    #expect(!labels.contains("Theme"))
    #expect(!segmentedLabels.contains("Light"))
    #expect(!segmentedLabels.contains("System"))
}

@Test @MainActor func settingsWindowMakesDefaultsAndModelTradeoffsDiscoverable() throws {
    let controller = SettingsWindowController()
    let contentView = try #require(controller.window?.contentView)
    let buttons = descendantViews(of: contentView, as: NSButton.self)
    let popups = descendantViews(of: contentView, as: NSPopUpButton.self)
    let labels = descendantViews(of: contentView, as: NSTextField.self).map(\.stringValue)
    let modelPopup = try #require(
        popups.first { popup in
            (0..<popup.numberOfItems).contains { popup.itemTitle(at: $0).contains("Multilingual") }
        }
    )
    let modelTitles = (0..<modelPopup.numberOfItems).map { modelPopup.itemTitle(at: $0) }

    #expect(buttons.contains { $0.accessibilityLabel() == "Restore transcript defaults" })
    #expect(modelTitles.contains { $0.contains("Small · Multilingual · Recommended") })
    #expect(modelTitles.contains { $0.contains("English only") })
    #expect(labels.contains { $0.contains("Small is recommended") })
}

@Test @MainActor func captureSettingsWindowWhenRequested() throws {
    guard let outputPath = ProcessInfo.processInfo.environment["REDACT_UI_CAPTURE_DIR"] else {
        return
    }
    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
    let controller = SettingsWindowController()
    let window = try #require(controller.window)
    let contentView = try #require(window.contentView)
    window.orderFrontRegardless()
    defer { window.close() }
    contentView.layoutSubtreeIfNeeded()
    guard let representation = contentView.bitmapImageRepForCachingDisplay(
        in: contentView.bounds
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    contentView.cacheDisplay(in: contentView.bounds, to: representation)
    let data = try #require(representation.representation(using: .png, properties: [:]))
    try data.write(to: outputURL.appendingPathComponent("settings-window-dark.png"))
}

private func descendantViews<T: NSView>(of root: NSView, as type: T.Type) -> [T] {
    root.subviews.flatMap { view -> [T] in
        let match = (view as? T).map { [$0] } ?? []
        return match + descendantViews(of: view, as: type)
    }
}
