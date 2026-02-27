import AppKit

class MainSplitViewController: NSViewController {
    private var emptyStateView: EmptyStateView!
    private var transcribeProgressView: TranscribeProgressView!
    private var errorBannerView: ErrorBannerView!

    // Editing UI (split layout)
    private(set) var videoPreviewView: VideoPreviewView!
    private(set) var transportControlsView: TransportControlsView!
    private(set) var transcriptView: TranscriptView!
    private(set) var waveformView: WaveformView!
    private var splitDivider: NSView!
    private var leftPanel: NSView!
    private var rightPanel: NSView!

    private var currentState: AppState = .empty

    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.surface0.cgColor
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupErrorBanner()
        showEmptyState()
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

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -16),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
        ])
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

    func showEditing(segments: [Segment]) {
        clearContent()
        currentState = .editing

        // Left panel: video + transport
        leftPanel = NSView()
        leftPanel.wantsLayer = true
        leftPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(leftPanel)

        videoPreviewView = VideoPreviewView()
        videoPreviewView.translatesAutoresizingMaskIntoConstraints = false
        leftPanel.addSubview(videoPreviewView)

        transportControlsView = TransportControlsView()
        transportControlsView.translatesAutoresizingMaskIntoConstraints = false
        leftPanel.addSubview(transportControlsView)

        // Divider
        splitDivider = NSView()
        splitDivider.wantsLayer = true
        splitDivider.layer?.backgroundColor = Theme.divider.cgColor
        splitDivider.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitDivider)

        // Right panel: transcript
        rightPanel = NSView()
        rightPanel.wantsLayer = true
        rightPanel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(rightPanel)

        transcriptView = TranscriptView()
        transcriptView.translatesAutoresizingMaskIntoConstraints = false
        rightPanel.addSubview(transcriptView)

        // Waveform bar (full width at bottom)
        waveformView = WaveformView()
        waveformView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(waveformView)

        NSLayoutConstraint.activate([
            // Waveform bar: 60pt at bottom, full width
            waveformView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            waveformView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            waveformView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            waveformView.heightAnchor.constraint(equalToConstant: 60),

            // Left panel: 40% width, above waveform
            leftPanel.topAnchor.constraint(equalTo: view.topAnchor),
            leftPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftPanel.bottomAnchor.constraint(equalTo: waveformView.topAnchor),
            leftPanel.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.4),

            // Video preview (fills top of left panel)
            videoPreviewView.topAnchor.constraint(equalTo: leftPanel.topAnchor),
            videoPreviewView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            videoPreviewView.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            videoPreviewView.bottomAnchor.constraint(equalTo: transportControlsView.topAnchor),

            // Transport controls (60pt at bottom of left panel)
            transportControlsView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            transportControlsView.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            transportControlsView.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),
            transportControlsView.heightAnchor.constraint(equalToConstant: 60),

            // Divider (1pt wide)
            splitDivider.topAnchor.constraint(equalTo: view.topAnchor),
            splitDivider.bottomAnchor.constraint(equalTo: waveformView.topAnchor),
            splitDivider.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            splitDivider.widthAnchor.constraint(equalToConstant: 1),

            // Right panel: 60% width, above waveform
            rightPanel.topAnchor.constraint(equalTo: view.topAnchor),
            rightPanel.leadingAnchor.constraint(equalTo: splitDivider.trailingAnchor),
            rightPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightPanel.bottomAnchor.constraint(equalTo: waveformView.topAnchor),

            // Transcript fills right panel
            transcriptView.topAnchor.constraint(equalTo: rightPanel.topAnchor),
            transcriptView.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            transcriptView.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
            transcriptView.bottomAnchor.constraint(equalTo: rightPanel.bottomAnchor),
        ])

        transcriptView.setTranscript(segments: segments)
    }

    // Keep old method name for backward compat during transition
    func showTranscript(segments: [Segment]) {
        showEditing(segments: segments)
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
        splitDivider = nil
        leftPanel = nil
        rightPanel = nil
    }
}
