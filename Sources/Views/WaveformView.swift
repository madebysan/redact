import AppKit
import DSWaveformImage

/// Waveform visualization at the bottom of the left panel.
/// Uses DSWaveformImage for rendering. Click to seek.
class WaveformView: NSView {
    var onSeek: ((Double) -> Void)?

    private let waveformImageView = NSImageView()
    private let cutMarkerOverlay = CutMarkerOverlayView()
    private let cursorView = NSView()
    private var totalDuration: Double = 0
    private var waveformTask: Task<Void, Never>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    deinit {
        waveformTask?.cancel()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface1.cgColor

        // Waveform image
        waveformImageView.imageScaling = .scaleAxesIndependently
        waveformImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(waveformImageView)

        cutMarkerOverlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cutMarkerOverlay)

        // Cursor line
        cursorView.wantsLayer = true
        cursorView.layer?.backgroundColor = Theme.waveformCursor.cgColor
        cursorView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cursorView)

        NSLayoutConstraint.activate([
            waveformImageView.topAnchor.constraint(equalTo: topAnchor),
            waveformImageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            waveformImageView.trailingAnchor.constraint(equalTo: trailingAnchor),
            waveformImageView.bottomAnchor.constraint(equalTo: bottomAnchor),

            cutMarkerOverlay.topAnchor.constraint(equalTo: topAnchor),
            cutMarkerOverlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            cutMarkerOverlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            cutMarkerOverlay.bottomAnchor.constraint(equalTo: bottomAnchor),

            cursorView.topAnchor.constraint(equalTo: topAnchor),
            cursorView.bottomAnchor.constraint(equalTo: bottomAnchor),
            cursorView.widthAnchor.constraint(equalToConstant: 1.5),
            cursorView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
        ])
    }

    /// Show canonical removed source-time ranges over the source waveform.
    func updateDeletedRanges(_ ranges: [TimeRange], duration: Double) {
        totalDuration = duration
        cutMarkerOverlay.update(ranges: ranges, duration: duration)
    }

    /// Generate waveform from audio file.
    func loadAudio(url: URL, duration: Double) {
        totalDuration = duration
        waveformTask?.cancel()

        waveformTask = Task { [weak self] in
            do {
                let waveformAnalyzer = WaveformAnalyzer()
                let samples = try await waveformAnalyzer.samples(fromAudioAt: url, count: 200)
                try Task.checkCancellation()
                self?.renderWaveform(samples: samples)
            } catch is CancellationError {
                return
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
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

private final class CutMarkerOverlayView: NSView {
    private var ranges: [TimeRange] = []
    private var totalDuration: Double = 0

    override var isOpaque: Bool { false }

    func update(ranges: [TimeRange], duration: Double) {
        self.ranges = ranges
        totalDuration = duration
        let countDescription = ranges.count == 1 ? "1 removed range" : "\(ranges.count) removed ranges"
        setAccessibilityLabel("\(countDescription) on source waveform")
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard totalDuration > 0, bounds.width > 0 else { return }

        let fillColor = Theme.error.withAlphaComponent(0.16)
        let edgeColor = Theme.error.withAlphaComponent(0.75)
        for range in ranges {
            let startFraction = max(0, min(1, range.start / totalDuration))
            let endFraction = max(startFraction, min(1, range.end / totalDuration))
            let startX = CGFloat(startFraction) * bounds.width
            let endX = CGFloat(endFraction) * bounds.width
            let markerRect = NSRect(
                x: startX,
                y: 0,
                width: max(2, endX - startX),
                height: bounds.height
            )
            fillColor.setFill()
            markerRect.fill()

            edgeColor.setFill()
            NSRect(x: markerRect.minX, y: 0, width: 1, height: bounds.height).fill()
            NSRect(x: markerRect.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        }
    }
}
