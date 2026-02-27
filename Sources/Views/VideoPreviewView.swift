import AVFoundation
import AVKit
import AppKit

/// Video preview area with AVPlayerView. Shows "No video loaded" placeholder when empty.
class VideoPreviewView: NSView {
    private let playerView = AVPlayerView()
    private let placeholderLabel = NSTextField(labelWithString: "No video loaded")

    var player: AVPlayer? {
        didSet {
            playerView.player = player
            placeholderLabel.isHidden = player != nil
            playerView.isHidden = player == nil
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

        NSLayoutConstraint.activate([
            placeholderLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            playerView.topAnchor.constraint(equalTo: topAnchor),
            playerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
