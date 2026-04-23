import AppKit

/// Transport controls: play/pause, skip back/forward, speed selector, seekable progress bar, time display.
class TransportControlsView: NSView {
    var onPlayPause: (() -> Void)?
    var onSkipBack: (() -> Void)?
    var onSkipForward: (() -> Void)?
    var onSpeedChange: ((Float) -> Void)?
    var onSeek: ((Double) -> Void)?

    private let playButton = NSButton()
    private let skipBackButton = NSButton()
    private let skipForwardButton = NSButton()
    private let speedButton = NSPopUpButton()
    private let timeLabel = NSTextField(labelWithString: "00:00 / 00:00")
    private let progressBar = NSSlider()

    private var totalDuration: Double = 0
    private var isPlaying = false

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
        layer?.backgroundColor = Theme.surface1.cgColor

        // Skip Back
        skipBackButton.image = NSImage(systemSymbolName: "gobackward.5", accessibilityDescription: "Skip back 5s")
        skipBackButton.bezelStyle = .inline
        skipBackButton.isBordered = false
        skipBackButton.target = self
        skipBackButton.action = #selector(skipBackClicked)
        skipBackButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(skipBackButton)

        // Play/Pause
        playButton.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Play")
        playButton.bezelStyle = .inline
        playButton.isBordered = false
        playButton.target = self
        playButton.action = #selector(playPauseClicked)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playButton)

        // Skip Forward
        skipForwardButton.image = NSImage(systemSymbolName: "goforward.5", accessibilityDescription: "Skip forward 5s")
        skipForwardButton.bezelStyle = .inline
        skipForwardButton.isBordered = false
        skipForwardButton.target = self
        skipForwardButton.action = #selector(skipForwardClicked)
        skipForwardButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(skipForwardButton)

        // Speed selector
        speedButton.removeAllItems()
        speedButton.addItems(withTitles: ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x"])
        speedButton.selectItem(withTitle: "1x")
        speedButton.target = self
        speedButton.action = #selector(speedChanged)
        speedButton.controlSize = .small
        speedButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(speedButton)

        // Time label
        timeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        timeLabel.textColor = Theme.textTertiary
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(timeLabel)

        // Progress bar
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.doubleValue = 0
        progressBar.target = self
        progressBar.action = #selector(progressChanged)
        progressBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressBar)

        NSLayoutConstraint.activate([
            // Controls row
            skipBackButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            skipBackButton.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            skipBackButton.widthAnchor.constraint(equalToConstant: 28),
            skipBackButton.heightAnchor.constraint(equalToConstant: 28),

            playButton.leadingAnchor.constraint(equalTo: skipBackButton.trailingAnchor, constant: 4),
            playButton.centerYAnchor.constraint(equalTo: skipBackButton.centerYAnchor),
            playButton.widthAnchor.constraint(equalToConstant: 32),
            playButton.heightAnchor.constraint(equalToConstant: 32),

            skipForwardButton.leadingAnchor.constraint(equalTo: playButton.trailingAnchor, constant: 4),
            skipForwardButton.centerYAnchor.constraint(equalTo: skipBackButton.centerYAnchor),
            skipForwardButton.widthAnchor.constraint(equalToConstant: 28),
            skipForwardButton.heightAnchor.constraint(equalToConstant: 28),

            speedButton.leadingAnchor.constraint(equalTo: skipForwardButton.trailingAnchor, constant: 12),
            speedButton.centerYAnchor.constraint(equalTo: skipBackButton.centerYAnchor),

            timeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            timeLabel.centerYAnchor.constraint(equalTo: skipBackButton.centerYAnchor),

            // Progress bar (full width below controls)
            progressBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            progressBar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            progressBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface1.cgColor
    }

    // MARK: - Public Updates

    func updateTime(current: Double, total: Double) {
        totalDuration = total
        timeLabel.stringValue = "\(formatTime(current)) / \(formatTime(total))"
        if total > 0 {
            progressBar.doubleValue = current / total
        }
    }

    func updatePlayingState(_ playing: Bool) {
        isPlaying = playing
        playButton.image = NSImage(
            systemSymbolName: playing ? "pause.fill" : "play.fill",
            accessibilityDescription: playing ? "Pause" : "Play"
        )
    }

    // MARK: - Actions

    @objc private func playPauseClicked() {
        onPlayPause?()
    }

    @objc private func skipBackClicked() {
        onSkipBack?()
    }

    @objc private func skipForwardClicked() {
        onSkipForward?()
    }

    @objc private func speedChanged() {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
        let idx = speedButton.indexOfSelectedItem
        if idx >= 0 && idx < speeds.count {
            onSpeedChange?(speeds[idx])
        }
    }

    @objc private func progressChanged() {
        guard totalDuration > 0 else { return }
        let seekTime = progressBar.doubleValue * totalDuration
        onSeek?(seekTime)
    }
}
