import AppKit
import UniformTypeIdentifiers

/// Modal sheet for export settings: format, quality, speed + progress.
class ExportSheetView: NSView {
    var onExportVideo: ((String, String?, Double) -> Void)?  // (format, quality, speed)
    var onExportSRT: (() -> Void)?
    var onCancel: (() -> Void)?

    private let formatPopup = NSPopUpButton()
    private let qualityPopup = NSPopUpButton()
    private let speedPopup = NSPopUpButton()
    private let exportVideoButton = NSButton()
    private let exportSRTButton = NSButton()
    private let cancelButton = NSButton()
    private let progressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")

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

        // Buttons
        exportVideoButton.title = "Export Video"
        exportVideoButton.bezelStyle = .rounded
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
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(cancelButton)

        // Progress
        progressIndicator.style = .bar
        progressIndicator.isIndeterminate = false
        progressIndicator.minValue = 0
        progressIndicator.maxValue = 100
        progressIndicator.isHidden = true
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressIndicator)

        progressLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        progressLabel.textColor = Theme.textTertiary
        progressLabel.isHidden = true
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(progressLabel)

        NSLayoutConstraint.activate([
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

            progressIndicator.topAnchor.constraint(equalTo: speedLabel.bottomAnchor, constant: 20),
            progressIndicator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            progressIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            progressLabel.topAnchor.constraint(equalTo: progressIndicator.bottomAnchor, constant: 4),
            progressLabel.centerXAnchor.constraint(equalTo: centerXAnchor),

            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            cancelButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),

            exportSRTButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            exportSRTButton.trailingAnchor.constraint(equalTo: exportVideoButton.leadingAnchor, constant: -12),

            exportVideoButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            exportVideoButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])
    }

    func updateProgress(_ percent: Double) {
        progressIndicator.isHidden = false
        progressLabel.isHidden = false
        progressIndicator.doubleValue = percent
        progressLabel.stringValue = "\(Int(percent))%"
    }

    func resetProgress() {
        progressIndicator.isHidden = true
        progressLabel.isHidden = true
        progressIndicator.doubleValue = 0
    }

    @objc private func exportVideoClicked() {
        let formats = ["mp4", "mkv", "webm"]
        let qualities: [String?] = [nil, "1080p", "720p"]
        let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

        let format = formats[formatPopup.indexOfSelectedItem]
        let quality = qualities[qualityPopup.indexOfSelectedItem]
        let speed = speeds[speedPopup.indexOfSelectedItem]

        onExportVideo?(format, quality, speed)
    }

    @objc private func exportSRTClicked() {
        onExportSRT?()
    }

    @objc private func cancelClicked() {
        onCancel?()
    }
}
