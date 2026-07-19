import AppKit

struct WelcomeWalkthroughPage: Equatable {
    let title: String
    let body: String
    let symbolName: String?

    static let all = [
        WelcomeWalkthroughPage(
            title: "Welcome to Redact",
            body: "Edit spoken video and audio as text — cut takes and tighten pauses without a timeline.",
            symbolName: nil
        ),
        WelcomeWalkthroughPage(
            title: "Delete words, not clips",
            body: "Select words in the transcript and press Delete. Removed words stay visible, the preview updates, and every edit is undoable.",
            symbolName: "strikethrough"
        ),
        WelcomeWalkthroughPage(
            title: "Clean up automatically",
            body: "Clean Up finds filler words, repeats, and long pauses on your Mac. You review every suggestion before anything is applied.",
            symbolName: "wand.and.stars"
        ),
        WelcomeWalkthroughPage(
            title: "Edit with Claude Code or Codex",
            body: "If you use Claude Code or Codex, Redact prepares a transcript-only handoff for you to share. Your media stays on your Mac, and you review every proposed cut.",
            symbolName: "sparkles"
        ),
    ]
}

enum WelcomeWalkthroughStore {
    static let doNotShowAgainKey = "welcomeWalkthroughDoNotShowAgain"

    static func shouldPresent(using defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: doNotShowAgainKey)
    }

    static func setDoNotShowAgain(
        _ doNotShowAgain: Bool,
        using defaults: UserDefaults = .standard
    ) {
        if doNotShowAgain {
            defaults.set(true, forKey: doNotShowAgainKey)
        } else {
            defaults.removeObject(forKey: doNotShowAgainKey)
        }
    }
}

@MainActor
final class WelcomeWalkthroughView: NSView {
    var onFinish: (() -> Void)?
    var onSkip: (() -> Void)?

    private let pages: [WelcomeWalkthroughPage]
    private let applicationIcon: NSImage
    private let iconContainer = WelcomeIconContainerView()
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let footerView = WelcomeSurfaceView(color: Theme.surface2)
    private let pageIndicator: WelcomePageIndicatorView
    private let doNotShowAgainCheckbox = NSButton()
    private let skipButton = NSButton()
    private let backButton = NSButton()
    private let primaryButton = NSButton()

    private(set) var currentPageIndex = 0

    var currentTitle: String {
        pages[currentPageIndex].title
    }

    var primaryButtonTitle: String {
        primaryButton.title
    }

    var pageStatus: String {
        "Page \(currentPageIndex + 1) of \(pages.count)"
    }

    var doNotShowAgain: Bool {
        get { doNotShowAgainCheckbox.state == .on }
        set { doNotShowAgainCheckbox.state = newValue ? .on : .off }
    }

    init(
        frame frameRect: NSRect,
        pages: [WelcomeWalkthroughPage] = WelcomeWalkthroughPage.all,
        applicationIcon: NSImage,
        doNotShowAgain: Bool = false
    ) {
        precondition(!pages.isEmpty)
        self.pages = pages
        self.applicationIcon = applicationIcon
        pageIndicator = WelcomePageIndicatorView(pageCount: pages.count)
        super.init(frame: frameRect)
        setup()
        self.doNotShowAgain = doNotShowAgain
        showPage(at: 0)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool { true }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurfaceColor()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .control, .option]
        guard event.modifierFlags.intersection(disallowedModifiers).isEmpty else {
            return super.performKeyEquivalent(with: event)
        }
        switch event.keyCode {
        case 123:
            showPage(at: currentPageIndex - 1)
            return true
        case 124:
            advance()
            return true
        case 53:
            onSkip?()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onSkip?()
    }

    func showPage(at index: Int) {
        currentPageIndex = min(max(index, 0), pages.count - 1)
        let page = pages[currentPageIndex]

        titleLabel.stringValue = page.title
        bodyLabel.attributedStringValue = attributedBody(page.body)
        pageIndicator.currentPage = currentPageIndex
        pageIndicator.setAccessibilityValue(pageStatus)
        backButton.isHidden = currentPageIndex == 0
        primaryButton.title = currentPageIndex == pages.count - 1 ? "Get Started" : "Next"
        primaryButton.setAccessibilityLabel(
            currentPageIndex == pages.count - 1 ? "Get started" : "Next welcome page"
        )

        if let symbolName = page.symbolName {
            let configuration = NSImage.SymbolConfiguration(pointSize: 64, weight: .medium)
            iconView.image = NSImage(
                systemSymbolName: symbolName,
                accessibilityDescription: page.title
            )?.withSymbolConfiguration(configuration)
            iconView.contentTintColor = Theme.accent
            iconContainer.showsTintedBackground = true
        } else {
            iconView.image = applicationIcon
            iconView.contentTintColor = nil
            iconContainer.showsTintedBackground = false
        }
        iconView.setAccessibilityLabel("\(page.title) icon")
        updateKeyViewLoop()
    }

    @discardableResult
    func focusInitialControl(in window: NSWindow) -> Bool {
        updateKeyViewLoop()
        return window.makeFirstResponder(primaryButton)
    }

    private func setup() {
        wantsLayer = true
        updateSurfaceColor()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Welcome to Redact")

        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconContainer)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        titleLabel.font = .systemFont(ofSize: 24, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.alignment = .center
        titleLabel.maximumNumberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        bodyLabel.font = .systemFont(ofSize: 15)
        bodyLabel.textColor = Theme.textSecondary
        bodyLabel.alignment = .center
        bodyLabel.maximumNumberOfLines = 4
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bodyLabel)

        doNotShowAgainCheckbox.setButtonType(.switch)
        doNotShowAgainCheckbox.title = "Do not show again"
        doNotShowAgainCheckbox.font = .systemFont(ofSize: 12)
        doNotShowAgainCheckbox.setAccessibilityLabel("Do not show again")
        doNotShowAgainCheckbox.setAccessibilityHelp(
            "When selected, Redact will stop showing this welcome walkthrough at launch."
        )
        doNotShowAgainCheckbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(doNotShowAgainCheckbox)

        footerView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(footerView)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(divider)

        skipButton.title = "Skip"
        skipButton.bezelStyle = .inline
        skipButton.isBordered = false
        skipButton.target = self
        skipButton.action = #selector(skipClicked)
        skipButton.setAccessibilityLabel("Skip welcome")
        skipButton.setAccessibilityHelp("Close the walkthrough. You can reopen it from the Help menu.")
        skipButton.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(skipButton)

        backButton.title = "Back"
        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(backClicked)
        backButton.setAccessibilityLabel("Previous welcome page")
        backButton.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(backButton)

        primaryButton.title = "Next"
        primaryButton.bezelStyle = .rounded
        primaryButton.controlSize = .large
        primaryButton.keyEquivalent = "\r"
        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(primaryButton)

        pageIndicator.translatesAutoresizingMaskIntoConstraints = false
        footerView.addSubview(pageIndicator)

        NSLayoutConstraint.activate([
            iconContainer.topAnchor.constraint(equalTo: topAnchor, constant: 54),
            iconContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconContainer.widthAnchor.constraint(equalToConstant: 132),
            iconContainer.heightAnchor.constraint(equalToConstant: 132),

            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 104),
            iconView.heightAnchor.constraint(equalToConstant: 104),

            titleLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 32),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 48),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -48),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 16),
            bodyLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            bodyLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 410),

            doNotShowAgainCheckbox.centerXAnchor.constraint(equalTo: centerXAnchor),
            doNotShowAgainCheckbox.bottomAnchor.constraint(
                equalTo: footerView.topAnchor,
                constant: -16
            ),

            footerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            footerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            footerView.bottomAnchor.constraint(equalTo: bottomAnchor),
            footerView.heightAnchor.constraint(equalToConstant: 72),

            divider.topAnchor.constraint(equalTo: footerView.topAnchor),
            divider.leadingAnchor.constraint(equalTo: footerView.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: footerView.trailingAnchor),

            skipButton.leadingAnchor.constraint(equalTo: footerView.leadingAnchor, constant: 24),
            skipButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor, constant: 1),

            pageIndicator.centerXAnchor.constraint(equalTo: footerView.centerXAnchor),
            pageIndicator.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),

            primaryButton.trailingAnchor.constraint(equalTo: footerView.trailingAnchor, constant: -24),
            primaryButton.centerYAnchor.constraint(equalTo: footerView.centerYAnchor),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 104),

            backButton.trailingAnchor.constraint(equalTo: primaryButton.leadingAnchor, constant: -10),
            backButton.centerYAnchor.constraint(equalTo: primaryButton.centerYAnchor),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 72),
        ])
    }

    private func attributedBody(_ body: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineSpacing = 4
        return NSAttributedString(
            string: body,
            attributes: [
                .font: NSFont.systemFont(ofSize: 15),
                .foregroundColor: Theme.textSecondary,
                .paragraphStyle: paragraph,
            ]
        )
    }

    private func updateSurfaceColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = Theme.surface1.cgColor
        }
    }

    private func updateKeyViewLoop() {
        if backButton.isHidden {
            skipButton.nextKeyView = doNotShowAgainCheckbox
        } else {
            skipButton.nextKeyView = backButton
            backButton.nextKeyView = doNotShowAgainCheckbox
        }
        doNotShowAgainCheckbox.nextKeyView = primaryButton
        primaryButton.nextKeyView = skipButton
    }

    private func advance() {
        if currentPageIndex == pages.count - 1 {
            onFinish?()
        } else {
            showPage(at: currentPageIndex + 1)
        }
    }

    @objc private func skipClicked() {
        onSkip?()
    }

    @objc private func backClicked() {
        showPage(at: currentPageIndex - 1)
    }

    @objc private func primaryClicked() {
        advance()
    }
}

private final class WelcomeSurfaceView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
        updateSurfaceColor()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurfaceColor()
    }

    private func updateSurfaceColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = color.cgColor
        }
    }
}

private final class WelcomeIconContainerView: NSView {
    var showsTintedBackground = false {
        didSet { updateSurfaceColor() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 30
        updateSurfaceColor()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSurfaceColor()
    }

    private func updateSurfaceColor() {
        layer?.backgroundColor = showsTintedBackground
            ? Theme.accent.withAlphaComponent(0.12).cgColor
            : NSColor.clear.cgColor
    }
}

private final class WelcomePageIndicatorView: NSView {
    let pageCount: Int
    var currentPage = 0 {
        didSet { needsDisplay = true }
    }

    init(pageCount: Int) {
        self.pageCount = pageCount
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.progressIndicator)
        setAccessibilityLabel("Welcome progress")
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CGFloat(pageCount * 10 + max(0, pageCount - 1) * 8), height: 10)
    }

    override func draw(_ dirtyRect: NSRect) {
        let diameter: CGFloat = 8
        let spacing: CGFloat = 10
        let totalWidth = CGFloat(pageCount) * diameter + CGFloat(max(0, pageCount - 1)) * spacing
        let startX = (bounds.width - totalWidth) / 2
        let y = (bounds.height - diameter) / 2

        for index in 0..<pageCount {
            let rect = NSRect(
                x: startX + CGFloat(index) * (diameter + spacing),
                y: y,
                width: diameter,
                height: diameter
            )
            let color = index == currentPage ? Theme.textPrimary : Theme.textDimmed.withAlphaComponent(0.45)
            color.setFill()
            NSBezierPath(ovalIn: rect).fill()
        }
    }
}
