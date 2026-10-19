import AppKit
import DSWaveformImage

/// Waveform visualization at the bottom of the left panel.
/// Uses DSWaveformImage for rendering. Click to seek.
class WaveformView: NSView {
    var onSeek: ((Double) -> Void)?

    private let waveformImageView = NSImageView()
    private let cutMarkerOverlay = CutMarkerOverlayView()
    private let cursorView = NSView()
    private let topDivider = NSView()
    private var totalDuration: Double = 0
    private var waveformTask: Task<Void, Never>?
    private var cursorLeadingConstraint: NSLayoutConstraint?

    /// Audio is analysed once at this resolution and resampled to the pixel
    /// width of the strip whenever it is laid out.
    private static let analysisSampleCount = 4000
    private var sourceSamples: [Float] = []
    private var renderedSize: CGSize = .zero

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
        layer?.backgroundColor = Theme.surface2.cgColor

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

        topDivider.wantsLayer = true
        topDivider.layer?.backgroundColor = Theme.divider.cgColor
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topDivider)

        NSLayoutConstraint.activate([
            topDivider.topAnchor.constraint(equalTo: topAnchor),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),

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
        ])
        let cursorLeading = cursorView.leadingAnchor.constraint(equalTo: leadingAnchor)
        cursorLeading.isActive = true
        cursorLeadingConstraint = cursorLeading
    }

    /// Whether a rendered waveform image is currently installed.
    var hasRenderedWaveform: Bool {
        waveformImageView.image != nil
    }

    /// Show canonical removed source-time ranges over the source waveform.
    func updateDeletedRanges(_ ranges: [TimeRange], duration: Double) {
        totalDuration = duration
        cutMarkerOverlay.update(ranges: ranges, duration: duration)
    }

    /// Analyse the audio once; rendering happens at the strip's pixel width in `layout()`.
    func loadAudio(url: URL, duration: Double) {
        totalDuration = duration
        waveformTask?.cancel()
        sourceSamples = []
        renderedSize = .zero
        waveformImageView.image = nil

        waveformTask = Task { [weak self] in
            do {
                let waveformAnalyzer = WaveformAnalyzer()
                let samples = try await waveformAnalyzer.samples(
                    fromAudioAt: url,
                    count: Self.analysisSampleCount
                )
                try Task.checkCancellation()
                self?.sourceSamples = samples
                self?.renderedSize = .zero
                self?.renderWaveformIfNeeded()
            } catch is CancellationError {
                return
            } catch {
                // Silently fail — waveform is not critical
            }
        }
    }

    override func layout() {
        super.layout()
        renderWaveformIfNeeded()
    }

    /// The drawer only renders when it receives exactly one sample per pixel, so
    /// the analysed samples are resampled to `width × scale` before each render.
    private func renderWaveformIfNeeded() {
        guard !sourceSamples.isEmpty, bounds.width >= 1, bounds.height >= 1 else { return }
        let size = bounds.size
        guard size != renderedSize else { return }

        let scale = window?.backingScaleFactor ?? 2
        let pixelCount = max(1, Int(size.width * scale))
        let samples = Self.resample(sourceSamples, to: pixelCount)
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
            scale: scale,
            verticalScalingFactor: 0.8
        )
        let drawer = WaveformImageDrawer()
        guard let image = drawer.waveformImage(
            from: samples,
            with: configuration,
            renderer: LinearWaveformRenderer()
        ) else {
            return
        }
        waveformImageView.image = image
        renderedSize = size
    }

    /// Averages the analysed samples into `count` buckets.
    static func resample(_ samples: [Float], to count: Int) -> [Float] {
        guard count > 0, !samples.isEmpty else { return [] }
        var result: [Float] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let start = min(index * samples.count / count, samples.count - 1)
            let end = min(max(start + 1, (index + 1) * samples.count / count), samples.count)
            let bucket = samples[start..<end]
            result.append(bucket.reduce(0, +) / Float(bucket.count))
        }
        return result
    }

    /// Update cursor position to match current playback time.
    func updateCursor(time: Double) {
        guard totalDuration > 0, bounds.width > 0 else { return }
        let fraction = max(0, min(1, time / totalDuration))
        cursorLeadingConstraint?.constant = CGFloat(fraction) * bounds.width
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface2.cgColor
        topDivider.layer?.backgroundColor = Theme.divider.cgColor
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
