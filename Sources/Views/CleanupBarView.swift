import AppKit

/// One-click cleanup above the transcript: Remove fillers, Remove repeats, and
/// Tighten pauses. Pointing at a toggle previews what it removes; clicking it
/// cuts every suggestion of that kind as one undoable edit, and clicking an
/// applied toggle restores them. The review sheet stays available for
/// suggestion-by-suggestion review.
final class CleanupBarView: NSView {
    struct Category: Equatable {
        let kind: TranscriptCleanupKind
        let title: String
        let wordIDs: Set<String>
        let count: Int
    }

    var onPreview: ((Set<String>) -> Void)?
    var onToggle: ((Set<String>, Bool) -> Void)?
    var onReview: (() -> Void)?

    private let stack = NSStackView()
    private let reviewButton = NSButton(title: "Review All…", target: nil, action: nil)
    private var chips: [CleanupChipButton] = []
    private(set) var categories: [Category] = []
    private let topDivider = NSView()

    static let height: CGFloat = 44

    static func categories(from suggestions: [TranscriptCleanupSuggestion]) -> [Category] {
        let titles: [(TranscriptCleanupKind, String)] = [
            (.fillerWords, "Remove fillers"),
            (.repeatedWords, "Remove repeats"),
            (.longPauses, "Tighten pauses"),
        ]
        return titles.compactMap { kind, title in
            let matches = suggestions.filter { $0.kind == kind && $0.isSelectable }
            guard !matches.isEmpty else { return nil }
            return Category(kind: kind, title: title, wordIDs: Set(matches.flatMap(\.wordIDs)), count: matches.count)
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.surface1.cgColor

        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        reviewButton.bezelStyle = .inline
        reviewButton.isBordered = false
        reviewButton.contentTintColor = Theme.textSecondary
        reviewButton.font = .systemFont(ofSize: 12)
        reviewButton.target = self
        reviewButton.action = #selector(reviewClicked)
        reviewButton.toolTip = "Review cleanup suggestions one by one"
        reviewButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(reviewButton)

        topDivider.wantsLayer = true
        topDivider.layer?.backgroundColor = Theme.divider.cgColor
        topDivider.translatesAutoresizingMaskIntoConstraints = false
        addSubview(topDivider)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: reviewButton.leadingAnchor, constant: -12),
            reviewButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            reviewButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            topDivider.leadingAnchor.constraint(equalTo: leadingAnchor),
            topDivider.trailingAnchor.constraint(equalTo: trailingAnchor),
            topDivider.bottomAnchor.constraint(equalTo: bottomAnchor),
            topDivider.heightAnchor.constraint(equalToConstant: 1),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Cleanup")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface1.cgColor
        topDivider.layer?.backgroundColor = Theme.divider.cgColor
    }

    func setCategories(_ categories: [Category]) {
        self.categories = categories
        chips.forEach { $0.removeFromSuperview() }
        chips = categories.enumerated().map { index, category in
            let chip = CleanupChipButton(title: category.title, count: category.count)
            chip.tag = index
            chip.target = self
            chip.action = #selector(chipClicked(_:))
            chip.onHover = { [weak self] inside in
                guard let self else { return }
                let applied = self.chips[index].isApplied
                self.onPreview?(inside && !applied ? category.wordIDs : [])
            }
            stack.addArrangedSubview(chip)
            return chip
        }
        isHidden = categories.isEmpty
    }

    /// Mark each toggle applied when every word of its kind is cut.
    func update(isDeleted: (String) -> Bool) {
        for (chip, category) in zip(chips, categories) {
            chip.isApplied = category.wordIDs.allSatisfy(isDeleted)
        }
    }

    @objc private func chipClicked(_ sender: CleanupChipButton) {
        guard categories.indices.contains(sender.tag) else { return }
        onPreview?([])
        onToggle?(categories[sender.tag].wordIDs, !sender.isApplied)
    }

    @objc private func reviewClicked() {
        onReview?()
    }
}

/// A rounded toggle chip: title, a count, and an applied state.
final class CleanupChipButton: NSButton {
    var onHover: ((Bool) -> Void)?
    var isApplied = false { didSet { refresh() } }
    private let label: String
    private let count: Int
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { refresh() } }

    init(title: String, count: Int) {
        label = title
        self.count = count
        super.init(frame: .zero)
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 26).isActive = true
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize {
        let size = attributedTitle.size()
        return NSSize(width: ceil(size.width) + 24, height: 26)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; onHover?(true) }
    override func mouseExited(with event: NSEvent) { hovering = false; onHover?(false) }

    private func refresh() {
        let title = NSMutableAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: isApplied ? NSColor(red: 0.81, green: 0.88, blue: 1, alpha: 1) : Theme.textPrimary,
        ])
        title.append(NSAttributedString(string: "  \(count)", attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: Theme.textSecondary,
        ]))
        attributedTitle = title
        layer?.backgroundColor = (isApplied
            ? Theme.accent.withAlphaComponent(0.18)
            : (hovering ? Theme.surface3.blended(withFraction: 0.15, of: .white) ?? Theme.surface3 : Theme.surface3)).cgColor
        layer?.borderWidth = isApplied ? 1 : 0
        layer?.borderColor = Theme.accent.withAlphaComponent(0.5).cgColor
        let action = isApplied ? "Restore" : "Cut"
        toolTip = "\(action) \(count) \(label.lowercased().replacingOccurrences(of: "remove ", with: "").replacingOccurrences(of: "tighten ", with: "")) as one edit"
        setAccessibilityLabel("\(label), \(count)")
        setAccessibilityValue(isApplied ? "Applied" : "Not applied")
        invalidateIntrinsicContentSize()
    }
}
