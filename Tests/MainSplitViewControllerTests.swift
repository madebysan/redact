import AppKit
import Testing
@testable import Redact

@Test @MainActor func editorFocusesTranscriptForKeyboardNavigation() {
    let preferences = temporaryPreferences()
    defer { preferences.remove() }
    let controller = MainSplitViewController(preferences: preferences.value)
    let window = NSWindow(contentViewController: controller)

    controller.showEditing(segments: [])

    #expect(window.firstResponder != nil)
    #expect(controller.isTranscriptFocused)
}

@Test @MainActor func editorLayoutDefaultsToTranscriptFirst() {
    let preferences = temporaryPreferences()
    defer { preferences.remove() }
    let controller = MainSplitViewController(preferences: preferences.value)
    controller.view.frame = NSRect(x: 0, y: 0, width: 1_400, height: 900)

    controller.showEditing(segments: [])
    controller.view.layoutSubtreeIfNeeded()

    #expect(controller.isPreviewVisible)
    #expect(controller.previewPanelWidth == FloatingPreviewView.largeWidth)
    #expect(abs(controller.transcriptPanelWidth - 1_400) < 0.5)
}

@Test @MainActor func editorLayoutHidesAndRestoresPreview() {
    let preferences = temporaryPreferences()
    defer { preferences.remove() }
    let controller = MainSplitViewController(preferences: preferences.value)
    controller.view.frame = NSRect(x: 0, y: 0, width: 1_400, height: 900)
    controller.showEditing(segments: [])

    controller.togglePreview()
    #expect(!controller.isPreviewVisible)
    #expect(controller.previewPanelWidth == 0)
    #expect(controller.floatingPreview?.isHidden == true)

    controller.togglePreview()
    #expect(controller.isPreviewVisible)
    #expect(controller.floatingPreview?.isHidden == false)
}

@Test @MainActor func editorLayoutRemembersCompactPreview() {
    let preferences = temporaryPreferences()
    defer { preferences.remove() }
    preferences.value.set(true, forKey: "editor.previewCompact")

    let controller = MainSplitViewController(preferences: preferences.value)
    controller.view.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
    controller.showEditing(segments: [])

    #expect(controller.previewPanelWidth == FloatingPreviewView.smallWidth)
}

@Test @MainActor func editorShowsPersistentMissingMediaRecoveryAction() {
    let preferences = temporaryPreferences()
    defer { preferences.remove() }
    let controller = MainSplitViewController(preferences: preferences.value)
    controller.view.frame = NSRect(x: 0, y: 0, width: 1_400, height: 900)
    var requestedRelink = false
    controller.onRelinkRequested = { requestedRelink = true }

    controller.showEditing(segments: [], showsMissingMediaNotice: true)
    controller.view.layoutSubtreeIfNeeded()

    #expect(controller.hasMissingMediaNotice)
    #expect(controller.missingMediaActionTitle == "Relink Media…")
    #expect(abs(controller.editorTopInset - 48) < 0.5)

    controller.performMissingMediaAction()
    #expect(requestedRelink)

    controller.showEditing(segments: [])
    controller.view.layoutSubtreeIfNeeded()
    #expect(!controller.hasMissingMediaNotice)
    #expect(controller.editorTopInset == 0)
}

@Test @MainActor func importingStateCanCancelBeforeTranscriptionStarts() {
    let controller = MainSplitViewController()
    var requestedCancel = false
    controller.onCancelImportRequested = { requestedCancel = true }

    controller.showImporting(fileName: "interview.mov")

    #expect(controller.importCancelActionTitle == "Cancel")
    controller.performImportCancelAction()
    #expect(requestedCancel)
}

private struct TemporaryPreferences {
    let suiteName: String
    let value: UserDefaults

    func remove() {
        value.removePersistentDomain(forName: suiteName)
    }
}

private func temporaryPreferences() -> TemporaryPreferences {
    let suiteName = "MainSplitViewControllerTests.\(UUID().uuidString)"
    let preferences = UserDefaults(suiteName: suiteName)!
    preferences.removePersistentDomain(forName: suiteName)
    return TemporaryPreferences(suiteName: suiteName, value: preferences)
}
