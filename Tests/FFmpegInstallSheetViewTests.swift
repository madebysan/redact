import AppKit
import Testing
@testable import Redact

@Test @MainActor func installSheetOffersTheDownloadWithSizeSourceAndLicense() throws {
    let sheet = FFmpegInstallSheetView(
        frame: NSRect(origin: .zero, size: FFmpegInstallSheetView.defaultSize),
        distribution: .current
    )
    let window = NSWindow(contentRect: sheet.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = sheet

    #expect(sheet.focusInitialControl(in: window))
    let focused = try #require(window.firstResponder as? NSButton)
    #expect(focused.title == "Install FFmpeg")
    #expect(focused.keyEquivalent == "\r")
    #expect(sheet.bodyText.contains("Application Support"))
    #expect(sheet.detailsText.contains(FFmpegDistribution.current.version))
    #expect(sheet.detailsText.contains(FFmpegDistribution.current.formattedDownloadSize))
    #expect(sheet.detailsText.contains(FFmpegDistribution.current.sourceName))
    #expect(sheet.detailsText.contains(FFmpegDistribution.current.licenseName))
    #expect(sheet.subviews.contains { ($0 as? NSButton)?.title == "Not Now" })
}

@Test @MainActor func installSheetShowsProgressThenErrorWithRetry() throws {
    let sheet = FFmpegInstallSheetView(
        frame: NSRect(origin: .zero, size: FFmpegInstallSheetView.defaultSize),
        distribution: .current
    )
    let window = NSWindow(contentRect: sheet.bounds, styleMask: [.titled], backing: .buffered, defer: false)
    window.contentView = sheet
    var installRequests = 0
    var cancelRequests = 0
    sheet.onInstall = { installRequests += 1 }
    sheet.onCancelInstall = { cancelRequests += 1 }

    sheet.showInstalling()
    #expect(sheet.isInstalling)
    sheet.updateProgress(ManagedFFmpegInstallProgress(
        phase: .downloading("ffmpeg"),
        completedBytes: 10_000_000,
        totalBytes: 50_000_000
    ))
    #expect(sheet.statusText == "Downloading ffmpeg…")
    let cancelButton = try #require(
        sheet.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Cancel" }
    )
    #expect(!cancelButton.isHidden)
    cancelButton.performClick(nil)
    #expect(cancelRequests == 1)

    sheet.showError("The download failed.")
    #expect(!sheet.isInstalling)
    #expect(sheet.statusText == "Install Failed")
    let tryAgain = try #require(
        sheet.subviews.compactMap { $0 as? NSButton }.first { $0.title == "Try Again" }
    )
    #expect(!tryAgain.isHidden)
    #expect(window.firstResponder === tryAgain)
    tryAgain.performClick(nil)
    #expect(installRequests == 1)
}

@Test @MainActor func coordinatorRunsTheActionImmediatelyWhenFFmpegIsAvailable() {
    guard PathUtilities.hasFFmpegAndFFprobe else { return }
    let coordinator = FFmpegInstallCoordinator()
    var ran = false

    let available = coordinator.ensureAvailable(in: nil) { ran = true }

    #expect(available)
    #expect(!ran)
    #expect(!coordinator.isPresentingSheet)
}
