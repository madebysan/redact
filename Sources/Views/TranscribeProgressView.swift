import AppKit

/// Shows transcription progress: spinner, status text, progress percentage, cancel button.
class TranscribeProgressView: NSView {
    var onCancel: (() -> Void)?

    private let spinner = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "Loading model…")
    private let progressLabel = NSTextField(labelWithString: "")
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

        progressLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        progressLabel.textColor = Theme.silenceText
        progressLabel.alignment = .center
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressLabel)

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -40),

            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),

            progressLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),

            cancelButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            cancelButton.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 20),
        ])
    }

    func updateProgress(_ progress: TranscribeProgress) {
        switch progress.status {
        case .loadingModel:
            statusLabel.stringValue = "Loading model…"
        case .transcribing:
            if let pct = progress.progress {
                statusLabel.stringValue = "Transcribing…"
                progressLabel.stringValue = "\(pct)%"
            } else {
                statusLabel.stringValue = "Transcribing…"
            }
        case .refining:
            statusLabel.stringValue = "Refining word timestamps…"
            progressLabel.stringValue = ""
        case .complete:
            statusLabel.stringValue = "Processing transcript…"
            progressLabel.stringValue = ""
        case .error:
            statusLabel.stringValue = progress.message ?? "Error"
            progressLabel.stringValue = ""
        }
    }

    @objc private func cancelClicked() {
        onCancel?()
    }
}
