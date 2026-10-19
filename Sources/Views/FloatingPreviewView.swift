import AppKit

/// The edited preview as a floating panel over the transcript: a grab strip,
/// the video at 16:9, and the transport. Drag the strip to move it; the size
/// button switches between a large and a small panel. Position and size are
/// remembered between projects.
final class FloatingPreviewView: NSView {
    static let largeWidth: CGFloat = 400
    static let smallWidth: CGFloat = 260
    static let edgeMargin: CGFloat = 20
    private static let compactKey = "editor.previewCompact"
    private static let offsetXKey = "editor.previewOffsetX"
    private static let offsetYKey = "editor.previewOffsetY"

    let videoView = VideoPreviewView()
    let transportView = TransportControlsView()
    private let grabStrip = PreviewGrabStrip()
    private let sizeButton = NSButton()
    private let preferences: UserDefaults
    private var widthConstraint: NSLayoutConstraint!

    /// Distance from the container's trailing and bottom edges.
    private(set) var offset: CGPoint
    private(set) var isCompact: Bool
    var onMove: (() -> Void)?

    var panelWidth: CGFloat { isCompact ? Self.smallWidth : Self.largeWidth }

    init(preferences: UserDefaults) {
        self.preferences = preferences
        isCompact = preferences.bool(forKey: Self.compactKey)
        offset = CGPoint(
            x: preferences.object(forKey: Self.offsetXKey) as? Double ?? Double(Self.edgeMargin),
            y: preferences.object(forKey: Self.offsetYKey) as? Double ?? Double(Self.edgeMargin)
        )
        super.init(frame: .zero)
        setup()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface2.cgColor
        layer?.cornerRadius = 12
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.borderColor = Theme.surface3.cgColor
        layer?.masksToBounds = true
        shadow = NSShadow()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Preview")

        grabStrip.onDrag = { [weak self] delta in self?.move(by: delta) }
        grabStrip.onDragEnd = { [weak self] in self?.saveOffset() }

        sizeButton.isBordered = false
        sizeButton.target = self
        sizeButton.action = #selector(toggleSize)
        sizeButton.contentTintColor = Theme.textSecondary
        updateSizeButton()

        for view in [grabStrip, sizeButton, videoView, transportView] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        widthConstraint = widthAnchor.constraint(equalToConstant: panelWidth)
        NSLayoutConstraint.activate([
            widthConstraint,
            grabStrip.topAnchor.constraint(equalTo: topAnchor),
            grabStrip.leadingAnchor.constraint(equalTo: leadingAnchor),
            grabStrip.trailingAnchor.constraint(equalTo: trailingAnchor),
            grabStrip.heightAnchor.constraint(equalToConstant: 22),
            sizeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            sizeButton.centerYAnchor.constraint(equalTo: grabStrip.centerYAnchor),
            sizeButton.widthAnchor.constraint(equalToConstant: 22),
            sizeButton.heightAnchor.constraint(equalToConstant: 18),
            videoView.topAnchor.constraint(equalTo: grabStrip.bottomAnchor),
            videoView.leadingAnchor.constraint(equalTo: leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: trailingAnchor),
            videoView.heightAnchor.constraint(equalTo: videoView.widthAnchor, multiplier: 9.0 / 16.0),
            transportView.topAnchor.constraint(equalTo: videoView.bottomAnchor),
            transportView.leadingAnchor.constraint(equalTo: leadingAnchor),
            transportView.trailingAnchor.constraint(equalTo: trailingAnchor),
            transportView.heightAnchor.constraint(equalToConstant: 84),
            transportView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface2.cgColor
        layer?.borderColor = Theme.surface3.cgColor
    }

    /// Keep the panel fully inside the container after a resize or drag.
    func clampOffset(in container: NSRect) {
        let size = fittingSize
        let maxX = max(Self.edgeMargin, container.width - size.width - Self.edgeMargin)
        let maxY = max(Self.edgeMargin, container.height - size.height - Self.edgeMargin)
        offset = CGPoint(x: min(max(Self.edgeMargin, offset.x), maxX), y: min(max(Self.edgeMargin, offset.y), maxY))
    }

    private func move(by delta: CGSize) {
        // The offset is measured from the trailing and bottom edges, so moving right
        // or down shrinks it.
        offset = CGPoint(x: offset.x - delta.width, y: offset.y - delta.height)
        if let container = superview?.bounds { clampOffset(in: container) }
        onMove?()
    }

    private func saveOffset() {
        preferences.set(Double(offset.x), forKey: Self.offsetXKey)
        preferences.set(Double(offset.y), forKey: Self.offsetYKey)
    }

    @objc private func toggleSize() {
        isCompact.toggle()
        preferences.set(isCompact, forKey: Self.compactKey)
        widthConstraint.constant = panelWidth
        updateSizeButton()
        if let container = superview?.bounds { clampOffset(in: container) }
        onMove?()
    }

    private func updateSizeButton() {
        let name = isCompact ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left"
        let label = isCompact ? "Larger preview" : "Smaller preview"
        sizeButton.image = NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        sizeButton.toolTip = label
        sizeButton.setAccessibilityLabel(label)
    }
}

/// The preview's top strip: shows a move cursor and reports drags.
final class PreviewGrabStrip: NSView {
    var onDrag: ((CGSize) -> Void)?
    var onDragEnd: (() -> Void)?
    private var last: NSPoint?
    private let title = NSTextField(labelWithString: "Preview")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        title.font = .systemFont(ofSize: 11, weight: .medium)
        title.textColor = Theme.textTertiary
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = "Drag to move the preview"
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        last = event.locationInWindow
        NSCursor.closedHand.push()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let last else { return }
        let point = event.locationInWindow
        // Window coordinates grow upward; report a downward-positive vertical delta.
        onDrag?(CGSize(width: point.x - last.x, height: last.y - point.y))
        self.last = point
    }

    override func mouseUp(with event: NSEvent) {
        last = nil
        NSCursor.pop()
        onDragEnd?()
    }
}
