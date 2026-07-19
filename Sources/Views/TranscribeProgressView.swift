import AppKit

/// Shows a quiet, cancellable transcription state without exposing raw model output.
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

        statusLabel.font = .systemFont(ofSize: 16, weight: .medium)
        statusLabel.textColor = Theme.textSecondary
        statusLabel.alignment = .center

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        let stack = NSStackView(views: [
            spinner,
            statusLabel,
            cancelButton,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),
        ])
    }

    func updateProgress(_ progress: TranscribeProgress) {
        switch progress.status {
        case .loadingModel:
            statusLabel.stringValue = "Loading model…"
        case .transcribing:
            statusLabel.stringValue = progress.message ?? "Transcribing…"
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
