import AppKit

/// The editing window's content: a full-width reading surface with cleanup
/// toggles above the transcript, a floating preview over it, and the waveform
/// strip along the bottom.
class MainSplitViewController: NSViewController {
    private let preferences: UserDefaults
    private var previewCollapsed = false

    private var emptyStateView: EmptyStateView!
    private var transcribeProgressView: TranscribeProgressView!
    private var errorBannerView: ErrorBannerView!
    private var missingMediaNoticeView: MissingMediaNoticeView?
    private var importCancelButton: NSButton?

    var onRelinkRequested: (() -> Void)?
    var onCancelImportRequested: (() -> Void)?

    // Editing UI
    private(set) var videoPreviewView: VideoPreviewView!
    private(set) var transportControlsView: TransportControlsView!
    private(set) var transcriptView: TranscriptView!
    private(set) var waveformView: WaveformView!
    private(set) var cleanupBarView: CleanupBarView!
    private(set) var floatingPreview: FloatingPreviewView!
    private var transcriptPanel: NSView!
    private var previewTrailing: NSLayoutConstraint?
    private var previewBottom: NSLayoutConstraint?

    private var currentState: AppState = .empty

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        preferences = .standard
        super.init(coder: coder)
    }

    override func loadView() {
        let container = ThemedContainerView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.surface0.cgColor
        container.onAppearanceChange = { [weak container, weak self] in
            container?.layer?.backgroundColor = Theme.surface0.cgColor
            self?.transcriptPanel?.layer?.backgroundColor = Theme.surface1.cgColor
        }
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupErrorBanner()
        showEmptyState()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        positionFloatingPreview()
    }

    private func setupErrorBanner() {
        errorBannerView = ErrorBannerView()
        errorBannerView.translatesAutoresizingMaskIntoConstraints = false
        errorBannerView.isHidden = true
        view.addSubview(errorBannerView)

        NSLayoutConstraint.activate([
            errorBannerView.topAnchor.constraint(equalTo: view.topAnchor),
            errorBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            errorBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            errorBannerView.heightAnchor.constraint(equalToConstant: 36),
        ])
    }

    func showError(_ message: String) {
        // Re-add banner on top if needed (clearContent removes all subviews)
        if errorBannerView.superview == nil {
            view.addSubview(errorBannerView)
            NSLayoutConstraint.activate([
                errorBannerView.topAnchor.constraint(equalTo: view.topAnchor),
                errorBannerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                errorBannerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                errorBannerView.heightAnchor.constraint(equalToConstant: 36),
            ])
        }
        view.addSubview(errorBannerView, positioned: .above, relativeTo: nil)
        errorBannerView.show(message: message)
    }

    // MARK: - State Transitions

    func showEmptyState() {
        clearContent()
        currentState = .empty

        emptyStateView = EmptyStateView(frame: view.bounds)
        emptyStateView.autoresizingMask = [.width, .height]
        emptyStateView.onFileDropped = { [weak self] url in
            guard let windowController = self?.view.window?.windowController as? MainWindowController else { return }
            windowController.handleImportedFile(url)
        }
        emptyStateView.onImportClicked = { [weak self] in
            guard let windowController = self?.view.window?.windowController as? MainWindowController else { return }
            windowController.importMedia(nil)
        }
        view.addSubview(emptyStateView)
    }

    func showImporting(fileName: String) {
        clearContent()
        currentState = .importing

        let label = NSTextField(labelWithString: "Extracting audio from \(fileName)…")
        label.font = .systemFont(ofSize: 16, weight: .medium)
        label.textColor = Theme.textSecondary
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(spinner)

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelImportClicked))
        cancelButton.bezelStyle = .rounded
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cancelButton)
        importCancelButton = cancelButton

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            cancelButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 16),
        ])
    }

    var importCancelActionTitle: String? {
        importCancelButton?.title
    }

    func performImportCancelAction() {
        onCancelImportRequested?()
    }

    @objc private func cancelImportClicked() {
        performImportCancelAction()
    }

    func showTranscribing() {
        clearContent()
        currentState = .transcribing

        transcribeProgressView = TranscribeProgressView(frame: view.bounds)
        transcribeProgressView.autoresizingMask = [.width, .height]
        transcribeProgressView.onCancel = { [weak self] in
            guard let windowController = self?.view.window?.windowController as? MainWindowController else { return }
            windowController.cancelTranscription()
        }
        view.addSubview(transcribeProgressView)
    }

    func updateTranscribeProgress(_ progress: TranscribeProgress) {
        transcribeProgressView?.updateProgress(progress)
    }

    func showEditing(segments: [Segment], showsMissingMediaNotice: Bool = false) {
        clearContent()
        currentState = .editing

        // The window uses a full-size content view, so the editor starts below the
        // title bar's safe area instead of the view's top edge.
        let safeTop = view.safeAreaLayoutGuide.topAnchor
        let editorTopAnchor: NSLayoutYAxisAnchor
        if showsMissingMediaNotice {
            let noticeView = MissingMediaNoticeView()
            noticeView.onRelink = { [weak self] in self?.onRelinkRequested?() }
            noticeView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(noticeView)
            missingMediaNoticeView = noticeView
            NSLayoutConstraint.activate([
                noticeView.topAnchor.constraint(equalTo: safeTop),
                noticeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                noticeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                noticeView.heightAnchor.constraint(equalToConstant: 48),
            ])
            editorTopAnchor = noticeView.bottomAnchor
        } else {
            editorTopAnchor = safeTop
        }

        // Transcript panel: cleanup toggles over the reading column.
        transcriptPanel = NSView()
        transcriptPanel.wantsLayer = true
        transcriptPanel.layer?.backgroundColor = Theme.surface1.cgColor
        transcriptPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(transcriptPanel)

        cleanupBarView = CleanupBarView()
        cleanupBarView.translatesAutoresizingMaskIntoConstraints = false
        transcriptPanel.addSubview(cleanupBarView)

        transcriptView = TranscriptView()
        transcriptView.translatesAutoresizingMaskIntoConstraints = false
        transcriptPanel.addSubview(transcriptView)

        // Floating preview over the transcript, anchored from the bottom-trailing corner.
        floatingPreview = FloatingPreviewView(preferences: preferences)
        floatingPreview.translatesAutoresizingMaskIntoConstraints = false
        floatingPreview.isHidden = previewCollapsed
        floatingPreview.onMove = { [weak self] in self?.positionFloatingPreview() }
        transcriptPanel.addSubview(floatingPreview)
        videoPreviewView = floatingPreview.videoView
        transportControlsView = floatingPreview.transportView

        waveformView = WaveformView()
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(waveformView)

        let trailing = floatingPreview.trailingAnchor.constraint(equalTo: transcriptPanel.trailingAnchor)
        let bottom = floatingPreview.bottomAnchor.constraint(equalTo: transcriptPanel.bottomAnchor)
        previewTrailing = trailing
        previewBottom = bottom

        NSLayoutConstraint.activate([
            waveformView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            waveformView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            waveformView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            waveformView.heightAnchor.constraint(equalToConstant: 60),

            transcriptPanel.topAnchor.constraint(equalTo: editorTopAnchor),
            transcriptPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            transcriptPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            transcriptPanel.bottomAnchor.constraint(equalTo: waveformView.topAnchor),

            cleanupBarView.topAnchor.constraint(equalTo: transcriptPanel.topAnchor),
            cleanupBarView.leadingAnchor.constraint(equalTo: transcriptPanel.leadingAnchor),
            cleanupBarView.trailingAnchor.constraint(equalTo: transcriptPanel.trailingAnchor),
            cleanupBarView.heightAnchor.constraint(equalToConstant: CleanupBarView.height),

            transcriptView.topAnchor.constraint(equalTo: cleanupBarView.bottomAnchor),
            transcriptView.leadingAnchor.constraint(equalTo: transcriptPanel.leadingAnchor),
            transcriptView.trailingAnchor.constraint(equalTo: transcriptPanel.trailingAnchor),
            transcriptView.bottomAnchor.constraint(equalTo: transcriptPanel.bottomAnchor),

            trailing,
            bottom,
        ])
        positionFloatingPreview()

        transcriptView.setTranscript(segments: segments)
        transcriptView.focusForKeyboardNavigation()
    }

    /// Apply the preview's remembered offset, kept inside the transcript panel.
    private func positionFloatingPreview() {
        guard let floatingPreview, let transcriptPanel else { return }
        if transcriptPanel.bounds.width > 0 {
            floatingPreview.clampOffset(in: transcriptPanel.bounds)
        }
        previewTrailing?.constant = -floatingPreview.offset.x
        previewBottom?.constant = -floatingPreview.offset.y
        // Keep the reading column clear of the preview while it sits in the right half.
        let docked = !floatingPreview.isHidden && floatingPreview.offset.x < transcriptPanel.bounds.width / 2
        transcriptView?.trailingReserve = docked ? floatingPreview.panelWidth + floatingPreview.offset.x : 0
    }

    // MARK: - Editor Layout

    var isPreviewVisible: Bool {
        currentState == .editing && !previewCollapsed
    }

    var isTranscriptFocused: Bool {
        currentState == .editing && transcriptView?.hasKeyboardFocus == true
    }

    /// Width of the floating preview when it is shown; the transcript always spans the window.
    var previewPanelWidth: CGFloat {
        isPreviewVisible ? (floatingPreview?.panelWidth ?? 0) : 0
    }

    var transcriptPanelWidth: CGFloat {
        transcriptPanel?.bounds.width ?? view.bounds.width
    }

    var hasMissingMediaNotice: Bool {
        missingMediaNoticeView?.superview != nil
    }

    var missingMediaActionTitle: String? {
        missingMediaNoticeView?.actionTitle
    }

    var editorTopInset: CGFloat {
        guard let transcriptPanel else { return 0 }
        return max(0, view.bounds.maxY - transcriptPanel.frame.maxY)
    }

    func performMissingMediaAction() {
        missingMediaNoticeView?.performAction()
    }

    func togglePreview() {
        guard currentState == .editing else { return }
        previewCollapsed.toggle()
        floatingPreview?.isHidden = previewCollapsed
        positionFloatingPreview()
    }

    private func clearContent() {
        // Remove all subviews except the error banner
        view.subviews.forEach { subview in
            if subview !== errorBannerView {
                subview.removeFromSuperview()
            }
        }
        emptyStateView = nil
        transcribeProgressView = nil
        videoPreviewView = nil
        transportControlsView = nil
        transcriptView = nil
        waveformView = nil
        cleanupBarView = nil
        floatingPreview = nil
        missingMediaNoticeView = nil
        importCancelButton = nil
        transcriptPanel = nil
        previewTrailing = nil
        previewBottom = nil
    }
}

// MARK: - Themed Container View

/// An NSView that fires a closure whenever the system or forced appearance changes.
/// Used so the owning view controller can re-apply layer-based colors without
/// going through a separate NotificationCenter subscription.
private final class ThemedContainerView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}
