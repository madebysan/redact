import AppKit

/// Owns the in-app FFmpeg install: decides whether import or export can go
/// ahead, presents the install sheet when FFmpeg is missing, runs the
/// download, and re-runs the action that was waiting on it.
@MainActor
final class FFmpegInstallCoordinator {
    private let distribution: FFmpegDistribution
    private let makeInstaller: (FFmpegDistribution) -> ManagedFFmpegInstaller?
    private var sheetWindow: NSWindow?
    private weak var sheetView: FFmpegInstallSheetView?
    private var installTask: Task<Void, Never>?
    private var pendingAction: (@MainActor () -> Void)?

    var isPresentingSheet: Bool { sheetWindow != nil }

    init(
        distribution: FFmpegDistribution = .current,
        makeInstaller: ((FFmpegDistribution) -> ManagedFFmpegInstaller?)? = nil
    ) {
        self.distribution = distribution
        self.makeInstaller = makeInstaller ?? { distribution in
            guard let directory = ManagedFFmpegLocation.directory() else { return nil }
            return ManagedFFmpegInstaller(distribution: distribution, directory: directory)
        }
    }

    /// Returns `true` when both FFmpeg and FFprobe are available. Otherwise
    /// shows the install sheet on `parentWindow` and runs `action` once the
    /// install succeeds.
    @discardableResult
    func ensureAvailable(
        in parentWindow: NSWindow?,
        then action: @escaping @MainActor () -> Void
    ) -> Bool {
        if PathUtilities.hasFFmpegAndFFprobe {
            return true
        }
        guard let parentWindow else { return false }
        present(in: parentWindow, then: action)
        return false
    }

    /// Reads media streams with the FFmpeg that is now available, for projects
    /// opened before it was installed.
    func probeMediaInfo(
        at path: String,
        completion: @escaping @MainActor (MediaInfo?) -> Void
    ) {
        let service = FFmpegService()
        Task {
            let info = try? await service.getMediaInfo(
                filePath: path,
                operation: ProcessOperation()
            )
            completion(info)
        }
    }

    func present(in parentWindow: NSWindow, then action: @escaping @MainActor () -> Void) {
        pendingAction = action
        guard sheetWindow == nil else { return }

        let size = FFmpegInstallSheetView.defaultSize
        let view = FFmpegInstallSheetView(
            frame: NSRect(origin: .zero, size: size),
            distribution: distribution
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.title = "Install FFmpeg"
        window.contentView = view
        sheetWindow = window
        sheetView = view

        view.onInstall = { [weak self] in self?.startInstall() }
        view.onNotNow = { [weak self] in self?.dismiss(runPendingAction: false) }
        view.onClose = { [weak self] in self?.dismiss(runPendingAction: false) }
        view.onCancelInstall = { [weak self] in
            self?.sheetView?.showCancelling()
            self?.installTask?.cancel()
        }

        parentWindow.beginSheet(window) { _ in }
        view.focusInitialControl(in: window)
    }

    private func startInstall() {
        guard let sheetView, installTask == nil else { return }
        guard let installer = makeInstaller(distribution) else {
            sheetView.showError("Redact could not find its Application Support folder.")
            return
        }
        sheetView.showInstalling()

        // The coordinator is main-actor isolated, so capturing it in the
        // progress callback is safe; the callback only lives for the install.
        installTask = Task {
            do {
                _ = try await installer.install { progress in
                    Task { @MainActor in
                        self.sheetView?.updateProgress(progress)
                    }
                }
                installTask = nil
                dismiss(runPendingAction: true)
            } catch ManagedFFmpegInstallError.cancelled {
                installTask = nil
                dismiss(runPendingAction: false)
            } catch {
                installTask = nil
                self.sheetView?.showError(error.localizedDescription)
            }
        }
    }

    private func dismiss(runPendingAction: Bool) {
        if let sheetWindow, let parent = sheetWindow.sheetParent {
            parent.endSheet(sheetWindow)
        }
        sheetWindow = nil
        sheetView = nil
        let action = pendingAction
        pendingAction = nil
        if runPendingAction, PathUtilities.hasFFmpegAndFFprobe {
            action?()
        }
    }
}
