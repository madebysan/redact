import AppKit
import DSWaveformImage

/// Waveform visualization at the bottom of the left panel.
/// Uses DSWaveformImage for rendering. Click to seek.
class WaveformView: NSView {
    var onSeek: ((Double) -> Void)?

    private let waveformImageView = NSImageView()
    private let cursorView = NSView()
    private var totalDuration: Double = 0
    private var waveformImage: NSImage?

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

        // Waveform image
        waveformImageView.imageScaling = .scaleAxesIndependently
        waveformImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(waveformImageView)

        // Cursor line
        cursorView.wantsLayer = true
        cursorView.layer?.backgroundColor = Theme.waveformCursor.cgColor
        cursorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cursorView)

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange),
            name: .settingsChanged, object: nil
        )

        NSLayoutConstraint.activate([
            waveformImageView.topAnchor.constraint(equalTo: topAnchor),
            waveformImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            waveformImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            waveformImageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            cursorView.topAnchor.constraint(equalTo: topAnchor),
            cursorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            cursorView.widthAnchor.constraint(equalToConstant: 1.5),
            cursorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
        ])
    }

    /// Generate waveform from audio file.
    func loadAudio(url: URL, duration: Double) {
        totalDuration = duration

        Task {
            do {
                let waveformAnalyzer = WaveformAnalyzer()
                let samples = try await waveformAnalyzer.samples(fromAudioAt: url, count: 200)
                await MainActor.run {
                    self.renderWaveform(samples: samples)
                }
            } catch {
                // Silently fail — waveform is not critical
            }
        }
    }

    private func renderWaveform(samples: [Float]) {
        let width = max(bounds.width, 400)
        let height = max(bounds.height, 60)
        let size = CGSize(width: width, height: height)

        let drawer = WaveformImageDrawer()
        let configuration = Waveform.Configuration(
            size: size,
            backgroundColor: .clear,
            style: .striped(
                .init(
                    color: Theme.waveformBar,
                    width: 2,
                    spacing: 1
                )
            ),
            verticalScalingFactor: 0.8
        )

        let waveformRenderer = LinearWaveformRenderer()
        let image = drawer.waveformImage(from: samples, with: configuration, renderer: waveformRenderer)
        waveformImageView.image = image
    }

    /// Update cursor position to match current playback time.
    func updateCursor(time: Double) {
        guard totalDuration > 0, bounds.width > 0 else { return }
        let fraction = time / totalDuration
        let x = CGFloat(fraction) * bounds.width

        // Update cursor position
        cursorView.frame.origin.x = x
    }

    @objc private func settingsDidChange() {
        layer?.backgroundColor = Theme.surface1.cgColor
        cursorView.layer?.backgroundColor = Theme.waveformCursor.cgColor
    }

    // MARK: - Click to Seek

    override func mouseDown(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location), bounds.width > 0, totalDuration > 0 else { return }

        let fraction = Double(location.x / bounds.width)
        let seekTime = fraction * totalDuration
        onSeek?(seekTime)
    }
}
