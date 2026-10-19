import AppKit

/// Modal sheet for export settings and operation progress.
final class ExportSheetView: NSView {
    var onExport: ((ExportPreset, String?, Double, Bool, ExportSidecarOptions) -> Void)?
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
    private let subtitleCheckbox = NSButton(checkboxWithTitle: "Subtitles (.srt)", target: nil, action: nil)
    private let edlCheckbox = NSButton(checkboxWithTitle: "Cut list (.edl)", target: nil, action: nil)
    private let fcpxmlCheckbox = NSButton(checkboxWithTitle: "Final Cut Pro XML", target: nil, action: nil)
    private let sidecarDescriptionLabel = NSTextField(
        wrappingLabelWithString: "Saved beside the export. Open the cut list or XML in Premiere Pro, Final Cut Pro, or DaVinci Resolve."
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
    private let canExportCutList: Bool
    private let canExportFCPXML: Bool
    private let settings: Settings?
    var progressClock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    override init(frame frameRect: NSRect) {
        presets = ExportCatalog.videoPresets + ExportCatalog.audioPresets
        sourceInfo = nil
        finalDuration = 0
        canExportSubtitles = true
        canExportCutList = true
        canExportFCPXML = true
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
        canExportCutList: Bool = true,
        canExportFCPXML: Bool = true,
        settings: Settings? = nil
    ) {
        self.presets = presets
        self.sourceInfo = sourceInfo
        self.finalDuration = finalDuration
        self.canExportSubtitles = canExportSubtitles
        self.canExportCutList = canExportCutList
        self.canExportFCPXML = canExportFCPXML
        self.settings = settings
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        presets = ExportCatalog.videoPresets + ExportCatalog.audioPresets
        sourceInfo = nil
        finalDuration = 0
        canExportSubtitles = true
        canExportCutList = true
        canExportFCPXML = true
        settings = nil
        super.init(coder: coder)
        setup()
    }

    private static let labelColumnWidth: CGFloat = 104
    private static let inset: CGFloat = 24
    private let titleLabel = NSTextField(labelWithString: "Export Video")

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface2.cgColor
        layer?.cornerRadius = 12

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary
        titleLabel.setAccessibilityRole(.staticText)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        let formatLabel = makeLabel("Format:")
        formatPopup.addItems(withTitles: presets.map(\.title))
        formatPopup.target = self
        formatPopup.action = #selector(formatChanged)
        formatPopup.setAccessibilityLabel("Export format")
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formatPopup)

        configureHelpLabel(codecDetailsLabel, identifier: "Export codec details")

        exportSummaryLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        exportSummaryLabel.textColor = Theme.textSecondary
        exportSummaryLabel.lineBreakMode = .byTruncatingTail
        exportSummaryLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        enhanceAudioSwitch.controlSize = .small
        enhanceAudioSwitch.toolTip = "Reduce background noise and balance loudness"
        enhanceAudioSwitch.setAccessibilityLabel("Enhance audio")
        enhanceAudioSwitch.setAccessibilityHelp(
            "Reduces background noise and balances loudness in the exported media."
        )
        enhanceAudioSwitch.target = self
        enhanceAudioSwitch.action = #selector(exportOptionChanged)
        enhanceAudioSwitch.translatesAutoresizingMaskIntoConstraints = false
        addSubview(enhanceAudioSwitch)

        configureHelpLabel(enhanceAudioDescriptionLabel, identifier: "Enhance audio description")

        let sidecarLabel = makeLabel("Also export:")
        configureSidecarCheckbox(
            subtitleCheckbox,
            enabled: canExportSubtitles,
            toolTip: "Export matching SRT subtitles",
            accessibilityLabel: "Also export subtitles",
            help: "Creates a matching SRT subtitle file beside the exported media."
        )
        configureSidecarCheckbox(
            edlCheckbox,
            enabled: canExportCutList,
            toolTip: "Export a CMX3600 EDL cut list for Premiere Pro or DaVinci Resolve",
            accessibilityLabel: "Also export EDL cut list",
            help: "Creates a CMX3600 edit decision list beside the exported media with one event per kept range."
        )
        configureSidecarCheckbox(
            fcpxmlCheckbox,
            enabled: canExportFCPXML,
            toolTip: "Export Final Cut Pro XML for Final Cut Pro or DaVinci Resolve",
            accessibilityLabel: "Also export Final Cut Pro XML",
            help: "Creates an FCPXML project beside the exported media with one clip per kept range."
        )

        configureHelpLabel(sidecarDescriptionLabel, identifier: "Sidecar export description")

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
        enhanceAudioSwitch.nextKeyView = subtitleCheckbox
        subtitleCheckbox.nextKeyView = edlCheckbox
        edlCheckbox.nextKeyView = fcpxmlCheckbox
        fcpxmlCheckbox.nextKeyView = cancelButton
        cancelButton.nextKeyView = exportVideoButton
        exportVideoButton.nextKeyView = formatPopup

        optionViews = [
            titleLabel,
            formatLabel, formatPopup,
            codecDetailsLabel,
            qualityLabel, qualityPopup,
            speedLabel, speedPopup,
            enhanceAudioLabel, enhanceAudioSwitch,
            enhanceAudioDescriptionLabel,
            sidecarLabel, subtitleCheckbox, edlCheckbox, fcpxmlCheckbox,
            sidecarDescriptionLabel,
            exportSummaryLabel,
            exportVideoButton, cancelButton,
        ]

        setupProgressViews()
        restoreSavedOptions()
        updateFormatControls()

        let inset = Self.inset
        let controlLeading = inset + Self.labelColumnWidth + 8
        var constraints: [NSLayoutConstraint] = [
            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -inset),

            formatPopup.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            codecDetailsLabel.topAnchor.constraint(equalTo: formatPopup.bottomAnchor, constant: 4),
            qualityPopup.topAnchor.constraint(equalTo: codecDetailsLabel.bottomAnchor, constant: 12),
            speedPopup.topAnchor.constraint(equalTo: qualityPopup.bottomAnchor, constant: 10),
            enhanceAudioSwitch.topAnchor.constraint(equalTo: speedPopup.bottomAnchor, constant: 12),
            enhanceAudioDescriptionLabel.topAnchor.constraint(
                equalTo: enhanceAudioSwitch.bottomAnchor,
                constant: 4
            ),
            subtitleCheckbox.topAnchor.constraint(
                equalTo: enhanceAudioDescriptionLabel.bottomAnchor,
                constant: 12
            ),
            edlCheckbox.topAnchor.constraint(equalTo: subtitleCheckbox.bottomAnchor, constant: 4),
            fcpxmlCheckbox.topAnchor.constraint(equalTo: edlCheckbox.bottomAnchor, constant: 4),
            sidecarDescriptionLabel.topAnchor.constraint(equalTo: fcpxmlCheckbox.bottomAnchor, constant: 4),

            exportSummaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            exportSummaryLabel.centerYAnchor.constraint(equalTo: exportVideoButton.centerYAnchor),
            exportSummaryLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: cancelButton.leadingAnchor,
                constant: -16
            ),
            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            cancelButton.trailingAnchor.constraint(equalTo: exportVideoButton.leadingAnchor, constant: -12),
            exportVideoButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            exportVideoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),

            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 48),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),
            percentLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 8),
            percentLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorLabel.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 16),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            dismissButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressCancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            progressCancelButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ]

        // Labels sit in a right-aligned column; each control starts at the shared control column.
        for (label, control) in [
            (formatLabel, formatPopup),
            (qualityLabel, qualityPopup),
            (speedLabel, speedPopup),
            (enhanceAudioLabel, enhanceAudioSwitch),
            (sidecarLabel, subtitleCheckbox),
        ] as [(NSTextField, NSView)] {
            constraints += [
                label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
                label.widthAnchor.constraint(equalToConstant: Self.labelColumnWidth),
                label.centerYAnchor.constraint(equalTo: control.centerYAnchor),
                control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: controlLeading),
            ]
        }
        for control in [edlCheckbox, fcpxmlCheckbox] {
            constraints.append(control.leadingAnchor.constraint(equalTo: leadingAnchor, constant: controlLeading))
        }
        for help in [codecDetailsLabel, enhanceAudioDescriptionLabel, sidecarDescriptionLabel] {
            constraints += [
                help.leadingAnchor.constraint(equalTo: leadingAnchor, constant: controlLeading),
                help.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    private func configureHelpLabel(_ label: NSTextField, identifier: String) {
        label.font = .systemFont(ofSize: 11)
        label.textColor = Theme.textTertiary
        label.maximumNumberOfLines = 3
        label.preferredMaxLayoutWidth = 520 - Self.inset * 2 - Self.labelColumnWidth - 8
        label.setAccessibilityIdentifier(identifier)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
    }

    private func configureSidecarCheckbox(
        _ checkbox: NSButton,
        enabled: Bool,
        toolTip: String,
        accessibilityLabel: String,
        help: String
    ) {
        checkbox.state = .off
        checkbox.isEnabled = enabled
        checkbox.font = .systemFont(ofSize: 13)
        checkbox.toolTip = toolTip
        checkbox.setAccessibilityLabel(accessibilityLabel)
        checkbox.setAccessibilityHelp(help)
        checkbox.target = self
        checkbox.action = #selector(exportOptionChanged)
        checkbox.translatesAutoresizingMaskIntoConstraints = false
        addSubview(checkbox)
    }

    private func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.textColor = Theme.textSecondary
        label.alignment = .right
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
        get { subtitleCheckbox.state == .on && subtitleCheckbox.isEnabled }
        set { subtitleCheckbox.state = newValue && canExportSubtitles ? .on : .off }
    }

    var isCutListExportEnabled: Bool {
        get { edlCheckbox.state == .on && edlCheckbox.isEnabled }
        set { edlCheckbox.state = newValue && canExportCutList ? .on : .off }
    }

    var isFCPXMLExportEnabled: Bool {
        get { fcpxmlCheckbox.state == .on && fcpxmlCheckbox.isEnabled }
        set { fcpxmlCheckbox.state = newValue && canExportFCPXML ? .on : .off }
    }

    var sidecarOptions: ExportSidecarOptions {
        ExportSidecarOptions(
            subtitles: isSubtitleExportEnabled,
            edl: isCutListExportEnabled,
            fcpxml: isFCPXMLExportEnabled
        )
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
        settings?.exportEDL = isCutListExportEnabled
        settings?.exportFCPXML = isFCPXMLExportEnabled
        onExport?(
            preset,
            quality,
            speed,
            isAudioEnhancementEnabled,
            sidecarOptions
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
        titleLabel.stringValue = exportVideoButton.title
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
        subtitleCheckbox.state = settings.exportSubtitles && canExportSubtitles ? .on : .off
        edlCheckbox.state = settings.exportEDL && canExportCutList ? .on : .off
        fcpxmlCheckbox.state = settings.exportFCPXML && canExportFCPXML ? .on : .off
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
