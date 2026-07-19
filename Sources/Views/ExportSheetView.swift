import AppKit

/// Modal sheet for export settings and operation progress.
final class ExportSheetView: NSView {
    var onExport: ((ExportPreset, String?, Double, Bool, Bool) -> Void)?
    var onCancel: (() -> Void)?
    var onCancelExport: (() -> Void)?
    var onDismiss: (() -> Void)?

    private let formatPopup = NSPopUpButton()
    private let qualityPopup = NSPopUpButton()
    private let speedPopup = NSPopUpButton()
    private let enhanceAudioSwitch = NSSwitch()
    private let enhanceAudioDescriptionLabel = NSTextField(
        wrappingLabelWithString: "Reduces steady background noise and balances loudness in the exported media."
    )
    private let subtitleSwitch = NSSwitch()
    private let subtitleDescriptionLabel = NSTextField(
        wrappingLabelWithString: "Creates a matching .srt subtitle file beside the exported media."
    )
    private let codecDetailsLabel = NSTextField(wrappingLabelWithString: "")
    private let exportSummaryLabel = NSTextField(labelWithString: "")
    private let exportVideoButton = NSButton()
    private let cancelButton = NSButton()
    private var optionViews: [NSView] = []

    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let dismissButton = NSButton()
    private let progressCancelButton = NSButton()
    private var hasReceivedProgress = false
    private var progressStartedAt: TimeInterval?
    private var presets: [ExportPreset]
    private let sourceInfo: MediaInfo?
    private let finalDuration: Double
    private let canExportSubtitles: Bool
    private let settings: Settings?
    var progressClock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    override init(frame frameRect: NSRect) {
        presets = ExportCatalog.videoPresets + ExportCatalog.audioPresets
        sourceInfo = nil
        finalDuration = 0
        canExportSubtitles = true
        settings = nil
        super.init(frame: frameRect)
        setup()
    }

    init(
        frame frameRect: NSRect,
        presets: [ExportPreset],
        sourceInfo: MediaInfo? = nil,
        finalDuration: Double = 0,
        canExportSubtitles: Bool = true,
        settings: Settings? = nil
    ) {
        self.presets = presets
        self.sourceInfo = sourceInfo
        self.finalDuration = finalDuration
        self.canExportSubtitles = canExportSubtitles
        self.settings = settings
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        presets = ExportCatalog.videoPresets + ExportCatalog.audioPresets
        sourceInfo = nil
        finalDuration = 0
        canExportSubtitles = true
        settings = nil
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface2.cgColor
        layer?.cornerRadius = 12

        let formatLabel = makeLabel("Format:")
        formatPopup.addItems(withTitles: presets.map(\.title))
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        formatPopup.setAccessibilityLabel("Export format")
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formatPopup)

        codecDetailsLabel.font = .systemFont(ofSize: 11)
        codecDetailsLabel.textColor = Theme.textTertiary
        codecDetailsLabel.maximumNumberOfLines = 2
        codecDetailsLabel.preferredMaxLayoutWidth = 472
        codecDetailsLabel.setAccessibilityIdentifier("Export codec details")
        codecDetailsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(codecDetailsLabel)

        exportSummaryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        exportSummaryLabel.textColor = Theme.textSecondary
        exportSummaryLabel.lineBreakMode = .byTruncatingTail
        exportSummaryLabel.setAccessibilityLabel("Export summary")
        exportSummaryLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(exportSummaryLabel)

        let qualityLabel = makeLabel("Quality:")
        qualityPopup.addItems(withTitles: ["Same as source", "1080p", "720p"])
        qualityPopup.target = self
        qualityPopup.action = #selector(exportOptionChanged)
        qualityPopup.setAccessibilityLabel("Export quality")
        qualityPopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(qualityPopup)

        let speedLabel = makeLabel("Speed:")
        speedPopup.addItems(withTitles: ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x"])
        speedPopup.selectItem(withTitle: "1x")
        speedPopup.target = self
        speedPopup.action = #selector(exportOptionChanged)
        speedPopup.setAccessibilityLabel("Export speed")
        speedPopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(speedPopup)

        let enhanceAudioLabel = makeLabel("Enhance audio:")
        enhanceAudioSwitch.state = .off
        enhanceAudioSwitch.toolTip = "Reduce background noise and balance loudness"
        enhanceAudioSwitch.setAccessibilityLabel("Enhance audio")
        enhanceAudioSwitch.setAccessibilityHelp(
            "Reduces background noise and balances loudness in the exported media."
        )
        enhanceAudioSwitch.target = self
        enhanceAudioSwitch.action = #selector(exportOptionChanged)
        enhanceAudioSwitch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(enhanceAudioSwitch)

        enhanceAudioDescriptionLabel.font = .systemFont(ofSize: 11)
        enhanceAudioDescriptionLabel.textColor = Theme.textTertiary
        enhanceAudioDescriptionLabel.maximumNumberOfLines = 2
        enhanceAudioDescriptionLabel.preferredMaxLayoutWidth = 472
        enhanceAudioDescriptionLabel.setAccessibilityIdentifier("Enhance audio description")
        enhanceAudioDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(enhanceAudioDescriptionLabel)

        let subtitleLabel = makeLabel("Also export subtitles:")
        subtitleSwitch.state = .off
        subtitleSwitch.isEnabled = canExportSubtitles
        subtitleSwitch.toolTip = "Export matching SRT subtitles"
        subtitleSwitch.setAccessibilityLabel("Also export subtitles")
        subtitleSwitch.setAccessibilityHelp(
            "Creates a matching SRT subtitle file beside the exported media."
        )
        subtitleSwitch.target = self
        subtitleSwitch.action = #selector(exportOptionChanged)
        subtitleSwitch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleSwitch)

        subtitleDescriptionLabel.font = .systemFont(ofSize: 11)
        subtitleDescriptionLabel.textColor = Theme.textTertiary
        subtitleDescriptionLabel.maximumNumberOfLines = 1
        subtitleDescriptionLabel.setAccessibilityIdentifier("Subtitle export description")
        subtitleDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleDescriptionLabel)

        exportVideoButton.title = "Export Video"
        exportVideoButton.bezelStyle = .rounded
        exportVideoButton.keyEquivalent = "\r"
        exportVideoButton.target = self
        exportVideoButton.action = #selector(exportVideoClicked)
        exportVideoButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(exportVideoButton)

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)

        formatPopup.nextKeyView = qualityPopup
        qualityPopup.nextKeyView = speedPopup
        speedPopup.nextKeyView = enhanceAudioSwitch
        enhanceAudioSwitch.nextKeyView = subtitleSwitch
        subtitleSwitch.nextKeyView = exportVideoButton
        exportVideoButton.nextKeyView = cancelButton
        cancelButton.nextKeyView = formatPopup

        optionViews = [
            formatLabel, formatPopup,
            codecDetailsLabel,
            exportSummaryLabel,
            qualityLabel, qualityPopup,
            speedLabel, speedPopup,
            enhanceAudioLabel, enhanceAudioSwitch,
            enhanceAudioDescriptionLabel,
            subtitleLabel, subtitleSwitch, subtitleDescriptionLabel,
            exportVideoButton, cancelButton,
        ]

        setupProgressViews()
        restoreSavedOptions()
        updateFormatControls()

        NSLayoutConstraint.activate([
            formatLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            formatLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            formatPopup.centerYAnchor.constraint(equalTo: formatLabel.centerYAnchor),
            formatPopup.leadingAnchor.constraint(equalTo: formatLabel.trailingAnchor, constant: 8),

            codecDetailsLabel.topAnchor.constraint(equalTo: formatPopup.bottomAnchor, constant: 8),
            codecDetailsLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            codecDetailsLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            exportSummaryLabel.topAnchor.constraint(equalTo: codecDetailsLabel.bottomAnchor, constant: 10),
            exportSummaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            exportSummaryLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            qualityLabel.topAnchor.constraint(equalTo: exportSummaryLabel.bottomAnchor, constant: 14),
            qualityLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            qualityPopup.centerYAnchor.constraint(equalTo: qualityLabel.centerYAnchor),
            qualityPopup.leadingAnchor.constraint(equalTo: qualityLabel.trailingAnchor, constant: 8),

            speedLabel.topAnchor.constraint(equalTo: qualityLabel.bottomAnchor, constant: 16),
            speedLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            speedPopup.centerYAnchor.constraint(equalTo: speedLabel.centerYAnchor),
            speedPopup.leadingAnchor.constraint(equalTo: speedLabel.trailingAnchor, constant: 8),

            enhanceAudioLabel.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: 16),
            enhanceAudioLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            enhanceAudioSwitch.centerYAnchor.constraint(equalTo: enhanceAudioLabel.centerYAnchor),
            enhanceAudioSwitch.leadingAnchor.constraint(
                equalTo: enhanceAudioLabel.trailingAnchor,
                constant: 8
            ),

            enhanceAudioDescriptionLabel.topAnchor.constraint(
                equalTo: enhanceAudioLabel.bottomAnchor,
                constant: 6
            ),
            enhanceAudioDescriptionLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: 24
            ),
            enhanceAudioDescriptionLabel.trailingAnchor.constraint(
                equalTo: trailingAnchor,
                constant: -24
            ),

            subtitleLabel.topAnchor.constraint(
                equalTo: enhanceAudioDescriptionLabel.bottomAnchor,
                constant: 12
            ),
            subtitleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            subtitleSwitch.centerYAnchor.constraint(equalTo: subtitleLabel.centerYAnchor),
            subtitleSwitch.leadingAnchor.constraint(
                equalTo: subtitleLabel.trailingAnchor,
                constant: 8
            ),
            subtitleDescriptionLabel.topAnchor.constraint(
                equalTo: subtitleLabel.bottomAnchor,
                constant: 5
            ),
            subtitleDescriptionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            subtitleDescriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            exportVideoButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            exportVideoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 48),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            percentLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 8),
            percentLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorLabel.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            dismissButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressCancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            progressCancelButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = Theme.textSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        return label
    }

    private func setupProgressViews() {
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = Theme.textPrimary
        statusLabel.alignment = .center

        progressIndicator.style = .bar
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.setAccessibilityLabel("Export progress")

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        percentLabel.textColor = Theme.textTertiary
        percentLabel.alignment = .center
        percentLabel.setAccessibilityLabel("Export timing")

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.alignment = .center
        errorLabel.preferredMaxLayoutWidth = 360

        dismissButton.title = "Close"
        dismissButton.bezelStyle = .rounded
        dismissButton.keyEquivalent = "\r"
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked)

        progressCancelButton.title = "Cancel Export"
        progressCancelButton.bezelStyle = .rounded
        progressCancelButton.keyEquivalent = "\u{1b}"
        progressCancelButton.target = self
        progressCancelButton.action = #selector(cancelExportClicked)

        for view in [
            statusLabel, progressIndicator, percentLabel,
            errorLabel, dismissButton, progressCancelButton,
        ] {
            view.isHidden = true
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
    }

    @discardableResult
    func focusInitialControl(in targetWindow: NSWindow? = nil) -> Bool {
        (targetWindow ?? window)?.makeFirstResponder(formatPopup) ?? false
    }

    func showProgressMode(status: String) {
        optionViews.forEach { $0.isHidden = true }
        statusLabel.stringValue = status
        statusLabel.textColor = Theme.textPrimary
        statusLabel.isHidden = false
        hasReceivedProgress = false
        progressStartedAt = progressClock()
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        progressIndicator.isHidden = false
        percentLabel.stringValue = "00:00 elapsed"
        percentLabel.isHidden = false
        errorLabel.isHidden = true
        dismissButton.isHidden = true
        progressCancelButton.isHidden = false
        progressCancelButton.isEnabled = true
        window?.makeFirstResponder(progressCancelButton)
    }

    func updateProgress(_ percent: Double, status: String? = nil) {
        if percent > 0, !hasReceivedProgress {
            hasReceivedProgress = true
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
        }
        if hasReceivedProgress {
            progressIndicator.doubleValue = percent
            percentLabel.stringValue = Self.progressDescription(
                percent: percent,
                elapsed: elapsedProgressTime
            )
        }
        if let status {
            statusLabel.stringValue = status
        }
    }

    func showError(_ message: String) {
        statusLabel.stringValue = "Export Failed"
        statusLabel.textColor = .systemRed
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        percentLabel.isHidden = true
        errorLabel.stringValue = message
        errorLabel.isHidden = false
        progressCancelButton.isHidden = true
        dismissButton.title = "Close"
        dismissButton.isHidden = false
        window?.makeFirstResponder(dismissButton)
    }

    func showComplete() {
        statusLabel.stringValue = "Export Complete"
        statusLabel.textColor = .systemGreen
        progressIndicator.stopAnimation(nil)
        progressIndicator.isIndeterminate = false
        progressIndicator.doubleValue = 100
        percentLabel.stringValue = Self.progressDescription(
            percent: 100,
            elapsed: elapsedProgressTime
        )
        progressCancelButton.isHidden = true
        dismissButton.title = "Done"
        dismissButton.isHidden = false
        window?.makeFirstResponder(dismissButton)
    }

    func showCancelling() {
        statusLabel.stringValue = "Cancelling…"
        statusLabel.textColor = Theme.textSecondary
        progressIndicator.stopAnimation(nil)
        progressIndicator.startAnimation(nil)
        progressIndicator.isIndeterminate = true
        percentLabel.stringValue = ""
        progressCancelButton.isEnabled = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface2.cgColor
    }

    var isAudioEnhancementEnabled: Bool {
        get { enhanceAudioSwitch.state == .on }
        set { enhanceAudioSwitch.state = newValue ? .on : .off }
    }

    var isSubtitleExportEnabled: Bool {
        get { subtitleSwitch.state == .on && subtitleSwitch.isEnabled }
        set { subtitleSwitch.state = newValue && canExportSubtitles ? .on : .off }
    }

    var exportSummaryText: String {
        exportSummaryLabel.stringValue
    }

    @objc private func exportVideoClicked() {
        guard presets.indices.contains(formatPopup.indexOfSelectedItem) else { return }
        let qualities: [String?] = [nil, "1080p", "720p"]
        let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
        let preset = presets[formatPopup.indexOfSelectedItem]
        let quality = qualities[qualityPopup.indexOfSelectedItem]
        let speed = speeds[speedPopup.indexOfSelectedItem]
        settings?.exportPresetID = preset.id
        settings?.exportQuality = quality
        settings?.exportSpeed = speed
        settings?.exportEnhanceAudio = isAudioEnhancementEnabled
        settings?.exportSubtitles = isSubtitleExportEnabled
        onExport?(
            preset,
            quality,
            speed,
            isAudioEnhancementEnabled,
            isSubtitleExportEnabled
        )
    }

    @objc private func formatChanged() {
        updateFormatControls()
    }

    @objc private func exportOptionChanged() {
        updateExportSummary()
    }

    private func updateFormatControls() {
        guard presets.indices.contains(formatPopup.indexOfSelectedItem) else {
            exportVideoButton.isEnabled = false
            return
        }
        let preset = presets[formatPopup.indexOfSelectedItem]
        qualityPopup.isEnabled = preset.supportsVideoQuality
        exportVideoButton.title = preset.mediaKind == .video ? "Export Video" : "Export Audio"
        exportVideoButton.isEnabled = true
        updateCodecDetails(for: preset)
        updateExportSummary()
    }

    private func restoreSavedOptions() {
        guard let settings else { return }
        if let presetID = settings.exportPresetID,
           let index = presets.firstIndex(where: { $0.id == presetID }) {
            formatPopup.selectItem(at: index)
        }
        switch settings.exportQuality {
        case "1080p": qualityPopup.selectItem(at: 1)
        case "720p": qualityPopup.selectItem(at: 2)
        default: qualityPopup.selectItem(at: 0)
        }
        let speedTitles: [Double: String] = [
            0.5: "0.5x",
            0.75: "0.75x",
            1: "1x",
            1.25: "1.25x",
            1.5: "1.5x",
            2: "2x",
        ]
        speedPopup.selectItem(withTitle: speedTitles[settings.exportSpeed] ?? "1x")
        enhanceAudioSwitch.state = settings.exportEnhanceAudio ? .on : .off
        subtitleSwitch.state = settings.exportSubtitles && canExportSubtitles ? .on : .off
    }

    private func updateExportSummary() {
        guard presets.indices.contains(formatPopup.indexOfSelectedItem) else {
            exportSummaryLabel.stringValue = ""
            return
        }
        let preset = presets[formatPopup.indexOfSelectedItem]
        let qualities = [nil, "1080p", "720p"] as [String?]
        let speeds: [Double] = [0.5, 0.75, 1, 1.25, 1.5, 2]
        let quality = qualities.indices.contains(qualityPopup.indexOfSelectedItem)
            ? qualities[qualityPopup.indexOfSelectedItem]
            : nil
        let speed = speeds.indices.contains(speedPopup.indexOfSelectedItem)
            ? speeds[speedPopup.indexOfSelectedItem]
            : 1
        let dimensions: String
        if preset.mediaKind == .audio {
            dimensions = "Audio only"
        } else if let quality {
            dimensions = quality
        } else if let video = sourceInfo?.videoStream,
                  let width = video.width,
                  let height = video.height {
            dimensions = "\(width)×\(height)"
        } else {
            dimensions = "Same as source"
        }
        let adjustedDuration = speed > 0 ? finalDuration / speed : finalDuration
        let summary = "\(preset.pathExtension.uppercased()) · \(dimensions) · \(speedPopup.titleOfSelectedItem ?? "1x") · \(formatTime(adjustedDuration)) final"
        exportSummaryLabel.stringValue = summary
        exportSummaryLabel.setAccessibilityValue(summary)
    }

    private func updateCodecDetails(for preset: ExportPreset) {
        let audioCodec = Self.displayName(for: preset.audioCodec)
        let outputDescription: String
        if let videoCodec = preset.videoCodec {
            outputDescription = "\(Self.displayName(for: videoCodec)) video + \(audioCodec) audio"
        } else {
            outputDescription = "\(audioCodec) audio"
        }

        let convertsHEVCToH264 = sourceInfo?.videoStream?.codecName == "hevc"
            && ["libx264", "h264_videotoolbox"].contains(preset.videoCodec)
        if convertsHEVCToH264 {
            codecDetailsLabel.stringValue = "Output: \(outputDescription).\nHEVC source will be converted to H.264; the export may be larger."
            codecDetailsLabel.textColor = .systemOrange
        } else {
            codecDetailsLabel.stringValue = "Output: \(outputDescription)."
            codecDetailsLabel.textColor = Theme.textTertiary
        }
        codecDetailsLabel.setAccessibilityLabel(codecDetailsLabel.stringValue)
    }

    private var elapsedProgressTime: TimeInterval {
        guard let progressStartedAt else { return 0 }
        return max(0, progressClock() - progressStartedAt)
    }

    private static func progressDescription(
        percent: Double,
        elapsed: TimeInterval
    ) -> String {
        let boundedPercent = min(100, max(0, percent))
        let elapsedDescription = formatDuration(elapsed)
        guard boundedPercent > 0, boundedPercent < 100 else {
            if boundedPercent >= 100 {
                return "100% · \(elapsedDescription) elapsed"
            }
            return "\(elapsedDescription) elapsed"
        }
        let remaining = elapsed * (100 - boundedPercent) / boundedPercent
        return "\(Int(boundedPercent))% · \(elapsedDescription) elapsed · ~\(formatDuration(remaining)) remaining"
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private static func displayName(for codec: String) -> String {
        switch codec {
        case "libx264", "h264_videotoolbox": "H.264"
        case "hevc_videotoolbox", "libx265": "HEVC"
        case "libvpx-vp9": "VP9"
        case "aac": "AAC"
        case "libopus": "Opus"
        case "libmp3lame": "MP3"
        case "pcm_s16le": "PCM"
        default: codec
        }
    }

    @objc private func cancelClicked() { onCancel?() }
    @objc private func cancelExportClicked() { onCancelExport?() }
    @objc private func dismissClicked() { onDismiss?() }
}
