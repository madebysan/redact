import AppKit

/// Persistent document recovery state shown while the transcript is editable
/// but its source media is unavailable.
final class MissingMediaNoticeView: NSView {
    var onRelink: (() -> Void)?

    private let messageLabel = NSTextField(
        labelWithString: "Source media is missing. Your transcript and edits are safe."
    )
    private let relinkButton = NSButton(title: "Relink Media…", target: nil, action: nil)
    private let dividerLayer = CALayer()

    var actionTitle: String { relinkButton.title }

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
        layer?.backgroundColor = Theme.surface2.cgColor
        dividerLayer.backgroundColor = Theme.divider.cgColor
        layer?.addSublayer(dividerLayer)

        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = Theme.textPrimary
        messageLabel.lineBreakMode = .byTruncatingTail
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(messageLabel)

        relinkButton.bezelStyle = .rounded
        relinkButton.controlSize = .small
        relinkButton.target = self
        relinkButton.action = #selector(relinkClicked)
        relinkButton.toolTip = "Choose the source media to restore preview and export"
        relinkButton.setAccessibilityLabel("Relink source media")
        relinkButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(relinkButton)

        NSLayoutConstraint.activate([
            messageLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            messageLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: relinkButton.leadingAnchor, constant: -12),
            relinkButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            relinkButton.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    override func layout() {
        super.layout()
        dividerLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: 1)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface2.cgColor
        dividerLayer.backgroundColor = Theme.divider.cgColor
    }

    func performAction() {
        onRelink?()
    }

    @objc private func relinkClicked() {
        performAction()
    }
}
