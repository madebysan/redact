import AppKit
import UniformTypeIdentifiers

class EmptyStateView: NSView {
    var onFileDropped: ((URL) -> Void)?
    var onImportClicked: (() -> Void)?

    private var isDragHighlighted = false {
        didSet { needsDisplay = true }
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "Drop a video or audio file here")
    private let subtitleLabel = NSTextField(labelWithString: "MP4, MKV, WebM, MOV, AVI, MP3, WAV, M4A")
    private let importButton = NSButton()
    private let orLabel = NSTextField(labelWithString: "or")
    private let dashedBorder = CAShapeLayer()

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
        registerForDraggedTypes([.fileURL])

        // Icon
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 48, weight: .thin)
        iconView.image = NSImage(systemSymbolName: "film", accessibilityDescription: "Media file")?
            .withSymbolConfiguration(symbolConfig)
        iconView.contentTintColor = Theme.textDimmed
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        // Title
        titleLabel.font = .systemFont(ofSize: 18, weight: .medium)
        titleLabel.textColor = Theme.textSecondary
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        // Subtitle
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = Theme.silenceText
        subtitleLabel.alignment = .center
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(subtitleLabel)

        // "or" label
        orLabel.font = .systemFont(ofSize: 13)
        orLabel.textColor = Theme.textDimmed
        orLabel.alignment = .center
        orLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(orLabel)

        // Import button
        importButton.title = "Import Media"
        importButton.bezelStyle = .rounded
        importButton.controlSize = .large
        importButton.target = self
        importButton.action = #selector(importClicked)
        importButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(importButton)

        // Dashed border layer
        dashedBorder.fillColor = nil
        dashedBorder.strokeColor = NSColor(white: 0.2, alpha: 1).cgColor
        dashedBorder.lineWidth = 1.5
        dashedBorder.lineDashPattern = [8, 6]
        layer?.addSublayer(dashedBorder)

        NSLayoutConstraint.activate([
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -60),
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64),

            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),

            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),

            orLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            orLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 16),

            importButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            importButton.topAnchor.constraint(equalTo: orLabel.bottomAnchor, constant: 12),
        ])
    }

    override func layout() {
        super.layout()
        updateDashedBorder()
    }

    private func updateDashedBorder() {
        let inset: CGFloat = 40
        let rect = bounds.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
        dashedBorder.path = path.cgPath
        dashedBorder.strokeColor = isDragHighlighted
            ? Theme.accent.withAlphaComponent(0.6).cgColor
            : NSColor(white: 0.2, alpha: 1).cgColor
    }

    @objc private func importClicked() {
        onImportClicked?()
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if validateDrag(sender) {
            isDragHighlighted = true
            return .copy
        }
        return []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        validateDrag(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragHighlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isDragHighlighted = false

        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = items.first else {
            return false
        }

        let ext = url.pathExtension.lowercased()
        if MainWindowController.allSupportedExtensions.contains(ext) {
            onFileDropped?(url)
            return true
        }
        return false
    }

    private func validateDrag(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = items.first else {
            return false
        }
        let ext = url.pathExtension.lowercased()
        return MainWindowController.allSupportedExtensions.contains(ext)
    }
}

// MARK: - NSBezierPath CGPath Extension

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            case .cubicCurveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            @unknown default: break
            }
        }
        return path
    }
}
