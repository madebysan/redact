import AppKit
import Testing
@testable import Redact

@Test @MainActor func toolbarMakesPrimaryActionsDiscoverable() throws {
    let project = ProjectDocument()
    let controller = MainWindowController(project: project, document: nil)
    let toolbar = try #require(controller.window?.toolbar)

    #expect(controller.window?.toolbarStyle == .unified)
    #expect(controller.window?.titleVisibility == .hidden)
    #expect(controller.window?.titlebarAppearsTransparent == false)
    #expect(controller.window?.tabbingMode == .disallowed)
    #expect(toolbar.displayMode == .iconOnly)
    #expect(toolbar.sizeMode == .regular)

    #expect(toolbar.items.map(\.itemIdentifier) == [
        MainWindowController.editGroupItem,
        .flexibleSpace,
        MainWindowController.outputGroupItem,
    ])
    let buttons = toolbarButtons(in: toolbar)
    let actionIdentifiers = buttons.compactMap { button in
        button.identifier.map { NSToolbarItem.Identifier($0.rawValue) }
    }
    #expect(actionIdentifiers == [
        MainWindowController.cleanupItem,
        MainWindowController.agentItem,
        MainWindowController.saveItem,
        MainWindowController.exportItem,
        MainWindowController.settingsItem,
        MainWindowController.closeProjectItem,
    ])
    #expect(toolbar.items.last?.itemIdentifier == MainWindowController.outputGroupItem)
    #expect(toolbar.items.allSatisfy { $0.itemIdentifier != .space })
    #expect(toolbar.items.allSatisfy { !["import", "undo", "redo"].contains($0.itemIdentifier.rawValue) })
    let editGroup = try #require(
        toolbar.items.first { $0.itemIdentifier == MainWindowController.editGroupItem }
    )
    let outputGroup = try #require(
        toolbar.items.first { $0.itemIdentifier == MainWindowController.outputGroupItem }
    )
    #expect(editGroup.view?.intrinsicContentSize == NSSize(width: 88, height: 36))
    #expect(outputGroup.view?.intrinsicContentSize == NSSize(width: 164, height: 36))
    #expect(editGroup.view?.layer?.cornerRadius == 18)
    #expect(outputGroup.view?.layer?.cornerRadius == 18)
    #expect(editGroup.view?.layer?.borderWidth == 1)
    #expect(outputGroup.view?.layer?.borderWidth == 1)
    #expect(editGroup.isBordered == false)
    #expect(outputGroup.isBordered == false)

    let cleanup = try toolbarButton(in: toolbar, identifier: MainWindowController.cleanupItem)
    let agent = try toolbarButton(in: toolbar, identifier: MainWindowController.agentItem)
    let save = try toolbarButton(in: toolbar, identifier: MainWindowController.saveItem)
    let export = try toolbarButton(in: toolbar, identifier: MainWindowController.exportItem)
    let settings = try toolbarButton(in: toolbar, identifier: MainWindowController.settingsItem)
    let close = try toolbarButton(in: toolbar, identifier: MainWindowController.closeProjectItem)

    #expect(buttons.allSatisfy { $0.title.isEmpty })
    #expect(buttons.allSatisfy { !$0.isBordered })
    #expect(buttons.allSatisfy { $0.imagePosition == .imageOnly })
    #expect(cleanup.toolTip?.hasPrefix("Clean Up:") == true)
    #expect(agent.toolTip?.hasPrefix("Agent:") == true)
    #expect(save.toolTip?.hasPrefix("Save Project:") == true)
    #expect(export.toolTip?.hasPrefix("Export Media:") == true)
    #expect(settings.toolTip?.hasPrefix("Settings:") == true)
    #expect(close.toolTip?.hasPrefix("Close:") == true)
    #expect(cleanup.image?.accessibilityDescription == "Clean Up")
    #expect(agent.image?.accessibilityDescription == "Agent")
    #expect(save.image?.accessibilityDescription == "Save Project")
    #expect(export.image?.accessibilityDescription == "Export Media")
    for button in [cleanup, agent, save, export, settings, close] {
        #expect(button.intrinsicContentSize.height == 32)
        #expect(button.intrinsicContentSize.width == 38)
    }

    project.filePath = "/private/interview.mov"
    project.mediaInfo = mediaInfo(hasVideo: true)
    project.setTranscript(
        RawTranscript(
            segments: [
                RawSegment(
                    id: 0,
                    words: [RawWord(word: "Hello", start: 0, end: 0.4, confidence: 1)]
                ),
            ],
            language: "en",
            duration: 1
        )
    )
    controller.updateToolbarState()

    #expect(export.toolTip?.hasPrefix("Export Video:") == true)
    #expect(export.image?.accessibilityDescription == "Export Video")
    #expect(export.isEnabled)
    #expect(agent.isEnabled)
    #expect(close.isEnabled)

    project.mediaInfo = mediaInfo(hasVideo: false)
    controller.updateToolbarState()
    #expect(export.toolTip?.hasPrefix("Export Audio:") == true)
}

@MainActor
private func toolbarButton(
    in toolbar: NSToolbar,
    identifier: NSToolbarItem.Identifier
) throws -> NSButton {
    try #require(
        toolbarButtons(in: toolbar).first {
            $0.identifier?.rawValue == identifier.rawValue
        }
    )
}

@MainActor
private func toolbarButtons(in toolbar: NSToolbar) -> [NSButton] {
    toolbar.items.flatMap { buttons(in: $0.view) }
}

@MainActor
private func buttons(in view: NSView?) -> [NSButton] {
    guard let view else { return [] }
    let current = (view as? NSButton).map { [$0] } ?? []
    return current + view.subviews.flatMap { buttons(in: $0) }
}

private func mediaInfo(hasVideo: Bool) -> MediaInfo {
    var streams = [
        MediaStreamInfo(index: 1, kind: .audio, codecName: "aac"),
    ]
    if hasVideo {
        streams.insert(
            MediaStreamInfo(index: 0, kind: .video, codecName: "h264"),
            at: 0
        )
    }
    return MediaInfo(duration: 1, containerNames: [hasVideo ? "mov" : "m4a"], streams: streams)
}
