import AVFoundation
import AVKit
import AppKit

/// Video preview area with AVPlayerView. Shows "No video loaded" placeholder when empty.
class VideoPreviewView: NSView {
    private let playerView = AVPlayerView()
    private let placeholderLabel = NSTextField(labelWithString: "No video loaded")
    private let fullScreenButton = NSButton()

    var player: AVPlayer? {
        didSet {
            playerView.player = player
            placeholderLabel.isHidden = player != nil
            playerView.isHidden = player == nil
            fullScreenButton.isHidden = player == nil
        }
    }

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
        layer?.backgroundColor = Theme.surface0.cgColor

        // Placeholder
        placeholderLabel.font = .systemFont(ofSize: 14)
        placeholderLabel.textColor = Theme.textDimmed
        placeholderLabel.alignment = .center
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(placeholderLabel)

        // Player view
        playerView.controlsStyle = .none
        playerView.translatesAutoresizingMaskIntoConstraints = false
        playerView.isHidden = true
        addSubview(playerView)

        fullScreenButton.image = NSImage(
            systemSymbolName: "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: "Enter full screen preview"
        )
        fullScreenButton.bezelStyle = .recessed
        fullScreenButton.isBordered = true
        fullScreenButton.setButtonType(.momentaryPushIn)
        fullScreenButton.setAccessibilityLabel("Enter full screen preview")
        fullScreenButton.toolTip = "Enter full screen preview"
        fullScreenButton.target = self
        fullScreenButton.action = #selector(toggleFullScreen)
        fullScreenButton.isHidden = true
        fullScreenButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fullScreenButton)

        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),

            fullScreenButton.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            fullScreenButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            fullScreenButton.widthAnchor.constraint(equalToConstant: 32),
            fullScreenButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    @objc func toggleFullScreen() {
        guard player != nil else { return }
        if isInFullScreenMode {
            exitFullScreenMode(options: nil)
            updateFullScreenButton(isFullScreen: false)
            return
        }
        guard let screen = window?.screen ?? NSScreen.main else { return }
        if enterFullScreenMode(screen, withOptions: nil) {
            updateFullScreenButton(isFullScreen: true)
        }
    }

    private func updateFullScreenButton(isFullScreen: Bool) {
        let label = isFullScreen ? "Exit full screen preview" : "Enter full screen preview"
        fullScreenButton.image = NSImage(
            systemSymbolName: isFullScreen
                ? "arrow.down.right.and.arrow.up.left"
                : "arrow.up.left.and.arrow.down.right",
            accessibilityDescription: label
        )
        fullScreenButton.setAccessibilityLabel(label)
        fullScreenButton.toolTip = label
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface0.cgColor
    }
}
