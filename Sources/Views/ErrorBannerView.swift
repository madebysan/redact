import AppKit

/// Red-tinted error banner that slides in below the toolbar and auto-dismisses after 5 seconds.
/// Click to dismiss immediately.
class ErrorBannerView: NSView {
    private let messageLabel = NSTextField(labelWithString: "")
    private let dismissButton = NSButton()
    private var autoDismissTimer: Timer?

    var onDismiss: (() -> Void)?

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
        layer?.backgroundColor = Theme.errorBackground.cgColor

        // Message
        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = Theme.error
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.maximumNumberOfLines = 1
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        // Dismiss button (x)
        dismissButton.bezelStyle = .inline
        dismissButton.isBordered = false
        dismissButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")
        dismissButton.contentTintColor = Theme.error
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked)
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dismissButton)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: dismissButton.leadingAnchor, constant: -8),

            dismissButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            dismissButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            dismissButton.widthAnchor.constraint(equalToConstant: 20),
            dismissButton.heightAnchor.constraint(equalToConstant: 20),
        ])

        // Click anywhere to dismiss
        let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(dismissClicked))
        addGestureRecognizer(clickGesture)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.errorBackground.cgColor
    }

    func show(message: String) {
        messageLabel.stringValue = message
        isHidden = false
        alphaValue = 0

        // Slide in
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        // Auto-dismiss after 5 seconds
        autoDismissTimer?.invalidate()
        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
            self?.dismiss()
        }
    }

    func dismiss() {
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.isHidden = true
            self?.onDismiss?()
        })
    }

    @objc private func dismissClicked() {
        dismiss()
    }
}
