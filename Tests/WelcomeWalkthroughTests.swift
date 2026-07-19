import AppKit
import Testing
@testable import Redact

@Test func welcomeWalkthroughAppearsUntilTheUserOptsOut() throws {
    let suiteName = "WelcomeWalkthroughTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    #expect(WelcomeWalkthroughStore.shouldPresent(using: defaults))

    WelcomeWalkthroughStore.setDoNotShowAgain(true, using: defaults)

    #expect(!WelcomeWalkthroughStore.shouldPresent(using: defaults))

    WelcomeWalkthroughStore.setDoNotShowAgain(false, using: defaults)

    #expect(WelcomeWalkthroughStore.shouldPresent(using: defaults))
}

@Test @MainActor func welcomeWalkthroughUsesTheApprovedFourPageStory() throws {
    #expect(WelcomeWalkthroughPage.all.count == 4)
    #expect(WelcomeWalkthroughPage.all.map(\.title) == [
        "Welcome to Redact",
        "Delete words, not clips",
        "Clean up automatically",
        "Edit with Claude Code or Codex",
    ])
    #expect(WelcomeWalkthroughPage.all.map(\.symbolName) == [
        nil,
        "strikethrough",
        "wand.and.stars",
        "sparkles",
    ])

    let view = WelcomeWalkthroughView(
        frame: NSRect(x: 0, y: 0, width: 560, height: 520),
        applicationIcon: NSImage(size: NSSize(width: 128, height: 128))
    )
    let window = NSWindow(
        contentRect: view.bounds,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    window.layoutIfNeeded()
    view.layoutSubtreeIfNeeded()

    #expect(view.currentPageIndex == 0)
    #expect(view.currentTitle == "Welcome to Redact")
    #expect(view.primaryButtonTitle == "Next")
    #expect(view.focusInitialControl(in: window))
    let titleField = try #require(
        view.subviews.compactMap { $0 as? NSTextField }
            .first { $0.stringValue == "Welcome to Redact" }
    )
    #expect(titleField.frame.width > 0)
    #expect(titleField.frame.height > 0)

    view.showPage(at: 3)

    #expect(view.currentTitle == "Edit with Claude Code or Codex")
    #expect(view.primaryButtonTitle == "Get Started")
    #expect(view.pageStatus == "Page 4 of 4")
    #expect(recursiveWelcomeText(in: view).contains("transcript-only"))
    #expect(recursiveWelcomeText(in: view).contains("media stays on your Mac"))
    #expect(recursiveWelcomeLabels(in: view).contains("Skip welcome"))
    #expect(recursiveWelcomeLabels(in: view).contains("Do not show again"))

    view.doNotShowAgain = true
    #expect(view.doNotShowAgain)

    let leftArrow = try #require(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        characters: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
        charactersIgnoringModifiers: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)),
        isARepeat: false,
        keyCode: 123
    ))
    #expect(view.performKeyEquivalent(with: leftArrow))
    #expect(view.currentPageIndex == 2)
}

@Test @MainActor func helpMenuCanReplayTheWelcomeWalkthrough() throws {
    let delegate = AppDelegate()
    let helpMenu = delegate.makeHelpMenu()
    let welcomeItem = try #require(helpMenu.items.first { $0.title == "Welcome to Redact" })

    #expect(welcomeItem.action == #selector(AppDelegate.showWelcomeWalkthrough(_:)))
}

@Test @MainActor func captureWelcomeWalkthroughWhenRequested() throws {
    guard let outputPath = ProcessInfo.processInfo.environment["REDACT_UI_CAPTURE_DIR"] else {
        return
    }
    let appearanceValue = ProcessInfo.processInfo.environment["REDACT_UI_APPEARANCE"] ?? "dark"
    let appearanceName: NSAppearance.Name = appearanceValue == "light" ? .aqua : .darkAqua
    let application = NSApplication.shared
    let originalAppearance = application.appearance
    defer { application.appearance = originalAppearance }
    application.appearance = NSAppearance(named: appearanceName)

    let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
    try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

    let captureIcon = NSImage(
        contentsOfFile: FileManager.default.currentDirectoryPath + "/assets/app-icon.png"
    ) ?? NSApp.applicationIconImage ?? NSImage(size: NSSize(width: 128, height: 128))
    let view = WelcomeWalkthroughView(
        frame: NSRect(x: 0, y: 0, width: 560, height: 520),
        applicationIcon: captureIcon
    )
    let window = NSWindow(
        contentRect: view.bounds,
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    window.contentView = view
    window.makeKeyAndOrderFront(nil)
    defer { window.close() }
    window.layoutIfNeeded()
    for index in WelcomeWalkthroughPage.all.indices {
        view.showPage(at: index)
        view.layoutSubtreeIfNeeded()
        try captureWelcome(
            view,
            at: outputURL.appendingPathComponent("welcome-\(index + 1)-\(appearanceValue).png")
        )
    }
}

@MainActor
private func recursiveWelcomeLabels(in view: NSView) -> [String] {
    view.subviews.flatMap { subview in
        [subview.accessibilityLabel()].compactMap { $0 }
            + recursiveWelcomeLabels(in: subview)
    }
}

@MainActor
private func recursiveWelcomeText(in view: NSView) -> String {
    view.subviews.map { subview in
        let ownText = (subview as? NSTextField)?.stringValue ?? ""
        return ownText + " " + recursiveWelcomeText(in: subview)
    }.joined(separator: " ")
}

@MainActor
private func captureWelcome(_ view: NSView, at outputURL: URL) throws {
    view.needsDisplay = true
    view.displayIfNeeded()
    view.subviews.forEach { $0.displayIfNeeded() }
    guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        throw CocoaError(.fileWriteUnknown)
    }
    view.cacheDisplay(in: view.bounds, to: representation)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: outputURL)
}
