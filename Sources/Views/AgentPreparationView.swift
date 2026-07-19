import AppKit

/// Explains the privacy boundary and prepares a copy-ready agent connection prompt.
final class AgentPreparationView: NSView {
    var onPrepare: ((AgentProvider) -> Void)?
    var onCancel: (() -> Void)?

    private let agentPopup = NSPopUpButton()
    private let prepareButton = NSButton()
    private let cancelButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    var selectedAgent: AgentProvider {
        AgentProvider.allCases[safe: agentPopup.indexOfSelectedItem] ?? .codex
    }

    @discardableResult
    func focusInitialControl(in targetWindow: NSWindow? = nil) -> Bool {
        (targetWindow ?? window)?.makeFirstResponder(agentPopup) ?? false
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface2.cgColor
        layer?.cornerRadius = 12

        let titleLabel = NSTextField(labelWithString: "Edit with Agent")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary

        let disclosureLabel = NSTextField(
            wrappingLabelWithString: "Redact will create a privacy-safe transcript snapshot and copy a connection prompt. Paste it into Codex or Claude Code. After the agent confirms it is connected, describe the edit you want there."
        )
        disclosureLabel.font = .systemFont(ofSize: 12)
        disclosureLabel.textColor = Theme.textSecondary
        disclosureLabel.maximumNumberOfLines = 3

        let privacyLabel = NSTextField(
            wrappingLabelWithString: "The snapshot contains transcript text, word timing, and current deletions. Source media, source file paths, bookmarks, and media fingerprints are not included."
        )
        privacyLabel.font = .systemFont(ofSize: 11)
        privacyLabel.textColor = Theme.textTertiary
        privacyLabel.maximumNumberOfLines = 2

        let agentLabel = NSTextField(labelWithString: "Agent")
        agentLabel.font = .systemFont(ofSize: 12, weight: .medium)
        agentLabel.textColor = Theme.textPrimary

        agentPopup.addItems(withTitles: AgentProvider.allCases.map(\.displayName))
        agentPopup.setAccessibilityLabel("Agent")
        agentPopup.setAccessibilityHelp("Choose where you will paste the Redact connection prompt.")

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)

        prepareButton.title = "Prepare & Copy Prompt"
        prepareButton.bezelStyle = .rounded
        prepareButton.keyEquivalent = "\r"
        prepareButton.target = self
        prepareButton.action = #selector(prepareClicked)

        for view in [
            titleLabel, disclosureLabel, privacyLabel, agentLabel, agentPopup,
            cancelButton, prepareButton,
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        agentPopup.nextKeyView = cancelButton
        cancelButton.nextKeyView = prepareButton
        prepareButton.nextKeyView = agentPopup

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            disclosureLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            disclosureLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            disclosureLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            privacyLabel.topAnchor.constraint(equalTo: disclosureLabel.bottomAnchor, constant: 10),
            privacyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            privacyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            agentLabel.topAnchor.constraint(equalTo: privacyLabel.bottomAnchor, constant: 16),
            agentLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            agentPopup.centerYAnchor.constraint(equalTo: agentLabel.centerYAnchor),
            agentPopup.leadingAnchor.constraint(equalTo: agentLabel.trailingAnchor, constant: 12),
            agentPopup.widthAnchor.constraint(greaterThanOrEqualToConstant: 150),

            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            cancelButton.trailingAnchor.constraint(equalTo: prepareButton.leadingAnchor, constant: -12),
            prepareButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            prepareButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])

    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface2.cgColor
    }

    @objc private func prepareClicked() {
        onPrepare?(selectedAgent)
    }

    @objc private func cancelClicked() {
        onCancel?()
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
