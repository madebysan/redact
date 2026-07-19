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
    #expect(abs(controller.previewPanelWidth - 490) < 0.5)
    #expect(controller.transcriptPanelWidth > controller.previewPanelWidth)
}

@Test @MainActor func editorLayoutCollapsesAndRestoresPreview() {
    let preferences = temporaryPreferences()
    defer { preferences.remove() }
    let controller = MainSplitViewController(preferences: preferences.value)
    controller.view.frame = NSRect(x: 0, y: 0, width: 1_400, height: 900)
    controller.showEditing(segments: [])

    controller.resizePreview(to: 560)
    controller.togglePreview()

    #expect(!controller.isPreviewVisible)
    #expect(controller.previewPanelWidth == 0)
    #expect(controller.transcriptPanelWidth == 1_400)

    controller.togglePreview()

    #expect(controller.isPreviewVisible)
    #expect(abs(controller.previewPanelWidth - 560) < 0.5)
    #expect(abs(controller.transcriptPanelWidth - 840) < 0.5)
}

@Test @MainActor func editorLayoutRestoresSavedPreviewFraction() {
    let preferences = temporaryPreferences()
    defer { preferences.remove() }
    let firstController = MainSplitViewController(preferences: preferences.value)
    firstController.view.frame = NSRect(x: 0, y: 0, width: 1_400, height: 900)
    firstController.showEditing(segments: [])
    firstController.resizePreview(to: 560)

    let restoredController = MainSplitViewController(preferences: preferences.value)
    restoredController.view.frame = NSRect(x: 0, y: 0, width: 1_000, height: 700)
    restoredController.showEditing(segments: [])

    #expect(abs(restoredController.previewPanelWidth - 400) < 0.5)
    #expect(abs(restoredController.transcriptPanelWidth - 600) < 0.5)
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
