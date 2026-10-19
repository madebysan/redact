import AppKit

/// Borderless symbol button shared by the toolbar capsules and the transport row:
/// a quiet hover fill, a firmer pressed fill, and dimmed disabled state, so every
/// icon action in the app belongs to one control family.
class IconButton: NSButton {
    let fixedSize: NSSize

    private var pointerIsInside = false
    private var trackingRegion: NSTrackingArea?

    init(
        image: NSImage?,
        title: String,
        toolTip: String,
        target: AnyObject?,
        action: Selector?,
        size: NSSize,
        cornerRadius: CGFloat
    ) {
        fixedSize = size
        super.init(frame: NSRect(origin: .zero, size: size))
        self.image = image
        self.title = ""
        self.toolTip = toolTip
        self.target = target
        self.action = action
        imagePosition = .imageOnly
        imageScaling = .scaleProportionallyDown
        alignment = .center
        isBordered = false
        setButtonType(.momentaryChange)
        setAccessibilityLabel(title)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = cornerRadius
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size.width),
            heightAnchor.constraint(equalToConstant: size.height),
        ])
        updateVisualState()
    }

    required init?(coder: NSCoder) {
        fixedSize = NSSize(width: 28, height: 28)
        super.init(coder: coder)
    }

    override var intrinsicContentSize: NSSize {
        fixedSize
    }

    override var isEnabled: Bool {
        didSet { updateVisualState() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingRegion {
            removeTrackingArea(trackingRegion)
        }
        let region = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(region)
        trackingRegion = region
    }

    override func mouseEntered(with event: NSEvent) {
        pointerIsInside = true
        updateVisualState()
    }

    override func mouseExited(with event: NSEvent) {
        pointerIsInside = false
        updateVisualState()
    }

    override func mouseDown(with event: NSEvent) {
        layer?.backgroundColor = Theme.surface3.withAlphaComponent(0.9).cgColor
        super.mouseDown(with: event)
        updateVisualState()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateVisualState()
    }

    private func updateVisualState() {
        alphaValue = isEnabled ? 1 : 0.34
        contentTintColor = isEnabled ? Theme.textPrimary : Theme.textDimmed
        layer?.backgroundColor = pointerIsInside && isEnabled
            ? Theme.surface3.withAlphaComponent(0.62).cgColor
            : NSColor.clear.cgColor
    }
}
