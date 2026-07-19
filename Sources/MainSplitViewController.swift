import AppKit

class MainSplitViewController: NSViewController {
    private static let previewFractionPreferenceKey = "editor.previewFraction"
    private static let defaultPreviewFraction: CGFloat = 0.35

    private let preferences: UserDefaults
    private var previewFraction: CGFloat
    private var previewCollapsed = false
    private var lastContainerWidth: CGFloat = 0

    private var emptyStateView: EmptyStateView!
    private var transcribeProgressView: TranscribeProgressView!
    private var errorBannerView: ErrorBannerView!
    private var missingMediaNoticeView: MissingMediaNoticeView?
    private var importCancelButton: NSButton?

    var onRelinkRequested: (() -> Void)?
    var onCancelImportRequested: (() -> Void)?

    // Editing UI (split layout)
    private(set) var videoPreviewView: VideoPreviewView!
    private(set) var transportControlsView: TransportControlsView!
    private(set) var transcriptView: TranscriptView!
    private(set) var waveformView: WaveformView!
    private var splitDivider: NSView!
    private var leftPanel: NSView!
    private var rightPanel: NSView!
    private var dragEventMonitor: Any?
    private var mouseUpEventMonitor: Any?

    /// The constraint that controls the left panel width (draggable).
    private var leftPanelWidthConstraint: NSLayoutConstraint?

    /// Minimum width for either panel.
    private let panelMinWidth: CGFloat = 250

    private var currentState: AppState = .empty

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        let savedFraction = preferences.object(forKey: Self.previewFractionPreferenceKey) as? NSNumber
        previewFraction = Self.normalizedPreviewFraction(
            savedFraction.map { CGFloat($0.doubleValue) } ?? Self.defaultPreviewFraction
        )
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        preferences = .standard
        let savedFraction = preferences.object(forKey: Self.previewFractionPreferenceKey) as? NSNumber
        previewFraction = Self.normalizedPreviewFraction(
            savedFraction.map { CGFloat($0.doubleValue) } ?? Self.defaultPreviewFraction
        )
        super.init(coder: coder)
    }

    override func loadView() {
        let container = ThemedContainerView(frame: NSRect(x: 0, y: 0, width: 1400, height: 900))
        container.wantsLayer = true
        container.layer?.backgroundColor = Theme.surface0.cgColor
        container.onAppearanceChange = { [weak container, weak self] in
            container?.layer?.backgroundColor = Theme.surface0.cgColor
            self?.splitDivider?.layer?.backgroundColor = Theme.divider.cgColor
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
        guard currentState == .editing, !previewCollapsed, !isDraggingDivider else { return }

        let containerWidth = view.bounds.width
        guard containerWidth > 0, abs(containerWidth - lastContainerWidth) > 0.5 else { return }
        leftPanelWidthConstraint?.constant = resolvedPreviewWidth(for: containerWidth)
        lastContainerWidth = containerWidth
    }

    deinit {
        removeDividerEventMonitors()
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

        let editorTopAnchor: NSLayoutYAxisAnchor
        if showsMissingMediaNotice {
            let noticeView = MissingMediaNoticeView()
            noticeView.onRelink = { [weak self] in self?.onRelinkRequested?() }
            noticeView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(noticeView)
            missingMediaNoticeView = noticeView
            NSLayoutConstraint.activate([
                noticeView.topAnchor.constraint(equalTo: view.topAnchor),
                noticeView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                noticeView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                noticeView.heightAnchor.constraint(equalToConstant: 48),
            ])
            editorTopAnchor = noticeView.bottomAnchor
        } else {
            editorTopAnchor = view.topAnchor
        }

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

        // Divider (6pt wide hit area, 1pt visible line)
        splitDivider = DividerView()
        splitDivider.wantsLayer = true
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

        // Preview starts smaller than the transcript and restores the user's ratio.
        let initialWidth = previewCollapsed ? 0 : resolvedPreviewWidth(for: view.bounds.width)
        let widthConstraint = leftPanel.widthAnchor.constraint(equalToConstant: initialWidth)
        leftPanelWidthConstraint = widthConstraint
        leftPanel.isHidden = previewCollapsed
        splitDivider.isHidden = previewCollapsed
        lastContainerWidth = view.bounds.width

        NSLayoutConstraint.activate([
            // Waveform bar: 60pt at bottom, full width
            waveformView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            waveformView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            waveformView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            waveformView.heightAnchor.constraint(equalToConstant: 60),

            // Left panel: variable width, above waveform
            leftPanel.topAnchor.constraint(equalTo: editorTopAnchor),
            leftPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            leftPanel.bottomAnchor.constraint(equalTo: waveformView.topAnchor),
            widthConstraint,

            // Video preview (fills top of left panel)
            videoPreviewView.topAnchor.constraint(equalTo: leftPanel.topAnchor),
            videoPreviewView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            videoPreviewView.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            videoPreviewView.bottomAnchor.constraint(equalTo: transportControlsView.topAnchor),

            // Transport controls (84pt at bottom of left panel)
            transportControlsView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            transportControlsView.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            transportControlsView.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),
            transportControlsView.heightAnchor.constraint(equalToConstant: 84),

            // Divider (6pt wide for easy grabbing)
            splitDivider.topAnchor.constraint(equalTo: editorTopAnchor),
            splitDivider.bottomAnchor.constraint(equalTo: waveformView.topAnchor),
            splitDivider.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor, constant: -3),
            splitDivider.widthAnchor.constraint(equalToConstant: 6),

            // Right panel: fills remaining width, above waveform
            rightPanel.topAnchor.constraint(equalTo: editorTopAnchor),
            rightPanel.leadingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            rightPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rightPanel.bottomAnchor.constraint(equalTo: waveformView.topAnchor),

            // Transcript fills right panel
            transcriptView.topAnchor.constraint(equalTo: rightPanel.topAnchor),
            transcriptView.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            transcriptView.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
            transcriptView.bottomAnchor.constraint(equalTo: rightPanel.bottomAnchor),
        ])

        // Setup divider dragging
        setupDividerDragging()

        transcriptView.setTranscript(segments: segments)
        transcriptView.focusForKeyboardNavigation()
    }

    // Keep old method name for backward compat during transition
    func showTranscript(segments: [Segment]) {
        showEditing(segments: segments)
    }

    // MARK: - Editor Layout

    var isPreviewVisible: Bool {
        currentState == .editing && !previewCollapsed
    }

    var isTranscriptFocused: Bool {
        currentState == .editing && transcriptView?.hasKeyboardFocus == true
    }

    var previewPanelWidth: CGFloat {
        isPreviewVisible ? (leftPanelWidthConstraint?.constant ?? 0) : 0
    }

    var transcriptPanelWidth: CGFloat {
        max(0, view.bounds.width - previewPanelWidth)
    }

    var hasMissingMediaNotice: Bool {
        missingMediaNoticeView?.superview != nil
    }

    var missingMediaActionTitle: String? {
        missingMediaNoticeView?.actionTitle
    }

    var editorTopInset: CGFloat {
        guard let leftPanel else { return 0 }
        return max(0, view.bounds.maxY - leftPanel.frame.maxY)
    }

    func performMissingMediaAction() {
        missingMediaNoticeView?.performAction()
    }

    func togglePreview() {
        guard currentState == .editing else { return }

        previewCollapsed.toggle()
        leftPanel.isHidden = previewCollapsed
        splitDivider.isHidden = previewCollapsed
        leftPanelWidthConstraint?.constant = previewCollapsed ? 0 : resolvedPreviewWidth(for: view.bounds.width)
        view.needsLayout = true
    }

    func resizePreview(to requestedWidth: CGFloat) {
        guard currentState == .editing, !previewCollapsed else { return }

        let containerWidth = view.bounds.width
        guard containerWidth > 0 else { return }
        let clampedWidth = clampedPreviewWidth(requestedWidth, containerWidth: containerWidth)
        leftPanelWidthConstraint?.constant = clampedWidth
        previewFraction = Self.normalizedPreviewFraction(clampedWidth / containerWidth)
        preferences.set(Double(previewFraction), forKey: Self.previewFractionPreferenceKey)
        lastContainerWidth = containerWidth
    }

    private func resolvedPreviewWidth(for containerWidth: CGFloat) -> CGFloat {
        clampedPreviewWidth(containerWidth * previewFraction, containerWidth: containerWidth)
    }

    private func clampedPreviewWidth(_ requestedWidth: CGFloat, containerWidth: CGFloat) -> CGFloat {
        guard containerWidth >= panelMinWidth * 2 else { return max(0, containerWidth / 2) }
        return max(panelMinWidth, min(requestedWidth, containerWidth - panelMinWidth))
    }

    private static func normalizedPreviewFraction(_ fraction: CGFloat) -> CGFloat {
        max(0.2, min(fraction, 0.75))
    }

    // MARK: - Divider Dragging

    private func setupDividerDragging() {
        removeDividerEventMonitors()

        // Mouse down on divider starts drag
        dragEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            guard let self, self.currentState == .editing,
                  let divider = self.splitDivider,
                  let eventWindow = event.window,
                  eventWindow == self.view.window else { return event }

            // Check if drag started near the divider
            let locationInView = self.view.convert(event.locationInWindow, from: nil)
            let dividerFrame = divider.frame

            // Only handle drags near the divider (within 20pt for initial grab)
            if self.isDraggingDivider || abs(locationInView.x - dividerFrame.midX) < 20 {
                self.isDraggingDivider = true
                self.resizePreview(to: locationInView.x)
                return nil // Consume the event
            }
            return event
        }

        mouseUpEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] event in
            self?.isDraggingDivider = false
            return event
        }
    }

    private func removeDividerEventMonitors() {
        if let dragEventMonitor {
            NSEvent.removeMonitor(dragEventMonitor)
            self.dragEventMonitor = nil
        }
        if let mouseUpEventMonitor {
            NSEvent.removeMonitor(mouseUpEventMonitor)
            self.mouseUpEventMonitor = nil
        }
        isDraggingDivider = false
    }

    private var isDraggingDivider = false

    private func clearContent() {
        removeDividerEventMonitors()
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
        missingMediaNoticeView = nil
        importCancelButton = nil
        splitDivider = nil
        leftPanel = nil
        rightPanel = nil
        leftPanelWidthConstraint = nil
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

// MARK: - Divider View

/// A thin visible divider line with a wider hit area. Shows resize cursor on hover.
private class DividerView: NSView {
    private let lineLayer = CALayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true

        // The view is 6pt wide but only the center 1pt line is visible
        lineLayer.backgroundColor = Theme.divider.cgColor
        layer?.addSublayer(lineLayer)
    }

    override func layout() {
        super.layout()
        // Center a 1pt line in the 6pt hit area
        lineLayer.frame = CGRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        lineLayer.backgroundColor = Theme.divider.cgColor
    }
}
