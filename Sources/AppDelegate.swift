import AppKit
import UniformTypeIdentifiers

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?
    private let welcomeDefaults: UserDefaults
    private var welcomeWalkthroughWindow: NSWindow?

    init(welcomeDefaults: UserDefaults = .standard) {
        self.welcomeDefaults = welcomeDefaults
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Without a proper .app bundle (e.g. swift run), macOS treats the
        // process as a background tool — no dock icon, no key event focus.
        // This tells macOS to treat it as a regular app.
        NSApp.setActivationPolicy(.regular)

        // Set dock icon from .icns (with 5% padding to reduce visual size)
        var rawIcon: NSImage?
        if let icon = Bundle.main.image(forResource: "icon") {
            rawIcon = icon
        } else {
            let candidates = [
                NSHomeDirectory() + "/Projects/redact/Sources/Resources/icon.icns",
                NSHomeDirectory() + "/Projects/redact/assets/icon.icns",
            ]
            for path in candidates {
                if let icon = NSImage(contentsOfFile: path) {
                    rawIcon = icon
                    break
                }
            }
        }
        if let rawIcon {
            let size = NSSize(width: 1024, height: 1024)
            let scale: CGFloat = 0.90
            let inset = size.width * (1 - scale) / 2
            let paddedIcon = NSImage(size: size)
            paddedIcon.lockFocus()
            rawIcon.draw(in: NSRect(x: inset, y: inset, width: size.width * scale, height: size.height * scale))
            paddedIcon.unlockFocus()
            NSApp.applicationIconImage = paddedIcon
        }

        Settings.shared.applyAppearance()

        setupMenuBar()

        if let restoredController = NSDocumentController.shared.documents
            .compactMap({ $0.windowControllers.first as? MainWindowController })
            .last {
            mainWindowController = restoredController
            restoredController.window?.makeKeyAndOrderFront(nil)
        } else {
            showUntitledDocument()
        }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.presentWelcomeWalkthroughIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        if url.pathExtension.lowercased() == "rdt" {
            do {
                try openDocument(at: url)
            } catch {
                mainWindowController?.showError(error.localizedDescription)
            }
            return
        }

        let controller: MainWindowController
        if let mainWindowController,
           mainWindowController.project.appState == .empty {
            controller = mainWindowController
        } else {
            controller = showUntitledDocument()
        }
        controller.handleImportedFile(url)
    }

    @objc func openProject(_ sender: Any?) {
        let panel = NSOpenPanel()
        if let projectType = UTType(filenameExtension: "rdt") {
            panel.allowedContentTypes = [projectType]
        }
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Open a Redact project"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                try openDocument(at: url)
            } catch {
                mainWindowController?.showError(error.localizedDescription)
            }
        }
    }

    @discardableResult
    private func showUntitledDocument() -> MainWindowController {
        let document = RedactDocument()
        return show(document)
    }

    func openDocument(at url: URL) throws {
        if let document = mainWindowController?.document as? RedactDocument,
           document.project.appState == .empty,
           !document.isDocumentEdited {
            document.close()
        }

        let document = RedactDocument()
        try document.load(from: url)
        _ = show(document)
    }

    @discardableResult
    private func show(_ document: RedactDocument) -> MainWindowController {
        NSDocumentController.shared.addDocument(document)
        document.makeWindowControllers()
        document.showWindows()
        let controller = document.windowControllers.first as! MainWindowController
        mainWindowController = controller
        controller.window?.makeKeyAndOrderFront(nil)
        return controller
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Redact", action: #selector(showAboutWindow), keyEquivalent: "")
        appMenu.addItem(withTitle: "Settings…", action: #selector(showPreferences), keyEquivalent: ",")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Hide Redact", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthersItem)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit Redact", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // File menu
        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open Project…", action: #selector(openProject(_:)), keyEquivalent: "o")
        let importItem = NSMenuItem(title: "Import Media…", action: #selector(MainWindowController.importMedia(_:)), keyEquivalent: "o")
        importItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(importItem)
        let closeProjectItem = NSMenuItem(title: "Close Project", action: #selector(MainWindowController.closeProject(_:)), keyEquivalent: "w")
        closeProjectItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(closeProjectItem)
        fileMenu.addItem(NSMenuItem.separator())
        let saveItem = NSMenuItem(title: "Save Project", action: #selector(MainWindowController.saveProject(_:)), keyEquivalent: "s")
        fileMenu.addItem(saveItem)
        let saveAsItem = NSMenuItem(title: "Save Project As…", action: #selector(MainWindowController.saveProjectAs(_:)), keyEquivalent: "S")
        fileMenu.addItem(saveAsItem)
        fileMenu.addItem(withTitle: "Relink Media…", action: #selector(MainWindowController.relinkMedia(_:)), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())
        let exportMediaItem = NSMenuItem(
            title: "Export Media…",
            action: #selector(MainWindowController.exportMedia(_:)),
            keyEquivalent: "e"
        )
        exportMediaItem.keyEquivalentModifierMask = [.command, .option]
        fileMenu.addItem(exportMediaItem)
        let exportSRTItem = NSMenuItem(title: "Export SRT…", action: #selector(MainWindowController.exportSRT(_:)), keyEquivalent: "e")
        exportSRTItem.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(exportSRTItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // Edit menu
        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: #selector(MainWindowController.performUndo(_:)), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: #selector(MainWindowController.performRedo(_:)), keyEquivalent: "z")
        redoItem.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redoItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        let findItem = NSMenuItem(
            title: "Find…",
            action: #selector(NSResponder.performTextFinderAction(_:)),
            keyEquivalent: "f"
        )
        findItem.tag = NSTextFinder.Action.showFindInterface.rawValue
        editMenu.addItem(findItem)
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(
            withTitle: "Clean Up Transcript…",
            action: #selector(MainWindowController.cleanUpTranscript(_:)),
            keyEquivalent: ""
        )
        editMenu.addItem(
            withTitle: "Edit with Agent…",
            action: #selector(MainWindowController.editWithAgent(_:)),
            keyEquivalent: ""
        )
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(
            withTitle: "Correct Selected Word…",
            action: #selector(MainWindowController.correctSelectedWord(_:)),
            keyEquivalent: ""
        )
        editMenu.addItem(
            withTitle: "Restore Selected Words",
            action: #selector(MainWindowController.restoreSelectedWords(_:)),
            keyEquivalent: ""
        )
        let deleteItem = NSMenuItem(title: "Delete Selected", action: #selector(MainWindowController.deleteSelected(_:)), keyEquivalent: "\u{08}")
        deleteItem.keyEquivalentModifierMask = []
        editMenu.addItem(deleteItem)
        editMenu.addItem(withTitle: "Select All", action: #selector(MainWindowController.selectAllWords(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // View menu
        let viewMenuItem = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let previewItem = NSMenuItem(
            title: "Hide Preview",
            action: #selector(MainWindowController.togglePreview(_:)),
            keyEquivalent: "p"
        )
        previewItem.keyEquivalentModifierMask = [.command, .option]
        viewMenu.addItem(previewItem)
        viewMenu.addItem(
            withTitle: "Enter Full Screen Preview",
            action: #selector(MainWindowController.togglePreviewFullScreen(_:)),
            keyEquivalent: ""
        )
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // Playback menu
        let playbackMenuItem = NSMenuItem()
        let playbackMenu = NSMenu(title: "Playback")
        let playPauseItem = NSMenuItem(title: "Play / Pause", action: #selector(MainWindowController.togglePlayPause(_:)), keyEquivalent: " ")
        playPauseItem.keyEquivalentModifierMask = []
        playbackMenu.addItem(playPauseItem)
        playbackMenu.addItem(NSMenuItem.separator())
        let skipBackItem = NSMenuItem(title: "Skip Back 5s", action: #selector(MainWindowController.skipBack(_:)), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        skipBackItem.keyEquivalentModifierMask = []
        playbackMenu.addItem(skipBackItem)
        let skipForwardItem = NSMenuItem(title: "Skip Forward 5s", action: #selector(MainWindowController.skipForward(_:)), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        skipForwardItem.keyEquivalentModifierMask = []
        playbackMenu.addItem(skipForwardItem)
        playbackMenu.addItem(NSMenuItem.separator())
        playbackMenu.addItem(
            withTitle: "Previous Edit",
            action: #selector(MainWindowController.previousEdit(_:)),
            keyEquivalent: ""
        )
        playbackMenu.addItem(
            withTitle: "Next Edit",
            action: #selector(MainWindowController.nextEdit(_:)),
            keyEquivalent: ""
        )
        playbackMenuItem.submenu = playbackMenu
        mainMenu.addItem(playbackMenuItem)

        // Window menu
        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // Help menu
        let helpMenuItem = NSMenuItem()
        let helpMenu = makeHelpMenu()
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }

    func makeHelpMenu() -> NSMenu {
        let helpMenu = NSMenu(title: "Help")
        let welcomeItem = NSMenuItem(
            title: "Welcome to Redact",
            action: #selector(showWelcomeWalkthrough(_:)),
            keyEquivalent: ""
        )
        welcomeItem.target = self
        helpMenu.addItem(welcomeItem)
        return helpMenu
    }

    @objc func showWelcomeWalkthrough(_ sender: Any?) {
        presentWelcomeWalkthrough()
    }

    private func presentWelcomeWalkthroughIfNeeded() {
        guard WelcomeWalkthroughStore.shouldPresent(using: welcomeDefaults) else { return }
        presentWelcomeWalkthrough()
    }

    private func presentWelcomeWalkthrough() {
        guard let parentWindow = mainWindowController?.window else { return }
        if let welcomeWalkthroughWindow {
            welcomeWalkthroughWindow.makeKeyAndOrderFront(nil)
            return
        }
        guard parentWindow.attachedSheet == nil else {
            NSSound.beep()
            return
        }

        let frame = NSRect(x: 0, y: 0, width: 560, height: 520)
        let walkthroughView = WelcomeWalkthroughView(
            frame: frame,
            applicationIcon: NSApp.applicationIconImage,
            doNotShowAgain: !WelcomeWalkthroughStore.shouldPresent(using: welcomeDefaults)
        )
        let sheetWindow = NSWindow(
            contentRect: frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheetWindow.title = "Welcome to Redact"
        sheetWindow.titleVisibility = .hidden
        sheetWindow.isReleasedWhenClosed = false
        sheetWindow.backgroundColor = Theme.surface1
        sheetWindow.contentView = walkthroughView
        welcomeWalkthroughWindow = sheetWindow

        let dismiss: () -> Void = {
            [weak self, weak parentWindow, weak sheetWindow, weak walkthroughView] in
            guard let self, let walkthroughView else { return }
            WelcomeWalkthroughStore.setDoNotShowAgain(
                walkthroughView.doNotShowAgain,
                using: self.welcomeDefaults
            )
            if let parentWindow, let sheetWindow {
                parentWindow.endSheet(sheetWindow)
            }
        }
        walkthroughView.onFinish = dismiss
        walkthroughView.onSkip = dismiss

        parentWindow.beginSheet(sheetWindow) { [weak self] _ in
            self?.welcomeWalkthroughWindow = nil
        }
        DispatchQueue.main.async {
            _ = walkthroughView.focusInitialControl(in: sheetWindow)
        }
    }

    // MARK: - About Window

    @objc func showAboutWindow() {
        let alert = NSAlert()
        alert.messageText = "Redact"
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        alert.informativeText = "Remove unwanted words from video.\nVersion \(version)"
        alert.alertStyle = .informational

        // Add "Made by santiagoalonso.com" as an accessory view
        let creditButton = NSButton(frame: NSRect(x: 0, y: 0, width: 220, height: 20))
        creditButton.isBordered = false
        creditButton.target = self
        creditButton.action = #selector(openWebsite)

        let attrString = NSMutableAttributedString()
        attrString.append(NSAttributedString(
            string: "Made by ",
            attributes: [
                .foregroundColor: NSColor.tertiaryLabelColor,
                .font: NSFont.systemFont(ofSize: 12),
            ]
        ))
        attrString.append(NSAttributedString(
            string: "santiagoalonso.com",
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .font: NSFont.systemFont(ofSize: 12),
            ]
        ))
        creditButton.attributedTitle = attrString
        alert.accessoryView = creditButton

        alert.icon = NSApp.applicationIconImage

        alert.runModal()
    }

    @objc func showPreferences() {
        SettingsWindowController.show()
    }

    @objc func openWebsite() {
        if let url = URL(string: "https://santiagoalonso.com") {
            NSWorkspace.shared.open(url)
        }
    }
}
