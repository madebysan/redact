import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)

        setupMenuBar()

        mainWindowController = MainWindowController()
        mainWindowController?.showWindow(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Redact", action: #selector(showAboutWindow), keyEquivalent: "")
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
        fileMenu.addItem(withTitle: "Import Media…", action: #selector(MainWindowController.importMedia(_:)), keyEquivalent: "o")
        fileMenu.addItem(NSMenuItem.separator())
        let saveItem = NSMenuItem(title: "Save Project", action: #selector(MainWindowController.saveProject(_:)), keyEquivalent: "s")
        fileMenu.addItem(saveItem)
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Export Video…", action: #selector(MainWindowController.exportVideo(_:)), keyEquivalent: "e")
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
        editMenu.addItem(withTitle: "Delete Selected", action: #selector(MainWindowController.deleteSelected(_:)), keyEquivalent: "\u{08}")
        editMenu.addItem(withTitle: "Select All", action: #selector(MainWindowController.selectAllWords(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Playback menu
        let playbackMenuItem = NSMenuItem()
        let playbackMenu = NSMenu(title: "Playback")
        playbackMenu.addItem(withTitle: "Play / Pause", action: #selector(MainWindowController.togglePlayPause(_:)), keyEquivalent: " ")
        playbackMenu.addItem(NSMenuItem.separator())
        let skipBackItem = NSMenuItem(title: "Skip Back 5s", action: #selector(MainWindowController.skipBack(_:)), keyEquivalent: String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)))
        skipBackItem.keyEquivalentModifierMask = []
        playbackMenu.addItem(skipBackItem)
        let skipForwardItem = NSMenuItem(title: "Skip Forward 5s", action: #selector(MainWindowController.skipForward(_:)), keyEquivalent: String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)))
        skipForwardItem.keyEquivalentModifierMask = []
        playbackMenu.addItem(skipForwardItem)
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
        let helpMenu = NSMenu(title: "Help")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        NSApp.mainMenu = mainMenu
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }

    // MARK: - About Window

    @objc func showAboutWindow() {
        let alert = NSAlert()
        alert.messageText = "Redact"
        alert.informativeText = "Remove unwanted words from video.\nVersion 1.0.0"
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

        if let icon = NSImage(named: "AppIcon") {
            alert.icon = icon
        }

        alert.runModal()
    }

    @objc func openWebsite() {
        if let url = URL(string: "https://santiagoalonso.com") {
            NSWorkspace.shared.open(url)
        }
    }
}
