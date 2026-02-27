import AppKit
import WhisperKit

/// Preferences window with card-based layout grouped into rounded-rect sections.
class SettingsWindowController: NSWindowController {
    private static var shared: SettingsWindowController?

    static func show() {
        if let existing = shared {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = SettingsWindowController()
        shared = controller
        controller.showWindow(nil)
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.isReleasedWhenClosed = false
        window.backgroundColor = Theme.surface0
        window.setFrameAutosaveName("SettingsWindow")
        if !window.setFrameUsingName("SettingsWindow") {
            window.center()
        }

        self.init(window: window)

        // Escape key closes the window
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            if event.keyCode == 53, event.window == window {
                window?.close()
                return nil
            }
            return event
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.frame = window.contentView!.bounds

        let contentView = SettingsContentView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = contentView

        // Pin document view to clip view for vertical-only scrolling
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
        ])

        window.contentView = scrollView
    }

    override func close() {
        super.close()
        SettingsWindowController.shared = nil
    }
}

// MARK: - Curated Font List

private let curatedFonts: [(name: String, label: String)] = [
    ("System", "System Default"),
    ("Georgia", "Georgia"),
    ("Helvetica Neue", "Helvetica Neue"),
    ("Times New Roman", "Times New Roman"),
    ("Menlo", "Menlo"),
    ("SF Mono", "SF Mono"),
    ("Avenir Next", "Avenir Next"),
    ("Charter", "Charter"),
    ("Palatino", "Palatino"),
    ("Baskerville", "Baskerville"),
    ("American Typewriter", "American Typewriter"),
]

// MARK: - Highlight Color Options

private struct ColorOption {
    let color: NSColor
    let label: String
}

private let highlightColors: [ColorOption] = [
    ColorOption(color: NSColor(red: 0.231, green: 0.51, blue: 0.965, alpha: 1), label: "Blue"),
    ColorOption(color: NSColor(red: 0.518, green: 0.369, blue: 0.898, alpha: 1), label: "Purple"),
    ColorOption(color: NSColor(red: 0.235, green: 0.725, blue: 0.502, alpha: 1), label: "Green"),
    ColorOption(color: NSColor(red: 0.957, green: 0.620, blue: 0.188, alpha: 1), label: "Orange"),
]

// MARK: - Content View

private class SettingsContentView: NSView {
    private let themeControl = NSSegmentedControl()
    private let fontPopup = NSPopUpButton()
    private let fontSizeStepper = NSStepper()
    private let fontSizeLabel = NSTextField(labelWithString: "15")
    private var colorButtons: [NSButton] = []
    private let crossfadeSlider = NSSlider()
    private let crossfadeValueLabel = NSTextField(labelWithString: "70 ms")
    private let modelPopup = NSPopUpButton()
    private let modelStatusLabel = NSTextField(labelWithString: "")
    private let modelActionButton = NSButton()
    private var isModelDownloaded = false

    // ElevenLabs
    private let elevenLabsApiKeyField = NSSecureTextField()
    private let elevenLabsVoicePopup = NSPopUpButton()
    private let elevenLabsCustomVoiceField = NSTextField()

    // Theme-sensitive views for updating on theme change
    private var cardViews: [NSView] = []
    private var separatorViews: [NSView] = []
    private var rowLabels: [NSTextField] = []
    private var sectionTitleLabels: [NSTextField] = []
    private var descriptionLabels: [NSTextField] = []

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
        loadFromSettings()
        checkModelAvailability()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
        loadFromSettings()
        checkModelAvailability()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Setup

    private func setup() {
        let sections = [
            buildSection("Appearance", card: buildAppearanceCard()),
            buildSection("Transcript", card: buildTranscriptCard()),
            buildSection("Audio", card: buildAudioCard()),
            buildSection("Transcription", card: buildTranscriptionCard()),
            buildSection("ElevenLabs Voice", card: buildElevenLabsCard()),
        ]

        var prev: NSView?
        for section in sections {
            section.translatesAutoresizingMaskIntoConstraints = false
            addSubview(section)

            NSLayoutConstraint.activate([
                section.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
                section.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            ])

            if let p = prev {
                section.topAnchor.constraint(equalTo: p.bottomAnchor, constant: 24).isActive = true
            } else {
                section.topAnchor.constraint(equalTo: topAnchor, constant: 24).isActive = true
            }
            prev = section
        }
        prev?.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24).isActive = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange),
            name: .settingsChanged, object: nil
        )
    }

    // MARK: - Section & Card Builders

    private func buildSection(_ title: String, card: NSView) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .regular)
        titleLabel.textColor = Theme.textSecondary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        sectionTitleLabels.append(titleLabel)
        container.addSubview(titleLabel)

        card.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(card)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: container.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),

            card.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    private func buildCard(_ rows: [NSView]) -> NSView {
        let card = NSView()
        card.wantsLayer = true
        card.layer?.backgroundColor = Theme.surface1.cgColor
        card.layer?.cornerRadius = 10
        card.translatesAutoresizingMaskIntoConstraints = false
        cardViews.append(card)

        var prev: NSView?
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(row)

            NSLayoutConstraint.activate([
                row.leadingAnchor.constraint(equalTo: card.leadingAnchor),
                row.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            ])

            if let p = prev {
                row.topAnchor.constraint(equalTo: p.bottomAnchor).isActive = true
            } else {
                row.topAnchor.constraint(equalTo: card.topAnchor).isActive = true
            }
            prev = row
        }
        prev?.bottomAnchor.constraint(equalTo: card.bottomAnchor).isActive = true

        return card
    }

    // MARK: - Row Helpers

    private func buildRow(label: String, control: NSView) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false

        let labelView = NSTextField(labelWithString: label)
        labelView.font = .systemFont(ofSize: 13)
        labelView.textColor = Theme.textPrimary
        labelView.translatesAutoresizingMaskIntoConstraints = false
        rowLabels.append(labelView)
        row.addSubview(labelView)

        control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(control)

        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),
            labelView.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 16),
            labelView.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -16),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            labelView.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -8),
        ])

        return row
    }

    private func buildSeparator() -> NSView {
        let wrapper = NSView()
        wrapper.translatesAutoresizingMaskIntoConstraints = false

        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = Theme.divider.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        separatorViews.append(line)
        wrapper.addSubview(line)

        NSLayoutConstraint.activate([
            wrapper.heightAnchor.constraint(equalToConstant: 1),
            line.heightAnchor.constraint(equalToConstant: 1),
            line.leadingAnchor.constraint(equalTo: wrapper.leadingAnchor, constant: 16),
            line.trailingAnchor.constraint(equalTo: wrapper.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: wrapper.centerYAnchor),
        ])

        return wrapper
    }

    private func buildDescription(_ text: String) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = Theme.textTertiary
        label.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabels.append(label)
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),
        ])

        return container
    }

    // MARK: - Card Content Builders

    private func buildAppearanceCard() -> NSView {
        themeControl.segmentCount = 3
        themeControl.setLabel("Dark", forSegment: 0)
        themeControl.setLabel("Light", forSegment: 1)
        themeControl.setLabel("System", forSegment: 2)
        themeControl.segmentStyle = .rounded
        themeControl.target = self
        themeControl.action = #selector(themeChanged)

        return buildCard([
            buildRow(label: "Theme", control: themeControl),
        ])
    }

    private func buildTranscriptCard() -> NSView {
        // Font popup
        fontPopup.removeAllItems()
        for font in curatedFonts {
            fontPopup.addItem(withTitle: font.label)
            fontPopup.lastItem?.representedObject = font.name
        }
        fontPopup.target = self
        fontPopup.action = #selector(fontFamilyChanged)

        // Font size controls
        fontSizeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)

        let ptLabel = NSTextField(labelWithString: "pt")
        ptLabel.font = .systemFont(ofSize: 13)

        fontSizeStepper.minValue = 10
        fontSizeStepper.maxValue = 24
        fontSizeStepper.increment = 1
        fontSizeStepper.valueWraps = false
        fontSizeStepper.target = self
        fontSizeStepper.action = #selector(fontSizeChanged)

        let sizeStack = NSStackView(views: [fontSizeLabel, ptLabel, fontSizeStepper])
        sizeStack.spacing = 4

        // Highlight color circles
        let colorStack = NSStackView()
        colorStack.orientation = .horizontal
        colorStack.spacing = 12

        for (index, option) in highlightColors.enumerated() {
            let button = ColorCircleButton(color: option.color)
            button.toolTip = option.label
            button.tag = index
            button.target = self
            button.action = #selector(colorOptionClicked(_:))
            colorButtons.append(button)
            colorStack.addArrangedSubview(button)
        }

        return buildCard([
            buildRow(label: "Font", control: fontPopup),
            buildSeparator(),
            buildRow(label: "Size", control: sizeStack),
            buildSeparator(),
            buildRow(label: "Highlight", control: colorStack),
        ])
    }

    private func buildAudioCard() -> NSView {
        crossfadeSlider.minValue = 10
        crossfadeSlider.maxValue = 500
        crossfadeSlider.target = self
        crossfadeSlider.action = #selector(crossfadeChanged)
        crossfadeSlider.translatesAutoresizingMaskIntoConstraints = false
        crossfadeSlider.widthAnchor.constraint(equalToConstant: 180).isActive = true

        crossfadeValueLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        crossfadeValueLabel.textColor = Theme.textSecondary

        let sliderStack = NSStackView(views: [crossfadeSlider, crossfadeValueLabel])
        sliderStack.spacing = 8

        return buildCard([
            buildRow(label: "Crossfade", control: sliderStack),
            buildDescription("Audio fade in/out at cut boundaries to soften jumps between edits."),
        ])
    }

    private func buildTranscriptionCard() -> NSView {
        modelPopup.removeAllItems()
        for model in Settings.availableModels {
            modelPopup.addItem(withTitle: "\(model.label)  (\(model.size))")
            modelPopup.lastItem?.representedObject = model.id
        }
        modelPopup.target = self
        modelPopup.action = #selector(modelChanged)

        modelActionButton.bezelStyle = .rounded
        modelActionButton.controlSize = .small
        modelActionButton.target = self
        modelActionButton.action = #selector(modelActionClicked)

        let modelStack = NSStackView(views: [modelPopup, modelActionButton])
        modelStack.spacing = 8

        // Status label + static description combined below the model row
        modelStatusLabel.font = .systemFont(ofSize: 11)
        modelStatusLabel.textColor = .secondaryLabelColor

        let infoView = NSView()
        infoView.translatesAutoresizingMaskIntoConstraints = false

        modelStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        infoView.addSubview(modelStatusLabel)

        let desc = NSTextField(wrappingLabelWithString: "Larger models are more accurate but slower to download and run.")
        desc.font = .systemFont(ofSize: 11)
        desc.textColor = Theme.textTertiary
        desc.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabels.append(desc)
        infoView.addSubview(desc)

        NSLayoutConstraint.activate([
            modelStatusLabel.topAnchor.constraint(equalTo: infoView.topAnchor, constant: 4),
            modelStatusLabel.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 16),

            desc.topAnchor.constraint(equalTo: modelStatusLabel.bottomAnchor, constant: 2),
            desc.leadingAnchor.constraint(equalTo: infoView.leadingAnchor, constant: 16),
            desc.trailingAnchor.constraint(equalTo: infoView.trailingAnchor, constant: -16),
            desc.bottomAnchor.constraint(equalTo: infoView.bottomAnchor, constant: -12),
        ])

        return buildCard([
            buildRow(label: "Model", control: modelStack),
            infoView,
        ])
    }

    private func buildElevenLabsCard() -> NSView {
        elevenLabsApiKeyField.placeholderString = "xi-..."
        elevenLabsApiKeyField.target = self
        elevenLabsApiKeyField.action = #selector(elevenLabsApiKeyChanged)
        elevenLabsApiKeyField.translatesAutoresizingMaskIntoConstraints = false
        elevenLabsApiKeyField.widthAnchor.constraint(equalToConstant: 220).isActive = true

        elevenLabsVoicePopup.removeAllItems()
        for voice in Settings.popularVoices {
            elevenLabsVoicePopup.addItem(withTitle: "\(voice.name) — \(voice.description)")
            elevenLabsVoicePopup.lastItem?.representedObject = voice.id
        }
        elevenLabsVoicePopup.target = self
        elevenLabsVoicePopup.action = #selector(elevenLabsVoiceChanged)

        elevenLabsCustomVoiceField.placeholderString = "Paste a voice ID to override"
        elevenLabsCustomVoiceField.target = self
        elevenLabsCustomVoiceField.action = #selector(elevenLabsCustomVoiceChanged)
        elevenLabsCustomVoiceField.translatesAutoresizingMaskIntoConstraints = false
        elevenLabsCustomVoiceField.widthAnchor.constraint(equalToConstant: 200).isActive = true

        return buildCard([
            buildRow(label: "API Key", control: elevenLabsApiKeyField),
            buildSeparator(),
            buildRow(label: "Voice", control: elevenLabsVoicePopup),
            buildSeparator(),
            buildRow(label: "Custom ID", control: elevenLabsCustomVoiceField),
            buildDescription("Voice recreation uses ElevenLabs API tokens during export. Custom voice ID overrides the selection above."),
        ])
    }

    // MARK: - Theme Update

    @objc private func settingsDidChange() {
        window?.backgroundColor = Theme.surface0

        for card in cardViews {
            card.layer?.backgroundColor = Theme.surface1.cgColor
        }
        for sep in separatorViews {
            sep.layer?.backgroundColor = Theme.divider.cgColor
        }
        for label in rowLabels {
            label.textColor = Theme.textPrimary
        }
        for label in sectionTitleLabels {
            label.textColor = Theme.textSecondary
        }
        for label in descriptionLabels {
            label.textColor = Theme.textTertiary
        }
        crossfadeValueLabel.textColor = Theme.textSecondary
        checkModelAvailability()
    }

    // MARK: - Load Settings

    private func loadFromSettings() {
        let settings = Settings.shared

        switch settings.theme {
        case "dark": themeControl.selectedSegment = 0
        case "light": themeControl.selectedSegment = 1
        case "system": themeControl.selectedSegment = 2
        default: themeControl.selectedSegment = 0
        }

        // Select font
        let currentFont = settings.transcriptFontFamily
        for i in 0..<fontPopup.numberOfItems {
            if let fontName = fontPopup.item(at: i)?.representedObject as? String, fontName == currentFont {
                fontPopup.selectItem(at: i)
                break
            }
        }

        fontSizeStepper.doubleValue = Double(settings.transcriptFontSize)
        fontSizeLabel.stringValue = "\(Int(settings.transcriptFontSize))"

        // Highlight the selected color circle
        updateColorSelection()

        // Crossfade
        crossfadeSlider.doubleValue = settings.crossfadeMs
        crossfadeValueLabel.stringValue = "\(Int(settings.crossfadeMs)) ms"

        // Select whisper model
        let currentModel = settings.whisperModel
        for i in 0..<modelPopup.numberOfItems {
            if let modelId = modelPopup.item(at: i)?.representedObject as? String, modelId == currentModel {
                modelPopup.selectItem(at: i)
                break
            }
        }

        // ElevenLabs
        elevenLabsApiKeyField.stringValue = settings.elevenLabsApiKey

        let currentVoiceId = settings.elevenLabsVoiceId
        for i in 0..<elevenLabsVoicePopup.numberOfItems {
            if let voiceId = elevenLabsVoicePopup.item(at: i)?.representedObject as? String, voiceId == currentVoiceId {
                elevenLabsVoicePopup.selectItem(at: i)
                break
            }
        }

        elevenLabsCustomVoiceField.stringValue = settings.elevenLabsCustomVoiceId
    }

    private func updateColorSelection() {
        let current = Settings.shared.highlightColor
        for (index, button) in colorButtons.enumerated() {
            guard let circleButton = button as? ColorCircleButton else { continue }
            let option = highlightColors[index]
            let isSelected = colorsApproximatelyEqual(current, option.color)
            circleButton.isChosen = isSelected
        }
    }

    private func colorsApproximatelyEqual(_ a: NSColor, _ b: NSColor) -> Bool {
        guard let ac = a.usingColorSpace(.sRGB), let bc = b.usingColorSpace(.sRGB) else { return false }
        return abs(ac.redComponent - bc.redComponent) < 0.05
            && abs(ac.greenComponent - bc.greenComponent) < 0.05
            && abs(ac.blueComponent - bc.blueComponent) < 0.05
    }

    // MARK: - Model Status

    private func checkModelAvailability() {
        let modelId = Settings.shared.whisperModel

        // WhisperKit stores models under Documents/huggingface/ or Application Support/huggingface/
        let possibleBases = [
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
        ].compactMap { $0 }

        isModelDownloaded = possibleBases.contains { base in
            let modelDir = base
                .appendingPathComponent("huggingface/models/argmaxinc/whisperkit-coreml")
                .appendingPathComponent(modelId)
            return FileManager.default.fileExists(atPath: modelDir.path)
        }

        if isModelDownloaded {
            modelStatusLabel.stringValue = "Ready to use"
            modelStatusLabel.textColor = .systemGreen
            modelActionButton.title = "Ready"
            modelActionButton.isEnabled = false
        } else {
            modelStatusLabel.stringValue = "Will download on first use"
            modelStatusLabel.textColor = .secondaryLabelColor
            modelActionButton.title = "Download"
            modelActionButton.isEnabled = true
        }
    }

    // MARK: - Actions

    @objc private func themeChanged() {
        let themes = ["dark", "light", "system"]
        let index = themeControl.selectedSegment
        if index >= 0 && index < themes.count {
            Settings.shared.theme = themes[index]
        }
    }

    @objc private func fontFamilyChanged() {
        guard let fontName = fontPopup.selectedItem?.representedObject as? String else { return }
        Settings.shared.transcriptFontFamily = fontName
    }

    @objc private func fontSizeChanged() {
        let size = CGFloat(fontSizeStepper.doubleValue)
        fontSizeLabel.stringValue = "\(Int(size))"
        Settings.shared.transcriptFontSize = size
    }

    @objc private func colorOptionClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index >= 0, index < highlightColors.count else { return }
        Settings.shared.highlightColor = highlightColors[index].color
        updateColorSelection()
    }

    @objc private func crossfadeChanged() {
        let ms = crossfadeSlider.doubleValue
        crossfadeValueLabel.stringValue = "\(Int(ms)) ms"
        Settings.shared.crossfadeMs = ms
    }

    @objc private func modelChanged() {
        guard let modelId = modelPopup.selectedItem?.representedObject as? String else { return }
        Settings.shared.whisperModel = modelId
        checkModelAvailability()
    }

    // MARK: - ElevenLabs Actions

    @objc private func elevenLabsApiKeyChanged() {
        Settings.shared.elevenLabsApiKey = elevenLabsApiKeyField.stringValue
    }

    @objc private func elevenLabsVoiceChanged() {
        guard let voiceId = elevenLabsVoicePopup.selectedItem?.representedObject as? String else { return }
        Settings.shared.elevenLabsVoiceId = voiceId
    }

    @objc private func elevenLabsCustomVoiceChanged() {
        Settings.shared.elevenLabsCustomVoiceId = elevenLabsCustomVoiceField.stringValue
    }

    @objc private func modelActionClicked() {
        guard !isModelDownloaded else { return }

        let modelId = Settings.shared.whisperModel
        modelActionButton.title = "Downloading…"
        modelActionButton.isEnabled = false
        modelStatusLabel.stringValue = "Downloading model… 0%"
        modelStatusLabel.textColor = .secondaryLabelColor

        Task {
            do {
                let _ = try await WhisperKit.download(
                    variant: modelId,
                    from: "argmaxinc/whisperkit-coreml",
                    progressCallback: { [weak self] progress in
                        let percent = Int(progress.fractionCompleted * 100)
                        DispatchQueue.main.async {
                            self?.modelStatusLabel.stringValue = "Downloading model… \(percent)%"
                        }
                    }
                )
                await MainActor.run {
                    self.checkModelAvailability()
                }
            } catch {
                await MainActor.run {
                    self.modelStatusLabel.stringValue = "Download failed: \(error.localizedDescription)"
                    self.modelStatusLabel.textColor = .systemRed
                    self.modelActionButton.title = "Download"
                    self.modelActionButton.isEnabled = true
                }
            }
        }
    }
}

// MARK: - Color Circle Button

/// A round color swatch button with a checkmark ring when selected.
private class ColorCircleButton: NSButton {
    let swatchColor: NSColor
    private let size: CGFloat = 32
    var isChosen: Bool = false {
        didSet { needsDisplay = true }
    }

    init(color: NSColor) {
        self.swatchColor = color
        super.init(frame: NSRect(x: 0, y: 0, width: 32, height: 32))
        isBordered = false
        title = ""
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
    }

    required init?(coder: NSCoder) {
        self.swatchColor = .blue
        super.init(coder: coder)
    }

    override func draw(_ dirtyRect: NSRect) {
        if isChosen {
            // Outer selection ring
            let outerRing = NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1))
            outerRing.lineWidth = 2
            NSColor.labelColor.setStroke()
            outerRing.stroke()

            // Color circle (smaller, inside the ring with gap)
            let innerRect = bounds.insetBy(dx: 5, dy: 5)
            let inner = NSBezierPath(ovalIn: innerRect)
            swatchColor.setFill()
            inner.fill()
        } else {
            // Just the color circle, no ring
            let rect = bounds.insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(ovalIn: rect)
            swatchColor.setFill()
            path.fill()
        }
    }
}
