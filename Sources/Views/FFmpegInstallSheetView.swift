import AppKit

/// Sheet that explains the FFmpeg download, runs it with progress, and reports errors.
///
/// Shown when import or export needs FFmpeg and none is installed. The same
/// view moves through three modes: the offer, the download, and a failure.
final class FFmpegInstallSheetView: NSView {
    static let defaultSize = NSSize(width: 520, height: 300)

    var onInstall: (() -> Void)?
    var onNotNow: (() -> Void)?
    var onCancelInstall: (() -> Void)?
    var onClose: (() -> Void)?

    private let distribution: FFmpegDistribution

    private let titleLabel = NSTextField(labelWithString: "Install FFmpeg")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let detailsLabel = NSTextField(wrappingLabelWithString: "")
    private let sourceLinkButton = NSButton()
    private let installButton = NSButton()
    private let notNowButton = NSButton()
    private var offerViews: [NSView] = []

    private let statusLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let progressDetailLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let cancelInstallButton = NSButton()
    private let closeButton = NSButton()
    private let tryAgainButton = NSButton()
    private var progressViews: [NSView] = []

    private(set) var isInstalling = false

    var installButtonTitle: String { installButton.title }
    var statusText: String { statusLabel.stringValue }
    var bodyText: String { bodyLabel.stringValue }
    var detailsText: String { detailsLabel.stringValue }

    init(frame frameRect: NSRect, distribution: FFmpegDistribution = .current) {
        self.distribution = distribution
        super.init(frame: frameRect)
        setup()
    }

    override init(frame frameRect: NSRect) {
        distribution = .current
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        distribution = .current
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface2.cgColor
        layer?.cornerRadius = 12

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary

        bodyLabel.stringValue = "Redact uses FFmpeg to read your media and export the edit, and it isn't installed on this Mac yet. Redact can download it for you and keep it in its own Application Support folder. Nothing else on your Mac changes."
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = Theme.textSecondary
        bodyLabel.preferredMaxLayoutWidth = 472

        detailsLabel.stringValue = "FFmpeg \(distribution.version) for Apple Silicon · \(distribution.formattedDownloadSize) download from \(distribution.sourceName) · \(distribution.licenseName) · verified against the published checksum before it runs."
        detailsLabel.font = .systemFont(ofSize: 11)
        detailsLabel.textColor = Theme.textTertiary
        detailsLabel.preferredMaxLayoutWidth = 472
        detailsLabel.setAccessibilityIdentifier("FFmpeg install details")

        sourceLinkButton.title = "About this build"
        sourceLinkButton.bezelStyle = .inline
        sourceLinkButton.isBordered = false
        sourceLinkButton.font = .systemFont(ofSize: 11)
        sourceLinkButton.contentTintColor = Theme.accent
        sourceLinkButton.target = self
        sourceLinkButton.action = #selector(openSourcePage)
        sourceLinkButton.toolTip = distribution.sourceURL.absoluteString
        sourceLinkButton.setAccessibilityLabel("About this FFmpeg build")

        installButton.title = "Install FFmpeg"
        installButton.bezelStyle = .rounded
        installButton.keyEquivalent = "\r"
        installButton.target = self
        installButton.action = #selector(installClicked)
        installButton.setAccessibilityLabel("Install FFmpeg")

        notNowButton.title = "Not Now"
        notNowButton.bezelStyle = .rounded
        notNowButton.keyEquivalent = "\u{1b}"
        notNowButton.target = self
        notNowButton.action = #selector(notNowClicked)

        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = Theme.textPrimary
        statusLabel.alignment = .center

        progressIndicator.style = .bar
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 1
        progressIndicator.setAccessibilityLabel("FFmpeg install progress")

        progressDetailLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        progressDetailLabel.textColor = Theme.textTertiary
        progressDetailLabel.alignment = .center

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.alignment = .center
        errorLabel.preferredMaxLayoutWidth = 440

        cancelInstallButton.title = "Cancel"
        cancelInstallButton.bezelStyle = .rounded
        cancelInstallButton.keyEquivalent = "\u{1b}"
        cancelInstallButton.target = self
        cancelInstallButton.action = #selector(cancelInstallClicked)

        closeButton.title = "Close"
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}"
        closeButton.target = self
        closeButton.action = #selector(closeClicked)

        tryAgainButton.title = "Try Again"
        tryAgainButton.bezelStyle = .rounded
        tryAgainButton.keyEquivalent = "\r"
        tryAgainButton.target = self
        tryAgainButton.action = #selector(installClicked)

        offerViews = [titleLabel, bodyLabel, detailsLabel, sourceLinkButton, installButton, notNowButton]
        progressViews = [
            statusLabel, progressIndicator, progressDetailLabel, errorLabel,
            cancelInstallButton, closeButton, tryAgainButton,
        ]
        for view in offerViews + progressViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        installButton.nextKeyView = notNowButton
        notNowButton.nextKeyView = sourceLinkButton
        sourceLinkButton.nextKeyView = installButton

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            bodyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            bodyLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            detailsLabel.topAnchor.constraint(equalTo: bodyLabel.bottomAnchor, constant: 14),
            detailsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            detailsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            sourceLinkButton.topAnchor.constraint(equalTo: detailsLabel.bottomAnchor, constant: 6),
            sourceLinkButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 22),

            notNowButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            notNowButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            installButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            installButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 48),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            progressDetailLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 8),
            progressDetailLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorLabel.topAnchor.constraint(equalTo: progressDetailLabel.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            cancelInstallButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            cancelInstallButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            closeButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            tryAgainButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            tryAgainButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])

        showOffer()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface2.cgColor
    }

    // MARK: - Modes

    func showOffer() {
        isInstalling = false
        offerViews.forEach { $0.isHidden = false }
        progressViews.forEach { $0.isHidden = true }
        progressIndicator.stopAnimation(nil)
        window?.makeFirstResponder(installButton)
    }

    func showInstalling() {
        isInstalling = true
        offerViews.forEach { $0.isHidden = true }
        progressViews.forEach { $0.isHidden = true }
        statusLabel.stringValue = "Preparing download…"
        statusLabel.textColor = Theme.textPrimary
        statusLabel.isHidden = false
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        progressIndicator.isHidden = false
        progressDetailLabel.stringValue = ""
        progressDetailLabel.isHidden = false
        cancelInstallButton.isEnabled = true
        cancelInstallButton.isHidden = false
        window?.makeFirstResponder(cancelInstallButton)
    }

    func updateProgress(_ progress: ManagedFFmpegInstallProgress) {
        guard isInstalling else { return }
        if progressIndicator.isIndeterminate {
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
        }
        progressIndicator.doubleValue = progress.fraction
        statusLabel.stringValue = progress.statusText
        progressDetailLabel.stringValue = progress.detailText
    }

    func showCancelling() {
        statusLabel.stringValue = "Cancelling…"
        statusLabel.textColor = Theme.textSecondary
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        progressDetailLabel.stringValue = ""
        cancelInstallButton.isEnabled = false
    }

    func showError(_ message: String) {
        isInstalling = false
        offerViews.forEach { $0.isHidden = true }
        progressViews.forEach { $0.isHidden = true }
        statusLabel.stringValue = "Install Failed"
        statusLabel.textColor = .systemRed
        statusLabel.isHidden = false
        progressIndicator.stopAnimation(nil)
        progressDetailLabel.stringValue = ""
        progressDetailLabel.isHidden = false
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        closeButton.isHidden = false
        tryAgainButton.isHidden = false
        window?.makeFirstResponder(tryAgainButton)
    }

    @discardableResult
    func focusInitialControl(in targetWindow: NSWindow? = nil) -> Bool {
        (targetWindow ?? window)?.makeFirstResponder(installButton) ?? false
    }

    // MARK: - Actions

    @objc private func installClicked() {
        onInstall?()
    }

    @objc private func notNowClicked() {
        onNotNow?()
    }

    @objc private func cancelInstallClicked() {
        onCancelInstall?()
    }

    @objc private func closeClicked() {
        onClose?()
    }

    @objc private func openSourcePage() {
        NSWorkspace.shared.open(distribution.sourceURL)
    }
}
