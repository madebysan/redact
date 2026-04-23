import AppKit
import UniformTypeIdentifiers

/// Voice option for export: use original audio or recreate with ElevenLabs.
enum ExportVoiceOption {
    case original
    case elevenLabs(voiceId: String)
}

/// Modal sheet for export settings: format, quality, speed, voice + progress.
class ExportSheetView: NSView {
    var onExportVideo: ((String, String?, Double, ExportVoiceOption) -> Void)?  // (format, quality, speed, voice)
    var onExportSRT: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCancelExport: (() -> Void)?  // cancel during progress mode
    var onDismiss: (() -> Void)?  // dismiss after completion/error

    private let elevenLabsService = ElevenLabsService()
    private var fetchedVoices: [(id: String, name: String, category: String)] = []

    // Options controls
    private let formatPopup = NSPopUpButton()
    private let qualityPopup = NSPopUpButton()
    private let speedPopup = NSPopUpButton()
    private let voiceControl = NSSegmentedControl()
    private let voicePopup = NSPopUpButton()
    private let customVoiceField = NSTextField()
    private let customVoiceLabel = NSTextField(labelWithString: "Voice ID:")
    private let voiceWarningLabel = NSTextField(labelWithString: "")
    private let exportVideoButton = NSButton()
    private let exportSRTButton = NSButton()
    private let cancelButton = NSButton()

    // All option views (to hide/show as a group)
    private var optionViews: [NSView] = []

    // Progress views
    private let progressIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let percentLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let dismissButton = NSButton()
    private let progressCancelButton = NSButton()

    /// True while we're still waiting for FFmpeg's first time= tick.
    /// During this window the bar animates indeterminately so it's clear
    /// something is happening even when percent can't yet be computed.
    private var hasReceivedProgress = false

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
        layer?.cornerRadius = 12

        // Format
        let formatLabel = NSTextField(labelWithString: "Format:")
        formatLabel.font = .systemFont(ofSize: 13)
        formatLabel.textColor = Theme.textSecondary
        formatLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formatLabel)

        formatPopup.removeAllItems()
        formatPopup.addItems(withTitles: ["MP4", "MKV", "WebM"])
        formatPopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(formatPopup)

        // Quality
        let qualityLabel = NSTextField(labelWithString: "Quality:")
        qualityLabel.font = .systemFont(ofSize: 13)
        qualityLabel.textColor = Theme.textSecondary
        qualityLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(qualityLabel)

        qualityPopup.removeAllItems()
        qualityPopup.addItems(withTitles: ["Source", "1080p", "720p"])
        qualityPopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(qualityPopup)

        // Speed
        let speedLabel = NSTextField(labelWithString: "Speed:")
        speedLabel.font = .systemFont(ofSize: 13)
        speedLabel.textColor = Theme.textSecondary
        speedLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(speedLabel)

        speedPopup.removeAllItems()
        speedPopup.addItems(withTitles: ["0.5x", "0.75x", "1x", "1.25x", "1.5x", "2x"])
        speedPopup.selectItem(withTitle: "1x")
        speedPopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(speedPopup)

        // Voice
        let voiceLabel = NSTextField(labelWithString: "Voice:")
        voiceLabel.font = .systemFont(ofSize: 13)
        voiceLabel.textColor = Theme.textSecondary
        voiceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(voiceLabel)

        voiceControl.segmentCount = 2
        voiceControl.setLabel("Original Audio", forSegment: 0)
        voiceControl.setLabel("Recreate Voice", forSegment: 1)
        voiceControl.segmentStyle = .rounded
        voiceControl.selectedSegment = 0
        voiceControl.target = self
        voiceControl.action = #selector(voiceOptionChanged)
        voiceControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(voiceControl)

        let voicePickerLabel = NSTextField(labelWithString: "Voice:")
        voicePickerLabel.font = .systemFont(ofSize: 12)
        voicePickerLabel.textColor = Theme.textSecondary
        voicePickerLabel.translatesAutoresizingMaskIntoConstraints = false
        voicePickerLabel.isHidden = true
        voicePickerLabel.tag = 900
        addSubview(voicePickerLabel)

        voicePopup.removeAllItems()
        voicePopup.addItem(withTitle: "Click \"Fetch\" to load voices")
        voicePopup.lastItem?.isEnabled = false
        voicePopup.addItem(withTitle: "Custom Voice ID")
        voicePopup.lastItem?.representedObject = "__custom__"
        voicePopup.target = self
        voicePopup.action = #selector(voicePickerChanged)
        voicePopup.isHidden = true
        voicePopup.translatesAutoresizingMaskIntoConstraints = false
        addSubview(voicePopup)

        let fetchButton = NSButton(title: "Fetch", target: self, action: #selector(fetchVoicesClicked))
        fetchButton.bezelStyle = .rounded
        fetchButton.controlSize = .small
        fetchButton.font = .systemFont(ofSize: 11)
        fetchButton.isHidden = true
        fetchButton.tag = 901
        fetchButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(fetchButton)

        customVoiceLabel.font = .systemFont(ofSize: 12)
        customVoiceLabel.textColor = Theme.textSecondary
        customVoiceLabel.isHidden = true
        customVoiceLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(customVoiceLabel)

        customVoiceField.placeholderString = "Enter voice ID"
        customVoiceField.stringValue = Settings.shared.elevenLabsCustomVoiceId
        customVoiceField.isHidden = true
        customVoiceField.translatesAutoresizingMaskIntoConstraints = false
        addSubview(customVoiceField)

        voiceWarningLabel.font = .systemFont(ofSize: 11)
        voiceWarningLabel.textColor = .systemOrange
        voiceWarningLabel.isHidden = true
        voiceWarningLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(voiceWarningLabel)

        // Buttons
        exportVideoButton.title = "Export Video"
        exportVideoButton.bezelStyle = .rounded
        exportVideoButton.keyEquivalent = "\r"
        exportVideoButton.target = self
        exportVideoButton.action = #selector(exportVideoClicked)
        exportVideoButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(exportVideoButton)

        exportSRTButton.title = "Export SRT"
        exportSRTButton.bezelStyle = .rounded
        exportSRTButton.target = self
        exportSRTButton.action = #selector(exportSRTClicked)
        exportSRTButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(exportSRTButton)

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)

        // Track all option views for batch hide/show
        optionViews = [
            formatLabel, formatPopup,
            qualityLabel, qualityPopup,
            speedLabel, speedPopup,
            voiceLabel, voiceControl, voicePickerLabel, voicePopup, fetchButton,
            customVoiceLabel, customVoiceField, voiceWarningLabel,
            exportVideoButton, exportSRTButton, cancelButton,
        ]

        // -- Progress views (hidden initially) --
        statusLabel.font = .systemFont(ofSize: 14, weight: .medium)
        statusLabel.textColor = Theme.textPrimary
        statusLabel.alignment = .center
        statusLabel.isHidden = true
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(statusLabel)

        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressIndicator)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        percentLabel.textColor = Theme.textTertiary
        percentLabel.alignment = .center
        percentLabel.isHidden = true
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(percentLabel)

        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.alignment = .center
        errorLabel.preferredMaxLayoutWidth = 360
        errorLabel.isHidden = true
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(errorLabel)

        dismissButton.title = "Close"
        dismissButton.bezelStyle = .rounded
        dismissButton.target = self
        dismissButton.action = #selector(dismissClicked)
        dismissButton.isHidden = true
        dismissButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dismissButton)

        progressCancelButton.title = "Cancel Export"
        progressCancelButton.bezelStyle = .rounded
        progressCancelButton.target = self
        progressCancelButton.action = #selector(cancelExportClicked)
        progressCancelButton.isHidden = true
        progressCancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressCancelButton)

        NSLayoutConstraint.activate([
            // Options layout
            formatLabel.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            formatLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            formatPopup.centerYAnchor.constraint(equalTo: formatLabel.centerYAnchor),
            formatPopup.leadingAnchor.constraint(equalTo: formatLabel.trailingAnchor, constant: 8),

            qualityLabel.topAnchor.constraint(equalTo: formatLabel.bottomAnchor, constant: 16),
            qualityLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            qualityPopup.centerYAnchor.constraint(equalTo: qualityLabel.centerYAnchor),
            qualityPopup.leadingAnchor.constraint(equalTo: qualityLabel.trailingAnchor, constant: 8),

            speedLabel.topAnchor.constraint(equalTo: qualityLabel.bottomAnchor, constant: 16),
            speedLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            speedPopup.centerYAnchor.constraint(equalTo: speedLabel.centerYAnchor),
            speedPopup.leadingAnchor.constraint(equalTo: speedLabel.trailingAnchor, constant: 8),

            voiceLabel.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: 20),
            voiceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

            voiceControl.topAnchor.constraint(equalTo: voiceLabel.bottomAnchor, constant: 8),
            voiceControl.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

            voicePickerLabel.topAnchor.constraint(equalTo: voiceControl.bottomAnchor, constant: 10),
            voicePickerLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

            voicePopup.centerYAnchor.constraint(equalTo: voicePickerLabel.centerYAnchor),
            voicePopup.leadingAnchor.constraint(equalTo: voicePickerLabel.trailingAnchor, constant: 8),
            voicePopup.widthAnchor.constraint(equalToConstant: 200),

            fetchButton.centerYAnchor.constraint(equalTo: voicePopup.centerYAnchor),
            fetchButton.leadingAnchor.constraint(equalTo: voicePopup.trailingAnchor, constant: 6),

            customVoiceLabel.topAnchor.constraint(equalTo: voicePopup.bottomAnchor, constant: 8),
            customVoiceLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

            customVoiceField.centerYAnchor.constraint(equalTo: customVoiceLabel.centerYAnchor),
            customVoiceField.leadingAnchor.constraint(equalTo: customVoiceLabel.trailingAnchor, constant: 8),
            customVoiceField.widthAnchor.constraint(equalToConstant: 220),

            voiceWarningLabel.topAnchor.constraint(equalTo: customVoiceLabel.bottomAnchor, constant: 6),
            voiceWarningLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

            exportSRTButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            exportSRTButton.trailingAnchor.constraint(equalTo: exportVideoButton.leadingAnchor, constant: -12),

            exportVideoButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            exportVideoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            // Progress layout (centered in sheet)
            statusLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            statusLabel.topAnchor.constraint(equalTo: topAnchor, constant: 48),
            statusLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            progressIndicator.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 20),
            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 40),
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -40),

            percentLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 8),
            percentLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            errorLabel.topAnchor.constraint(equalTo: percentLabel.bottomAnchor, constant: 16),
            errorLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            errorLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            errorLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            dismissButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            dismissButton.centerXAnchor.constraint(equalTo: centerXAnchor),

            progressCancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            progressCancelButton.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
    }

    // MARK: - Progress Mode

    /// Switch to progress mode: hide options, show progress bar + status.
    /// Starts indeterminate — flips to determinate on the first updateProgress call
    /// (after ffmpeg's filter graph setup completes and encoding actually begins).
    func showProgressMode(status: String) {
        for view in optionViews { view.isHidden = true }
        statusLabel.stringValue = status
        statusLabel.textColor = Theme.textPrimary
        statusLabel.isHidden = false

        hasReceivedProgress = false
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        progressIndicator.isHidden = false

        percentLabel.stringValue = ""
        percentLabel.isHidden = false

        errorLabel.isHidden = true
        dismissButton.isHidden = true
        progressCancelButton.isHidden = false
    }

    /// Update the progress bar and status text. A call with percent > 0 flips
    /// the indicator from indeterminate to determinate — until then we're still
    /// in "working on it, no ETA yet" territory.
    func updateProgress(_ percent: Double, status: String? = nil) {
        if percent > 0, !hasReceivedProgress {
            hasReceivedProgress = true
            progressIndicator.stopAnimation(nil)
            progressIndicator.isIndeterminate = false
        }
        if hasReceivedProgress {
            progressIndicator.doubleValue = percent
            percentLabel.stringValue = "\(Int(percent))%"
        }
        if let status {
            statusLabel.stringValue = status
        }
    }

    /// Show an error in the progress view.
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
    }

    /// Show success in the progress view.
    func showComplete() {
        statusLabel.stringValue = "Export Complete"
        statusLabel.textColor = .systemGreen
        progressIndicator.stopAnimation(nil)
        progressIndicator.isIndeterminate = false
        progressIndicator.doubleValue = 100
        percentLabel.stringValue = "100%"
        progressCancelButton.isHidden = true
        dismissButton.title = "Done"
        dismissButton.isHidden = false
    }

    /// Show a "cancelling…" state while the ffmpeg subprocess is shutting down.
    func showCancelling() {
        statusLabel.stringValue = "Cancelling…"
        statusLabel.textColor = Theme.textSecondary
        progressIndicator.stopAnimation(nil)
        progressIndicator.startAnimation(nil)
        progressIndicator.isIndeterminate = true
        percentLabel.stringValue = ""
        progressCancelButton.isEnabled = false
    }

    // MARK: - Actions

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface2.cgColor
    }

    @objc private func voiceOptionChanged() {
        let recreate = voiceControl.selectedSegment == 1
        let pickerLabel = subviews.first { $0.tag == 900 }
        let fetchBtn = subviews.first { $0.tag == 901 }
        pickerLabel?.isHidden = !recreate
        voicePopup.isHidden = !recreate
        fetchBtn?.isHidden = !recreate

        if recreate {
            updateCustomVoiceVisibility()
            updateVoiceWarning()
            // Auto-fetch voices if we haven't yet and API key is set
            if fetchedVoices.isEmpty && !Settings.shared.elevenLabsApiKey.isEmpty {
                fetchVoicesClicked()
            }
        } else {
            customVoiceLabel.isHidden = true
            customVoiceField.isHidden = true
            voiceWarningLabel.isHidden = true
            exportVideoButton.isEnabled = true
        }
    }

    @objc private func voicePickerChanged() {
        updateCustomVoiceVisibility()
    }

    private func updateCustomVoiceVisibility() {
        let isCustom = (voicePopup.selectedItem?.representedObject as? String) == "__custom__"
        customVoiceLabel.isHidden = !isCustom
        customVoiceField.isHidden = !isCustom
    }

    private func updateVoiceWarning() {
        let apiKey = Settings.shared.elevenLabsApiKey
        if apiKey.isEmpty {
            voiceWarningLabel.stringValue = "API key not configured. Set it in Preferences."
            voiceWarningLabel.isHidden = false
            exportVideoButton.isEnabled = false
        } else {
            voiceWarningLabel.isHidden = true
            exportVideoButton.isEnabled = true
        }
    }

    private func selectedVoiceOption() -> ExportVoiceOption {
        guard voiceControl.selectedSegment == 1 else {
            return .original
        }

        if let voiceId = voicePopup.selectedItem?.representedObject as? String, voiceId != "__custom__" {
            return .elevenLabs(voiceId: voiceId)
        }

        let customId = customVoiceField.stringValue.trimmingCharacters(in: .whitespaces)
        if !customId.isEmpty {
            return .elevenLabs(voiceId: customId)
        }

        let settingsCustomId = Settings.shared.elevenLabsCustomVoiceId.trimmingCharacters(in: .whitespaces)
        if !settingsCustomId.isEmpty {
            return .elevenLabs(voiceId: settingsCustomId)
        }

        return .original
    }

    @objc private func fetchVoicesClicked() {
        let apiKey = Settings.shared.elevenLabsApiKey
        guard !apiKey.isEmpty else {
            voiceWarningLabel.stringValue = "API key not configured. Set it in Preferences."
            voiceWarningLabel.isHidden = false
            return
        }

        let fetchBtn = subviews.first { $0.tag == 901 } as? NSButton
        fetchBtn?.isEnabled = false
        fetchBtn?.title = "Loading..."

        Task {
            do {
                let voices = try await elevenLabsService.listVoices(apiKey: apiKey)
                await MainActor.run {
                    self.fetchedVoices = voices
                    self.voicePopup.removeAllItems()
                    for voice in voices {
                        let label = voice.category.isEmpty ? voice.name : "\(voice.name) (\(voice.category))"
                        self.voicePopup.addItem(withTitle: label)
                        self.voicePopup.lastItem?.representedObject = voice.id
                    }
                    self.voicePopup.addItem(withTitle: "Custom Voice ID")
                    self.voicePopup.lastItem?.representedObject = "__custom__"
                    fetchBtn?.title = "Fetch"
                    fetchBtn?.isEnabled = true
                    self.voiceWarningLabel.isHidden = true
                }
            } catch {
                await MainActor.run {
                    self.voiceWarningLabel.stringValue = "Failed to fetch voices: \(error.localizedDescription)"
                    self.voiceWarningLabel.isHidden = false
                    fetchBtn?.title = "Retry"
                    fetchBtn?.isEnabled = true
                }
            }
        }
    }

    @objc private func exportVideoClicked() {
        let formats = ["mp4", "mkv", "webm"]
        let qualities: [String?] = [nil, "1080p", "720p"]
        let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

        let format = formats[formatPopup.indexOfSelectedItem]
        let quality = qualities[qualityPopup.indexOfSelectedItem]
        let speed = speeds[speedPopup.indexOfSelectedItem]
        let voice = selectedVoiceOption()

        onExportVideo?(format, quality, speed, voice)
    }

    @objc private func exportSRTClicked() {
        onExportSRT?()
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    @objc private func cancelExportClicked() {
        onCancelExport?()
    }

    @objc private func dismissClicked() {
        onDismiss?()
    }
}
