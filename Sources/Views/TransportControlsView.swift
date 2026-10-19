import AppKit

private final class ScrubbableSlider: NSSlider {
    var onScrubStateChanged: ((Bool) -> Void)?

    override func mouseDown(with event: NSEvent) {
        onScrubStateChanged?(true)
        super.mouseDown(with: event)
        onScrubStateChanged?(false)
    }
}

/// Edited-timeline transport and compact cut-review controls.
final class TransportControlsView: NSView {
    var onPreviousEdit: (() -> Void)?
    var onNextEdit: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onSkipBack: (() -> Void)?
    var onSkipForward: (() -> Void)?
    var onSpeedChange: ((Float) -> Void)?
    var onVolumeChange: ((Float) -> Void)?
    var onMuteToggle: (() -> Void)?
    var onSeek: ((Double) -> Void)?

    private static let buttonSize = NSSize(width: 28, height: 28)
    private static let playButtonSize = NSSize(width: 34, height: 34)

    private var previousEditButton: IconButton!
    private var skipBackButton: IconButton!
    private var playButton: IconButton!
    private var skipForwardButton: IconButton!
    private var nextEditButton: IconButton!
    private let speedButton = NSPopUpButton()
    private var muteButton: IconButton!
    private let volumeSlider = NSSlider()
    private let topDivider = NSView()
    private let reviewSummaryLabel = NSTextField(labelWithString: "No cuts")
    private let timeLabel = NSTextField(
        labelWithString: "00:00 / 00:00 · 00:00 original"
    )
    private let progressBar = ScrubbableSlider()
    private let controlsStack = NSStackView()

    private var volumeWidthConstraint: NSLayoutConstraint?
    private var totalDuration: Double = 0
    private var isPlaying = false
    private var isScrubbing = false
    private var reviewSummaryText = "No cuts"

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

        topDivider.wantsLayer = true
        topDivider.layer?.backgroundColor = Theme.divider.cgColor
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topDivider)

        previousEditButton = makeButton(
            symbolName: "backward.end",
            label: "Previous edit",
            action: #selector(previousEditClicked)
        )
        skipBackButton = makeButton(
            symbolName: "gobackward.5",
            label: "Skip back 5 seconds",
            action: #selector(skipBackClicked)
        )
        playButton = makeButton(
            symbolName: "play.fill",
            label: "Play",
            action: #selector(playPauseClicked),
            size: Self.playButtonSize,
            pointSize: 17
        )
        skipForwardButton = makeButton(
            symbolName: "goforward.5",
            label: "Skip forward 5 seconds",
            action: #selector(skipForwardClicked)
        )
        nextEditButton = makeButton(
            symbolName: "forward.end",
            label: "Next edit",
            action: #selector(nextEditClicked)
        )
        muteButton = makeButton(
            symbolName: "speaker.wave.2.fill",
            label: "Mute preview",
            action: #selector(muteClicked)
        )

        previousEditButton.isEnabled = false
        nextEditButton.isEnabled = false

        speedButton.removeAllItems()
        speedButton.addItems(withTitles: ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x"])
        speedButton.selectItem(withTitle: "1x")
        speedButton.target = self
        speedButton.action = #selector(speedChanged)
        speedButton.isBordered = false
        speedButton.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        speedButton.contentTintColor = Theme.textSecondary
        speedButton.controlSize = .small
        speedButton.toolTip = "Playback speed"
        speedButton.setAccessibilityLabel("Playback speed")

        volumeSlider.minValue = 0
        volumeSlider.maxValue = 1
        volumeSlider.doubleValue = 1
        volumeSlider.isContinuous = true
        volumeSlider.controlSize = .small
        volumeSlider.target = self
        volumeSlider.action = #selector(volumeChanged)
        volumeSlider.setAccessibilityLabel("Preview volume")
        volumeSlider.toolTip = "Preview volume"
        volumeWidthConstraint = volumeSlider.widthAnchor.constraint(equalToConstant: 80)
        volumeWidthConstraint?.priority = .defaultHigh
        volumeWidthConstraint?.isActive = true

        controlsStack.orientation = .horizontal
        controlsStack.alignment = .centerY
        controlsStack.spacing = 2
        controlsStack.addArrangedSubview(previousEditButton)
        controlsStack.addArrangedSubview(skipBackButton)
        controlsStack.addArrangedSubview(playButton)
        controlsStack.addArrangedSubview(skipForwardButton)
        controlsStack.addArrangedSubview(nextEditButton)
        controlsStack.setCustomSpacing(12, after: nextEditButton)
        controlsStack.addArrangedSubview(speedButton)
        controlsStack.setCustomSpacing(12, after: speedButton)
        controlsStack.addArrangedSubview(muteButton)
        controlsStack.setCustomSpacing(4, after: muteButton)
        controlsStack.addArrangedSubview(volumeSlider)
        controlsStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(controlsStack)

        reviewSummaryLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        reviewSummaryLabel.textColor = Theme.textSecondary
        reviewSummaryLabel.lineBreakMode = .byTruncatingTail
        reviewSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        reviewSummaryLabel.setAccessibilityLabel("Edit summary: No cuts")
        reviewSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reviewSummaryLabel)

        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = Theme.textSecondary
        timeLabel.alignment = .right
        timeLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.isContinuous = true
        progressBar.controlSize = .small
        progressBar.target = self
        progressBar.action = #selector(progressChanged)
        progressBar.setAccessibilityLabel("Edited timeline position")
        progressBar.onScrubStateChanged = { [weak self] isScrubbing in
            self?.setScrubbing(isScrubbing)
        }
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressBar)

        NSLayoutConstraint.activate([
            topDivider.topAnchor.constraint(equalTo: topAnchor),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

            controlsStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            controlsStack.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            controlsStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),

            reviewSummaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            reviewSummaryLabel.topAnchor.constraint(equalTo: controlsStack.bottomAnchor, constant: 4),
            timeLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: reviewSummaryLabel.trailingAnchor,
                constant: 8
            ),
            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: reviewSummaryLabel.centerYAnchor),

            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            progressBar.topAnchor.constraint(greaterThanOrEqualTo: timeLabel.bottomAnchor, constant: 2),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    override func layout() {
        super.layout()
        let usesCompactControls = bounds.width < 340
        skipBackButton.isHidden = usesCompactControls
        skipForwardButton.isHidden = usesCompactControls
        volumeWidthConstraint?.constant = usesCompactControls ? 44 : 80
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface2.cgColor
        topDivider.layer?.backgroundColor = Theme.divider.cgColor
    }

    // MARK: - Public Updates

    func updateTime(current: Double, total: Double, original: Double) {
        totalDuration = total
        let currentText = formatTime(current)
        let editedText = formatTime(total)
        let originalText = formatTime(original)
        timeLabel.stringValue = "\(currentText) / \(editedText) · \(originalText) original"
        timeLabel.setAccessibilityLabel(
            "\(currentText) of \(editedText) edited, \(originalText) original"
        )
        progressBar.doubleValue = total > 0 ? current / total : 0
        progressBar.setAccessibilityValue(currentText)
    }

    func updateReviewSummary(cutCount: Int, removed: Double, final: Double) {
        let cutDescription = cutCount == 1 ? "1 cut" : "\(cutCount) cuts"
        reviewSummaryText = "\(cutDescription) · \(formatTime(removed)) removed · \(formatTime(final)) final"
        if !isScrubbing {
            reviewSummaryLabel.stringValue = reviewSummaryText
        }
        reviewSummaryLabel.setAccessibilityLabel("Edit summary: \(reviewSummaryText)")
    }

    func updateEditNavigation(previousEnabled: Bool, nextEnabled: Bool) {
        previousEditButton.isEnabled = previousEnabled
        nextEditButton.isEnabled = nextEnabled
    }

    func updatePlayingState(_ playing: Bool) {
        isPlaying = playing
        let actionLabel = playing ? "Pause" : "Play"
        playButton.image = Self.symbol(
            named: playing ? "pause.fill" : "play.fill",
            label: actionLabel,
            pointSize: 17
        )
        playButton.setAccessibilityLabel(actionLabel)
        playButton.toolTip = actionLabel
    }

    func updateVolume(_ volume: Float, muted: Bool) {
        volumeSlider.doubleValue = Double(volume)
        let symbolName: String
        if muted || volume == 0 {
            symbolName = "speaker.slash.fill"
        } else if volume < 0.34 {
            symbolName = "speaker.fill"
        } else if volume < 0.67 {
            symbolName = "speaker.wave.1.fill"
        } else {
            symbolName = "speaker.wave.2.fill"
        }
        let label = muted ? "Unmute preview" : "Mute preview"
        muteButton.image = Self.symbol(named: symbolName, label: label)
        muteButton.setAccessibilityLabel(label)
        muteButton.toolTip = label
    }

    // MARK: - Actions

    @objc private func previousEditClicked() { onPreviousEdit?() }
    @objc private func nextEditClicked() { onNextEdit?() }
    @objc private func playPauseClicked() { onPlayPause?() }
    @objc private func skipBackClicked() { onSkipBack?() }
    @objc private func skipForwardClicked() { onSkipForward?() }

    @objc private func speedChanged() {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        let index = speedButton.indexOfSelectedItem
        guard speeds.indices.contains(index) else { return }
        onSpeedChange?(speeds[index])
    }

    @objc private func volumeChanged() {
        let volume = Float(volumeSlider.doubleValue)
        volumeSlider.toolTip = "Preview volume: \(Int((volume * 100).rounded()))%"
        onVolumeChange?(volume)
    }

    @objc private func muteClicked() { onMuteToggle?() }

    @objc private func progressChanged() {
        guard totalDuration > 0 else { return }
        let seekTime = progressBar.doubleValue * totalDuration
        progressBar.toolTip = "Seek to \(formatTime(seekTime))"
        if isScrubbing {
            reviewSummaryLabel.stringValue = "Seek to \(formatTime(seekTime))"
        }
        onSeek?(seekTime)
    }

    private func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        if scrubbing {
            progressChanged()
        } else {
            reviewSummaryLabel.stringValue = reviewSummaryText
        }
    }

    private func makeButton(
        symbolName: String,
        label: String,
        action: Selector,
        size: NSSize = TransportControlsView.buttonSize,
        pointSize: CGFloat = 13
    ) -> IconButton {
        IconButton(
            image: Self.symbol(named: symbolName, label: label, pointSize: pointSize),
            title: label,
            toolTip: label,
            target: self,
            action: action,
            size: size,
            cornerRadius: 8
        )
    }

    private static func symbol(named name: String, label: String, pointSize: CGFloat = 13) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium))
    }
}
