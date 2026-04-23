import AppKit

/// Shows transcription progress: spinner, status text, cancel button.
/// Intentionally indeterminate — see AppState.TranscribeProgress.
class TranscribeProgressView: NSView {
    var onCancel: (() -> Void)?

    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "Loading model…")
    private let cancelButton = NSButton()

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

        spinner.style = .spinning
        spinner.controlSize = .regular
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)

        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textColor = Theme.textSecondary
        statusLabel.alignment = .center
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -32),

            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),

            cancelButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
        ])
    }

    func updateProgress(_ progress: TranscribeProgress) {
        switch progress.status {
        case .loadingModel:
            statusLabel.stringValue = "Loading model…"
        case .transcribing:
            statusLabel.stringValue = "Transcribing…"
        case .complete:
            statusLabel.stringValue = "Processing transcript…"
        case .error:
            statusLabel.stringValue = progress.message ?? "Error"
        }
    }

    @objc private func cancelClicked() {
        onCancel?()
    }
}
