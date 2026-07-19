import AppKit

struct CleanupReviewConfiguration {
    let title: String
    let subtitle: String
    let attribution: String?
    let goal: String?
    let applyTitle: String
    let cancelTitle: String
    let rejectTitle: String?
    let showsRequirement: Bool
    let initialSelectedSuggestionIDs: Set<String>?
    let summaryProvider: ((Set<String>, Int, Int) -> String)?

    static let cleanup = CleanupReviewConfiguration(
        title: "Clean Up Transcript",
        subtitle: "Review the suggested edits. Nothing changes until you apply them, and the entire cleanup can be undone at once.",
        attribution: nil,
        goal: nil,
        applyTitle: "Apply Cleanup",
        cancelTitle: "Cancel",
        rejectTitle: nil,
        showsRequirement: false,
        initialSelectedSuggestionIDs: nil,
        summaryProvider: nil
    )

    static func agent(
        agentName: String,
        goal: String,
        initialSelectedSuggestionIDs: Set<String>,
        summaryProvider: @escaping (Set<String>, Int, Int) -> String
    ) -> CleanupReviewConfiguration {
        CleanupReviewConfiguration(
            title: "Review Agent Edits",
            subtitle: "Required and optional edits are suggestions until you apply them. Applying the selection creates one Undo step.",
            attribution: "Proposed by \(agentName)",
            goal: "Goal: \(goal)",
            applyTitle: "Apply Edits",
            cancelTitle: "Cancel",
            rejectTitle: "Reject Proposal",
            showsRequirement: true,
            initialSelectedSuggestionIDs: initialSelectedSuggestionIDs,
            summaryProvider: summaryProvider
        )
    }
}

/// Review surface for applying transcript cleanup as one undoable edit.
final class CleanupReviewView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onApply: ((Set<String>) -> Void)?
    var onCancel: (() -> Void)?
    var onReject: (() -> Void)?
    var onSelectionChanged: ((Set<String>) -> Void)?

    private let suggestions: [TranscriptCleanupSuggestion]
    private let configuration: CleanupReviewConfiguration
    private var selectedSuggestionIDs: Set<String>
    private var categoryButtons: [TranscriptCleanupKind: NSButton] = [:]
    private var categoryControls: [NSButton] = []

    private let tableView = NSTableView()
    private let summaryLabel = NSTextField(labelWithString: "")
    private let cancelButton = NSButton()
    private let rejectButton = NSButton()
    private let applyButton = NSButton()

    init(
        frame frameRect: NSRect,
        suggestions: [TranscriptCleanupSuggestion],
        configuration: CleanupReviewConfiguration = .cleanup
    ) {
        self.suggestions = suggestions
        self.configuration = configuration
        let selectableIDs = Set(suggestions.lazy.filter(\.isSelectable).map(\.id))
        selectedSuggestionIDs = configuration.initialSelectedSuggestionIDs
            .map { $0.intersection(selectableIDs) }
            ?? selectableIDs
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        suggestions = []
        configuration = .cleanup
        selectedSuggestionIDs = []
        super.init(coder: coder)
        setup()
    }

    var selectedSuggestionCount: Int {
        selectedSuggestionIDs.count
    }

    var selectedWordIDs: Set<String> {
        Set(
            suggestions
                .filter { selectedSuggestionIDs.contains($0.id) && $0.isSelectable }
                .flatMap(\.wordIDs)
        )
    }

    var summaryText: String {
        summaryLabel.stringValue
    }

    func setCategory(_ kind: TranscriptCleanupKind, enabled: Bool) {
        let categoryIDs = suggestions.lazy
            .filter { $0.kind == kind && $0.isSelectable }
            .map(\.id)
        if enabled {
            selectedSuggestionIDs.formUnion(categoryIDs)
        } else {
            selectedSuggestionIDs.subtract(categoryIDs)
        }
        tableView.reloadData()
        updateControls()
    }

    func setSuggestion(_ id: String, enabled: Bool) {
        guard let suggestion = suggestions.first(where: { $0.id == id }),
              suggestion.isSelectable else {
            return
        }
        if enabled {
            selectedSuggestionIDs.insert(id)
        } else {
            selectedSuggestionIDs.remove(id)
        }
        tableView.reloadData()
        updateControls()
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = Theme.surface2.cgColor
        layer?.cornerRadius = 12

        let titleLabel = NSTextField(labelWithString: configuration.title)
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.textColor = Theme.textPrimary

        let subtitleLabel = NSTextField(wrappingLabelWithString: configuration.subtitle)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = Theme.textSecondary
        subtitleLabel.maximumNumberOfLines = 2

        let headerStack = NSStackView()
        headerStack.orientation = .vertical
        headerStack.alignment = .leading
        headerStack.spacing = 4
        headerStack.addArrangedSubview(titleLabel)
        if let attribution = configuration.attribution {
            let attributionLabel = NSTextField(labelWithString: attribution)
            attributionLabel.font = .systemFont(ofSize: 12, weight: .medium)
            attributionLabel.textColor = Theme.accent
            attributionLabel.setAccessibilityLabel(attribution)
            headerStack.addArrangedSubview(attributionLabel)
        }
        if let goal = configuration.goal {
            let goalLabel = NSTextField(wrappingLabelWithString: goal)
            goalLabel.font = .systemFont(ofSize: 12)
            goalLabel.textColor = Theme.textPrimary
            goalLabel.maximumNumberOfLines = 2
            headerStack.addArrangedSubview(goalLabel)
            goalLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true
        }
        headerStack.addArrangedSubview(subtitleLabel)
        subtitleLabel.widthAnchor.constraint(equalTo: headerStack.widthAnchor).isActive = true

        let categoryStack = NSStackView()
        categoryStack.orientation = .horizontal
        categoryStack.spacing = 18
        categoryStack.alignment = .centerY

        for (index, kind) in TranscriptCleanupKind.allCases.enumerated() {
            let count = suggestions.lazy.filter { $0.kind == kind }.count
            guard count > 0 else { continue }
            let button = NSButton(
                checkboxWithTitle: "\(kind.title) (\(count))",
                target: self,
                action: #selector(categoryClicked(_:))
            )
            button.tag = index
            button.state = .on
            button.allowsMixedState = true
            button.setAccessibilityLabel(kind.title)
            button.setAccessibilityHelp("Include or exclude all \(kind.title.lowercased()) suggestions.")
            categoryButtons[kind] = button
            categoryControls.append(button)
            categoryStack.addArrangedSubview(button)
        }

        configureTable()
        let scrollView = NSScrollView()
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        scrollView.drawsBackground = false

        summaryLabel.font = .systemFont(ofSize: 12)
        summaryLabel.textColor = Theme.textSecondary
        summaryLabel.setAccessibilityLabel(
            configuration.showsRequirement ? "Agent edit summary" : "Cleanup summary"
        )

        cancelButton.title = "Cancel"
        cancelButton.title = configuration.cancelTitle
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)

        rejectButton.title = configuration.rejectTitle ?? ""
        rejectButton.bezelStyle = .rounded
        rejectButton.target = self
        rejectButton.action = #selector(rejectClicked)
        rejectButton.isHidden = configuration.rejectTitle == nil

        applyButton.title = configuration.applyTitle
        applyButton.bezelStyle = .rounded
        applyButton.keyEquivalent = "\r"
        applyButton.target = self
        applyButton.action = #selector(applyClicked)

        for view in [
            headerStack, categoryStack, scrollView,
            summaryLabel, cancelButton, rejectButton, applyButton,
        ] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }

        let actionControls: [NSView] = configuration.rejectTitle == nil
            ? [cancelButton, applyButton]
            : [cancelButton, rejectButton, applyButton]
        let keyboardControls: [NSView] = categoryControls + [tableView] + actionControls
        for (current, next) in zip(keyboardControls, keyboardControls.dropFirst()) {
            current.nextKeyView = next
        }
        keyboardControls.last?.nextKeyView = keyboardControls.first

        NSLayoutConstraint.activate([
            headerStack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            headerStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            headerStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),

            categoryStack.topAnchor.constraint(equalTo: headerStack.bottomAnchor, constant: 16),
            categoryStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            categoryStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: categoryStack.bottomAnchor, constant: 14),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: summaryLabel.topAnchor, constant: -14),

            summaryLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            summaryLabel.centerYAnchor.constraint(equalTo: cancelButton.centerYAnchor),
            summaryLabel.trailingAnchor.constraint(lessThanOrEqualTo: cancelButton.leadingAnchor, constant: -16),

            cancelButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            cancelButton.trailingAnchor.constraint(
                equalTo: configuration.rejectTitle == nil
                    ? applyButton.leadingAnchor
                    : rejectButton.leadingAnchor,
                constant: -12
            ),
            rejectButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            rejectButton.trailingAnchor.constraint(equalTo: applyButton.leadingAnchor, constant: -12),
            applyButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20),
            applyButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
        ])

        updateControls()
    }

    @discardableResult
    func focusInitialControl(in targetWindow: NSWindow? = nil) -> Bool {
        let initialControl: NSView = categoryControls.first ?? tableView
        return (targetWindow ?? window)?.makeFirstResponder(initialControl) ?? false
    }

    private func configureTable() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 34
        tableView.intercellSpacing = NSSize(width: 8, height: 2)
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = true
        tableView.allowsMultipleSelection = false
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = .clear
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.setAccessibilityLabel(
            configuration.showsRequirement ? "Agent edit suggestions" : "Cleanup suggestions"
        )

        addColumn(identifier: "include", title: "", width: 30, minimumWidth: 30)
        addColumn(identifier: "kind", title: "Type", width: 92, minimumWidth: 82)
        if configuration.showsRequirement {
            addColumn(identifier: "requirement", title: "Status", width: 82, minimumWidth: 78)
        }
        addColumn(identifier: "change", title: "Suggested change", width: 190, minimumWidth: 150)
        addColumn(identifier: "context", title: "Context", width: 180, minimumWidth: 130)
        addColumn(identifier: "time", title: "At", width: 60, minimumWidth: 56)
    }

    private func addColumn(
        identifier: String,
        title: String,
        width: CGFloat,
        minimumWidth: CGFloat
    ) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = minimumWidth
        tableView.addTableColumn(column)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        suggestions.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard suggestions.indices.contains(row), let tableColumn else { return nil }
        let suggestion = suggestions[row]

        if tableColumn.identifier.rawValue == "include" {
            let identifier = NSUserInterfaceItemIdentifier("CleanupIncludeCell")
            let button = tableView.makeView(withIdentifier: identifier, owner: self) as? NSButton
                ?? NSButton(checkboxWithTitle: "", target: self, action: #selector(rowClicked(_:)))
            button.identifier = identifier
            button.tag = row
            button.state = selectedSuggestionIDs.contains(suggestion.id) ? .on : .off
            button.isEnabled = suggestion.isSelectable
            button.setAccessibilityLabel("Include \(suggestion.changeDescription)")
            button.setAccessibilityHelp(
                suggestion.validationMessage
                    ?? "Include or exclude this proposed transcript deletion."
            )
            return button
        }

        let identifier = NSUserInterfaceItemIdentifier("CleanupTextCell-" + tableColumn.identifier.rawValue)
        let label = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            ?? NSTextField(labelWithString: "")
        label.identifier = identifier
        label.font = .systemFont(ofSize: 12)
        label.textColor = tableColumn.identifier.rawValue == "context"
            ? Theme.textSecondary
            : Theme.textPrimary
        label.lineBreakMode = .byTruncatingTail
        label.maximumNumberOfLines = 1

        switch tableColumn.identifier.rawValue {
        case "kind":
            label.stringValue = suggestion.kind.rowTitle
        case "requirement":
            label.stringValue = suggestion.validationMessage == nil
                ? suggestion.requirement.title
                : "Needs review"
        case "change":
            label.stringValue = suggestion.changeDescription
        case "context":
            label.stringValue = suggestion.validationMessage ?? suggestion.context
        case "time":
            label.stringValue = formatTime(suggestion.startTime)
            label.alignment = .right
        default:
            label.stringValue = ""
        }
        label.toolTip = label.stringValue
        return label
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        layer?.backgroundColor = Theme.surface2.cgColor
        tableView.reloadData()
    }

    @objc private func rowClicked(_ sender: NSButton) {
        guard suggestions.indices.contains(sender.tag) else { return }
        setSuggestion(suggestions[sender.tag].id, enabled: sender.state == .on)
    }

    @objc private func categoryClicked(_ sender: NSButton) {
        guard TranscriptCleanupKind.allCases.indices.contains(sender.tag) else { return }
        let kind = TranscriptCleanupKind.allCases[sender.tag]
        setCategory(kind, enabled: sender.state == .on)
    }

    @objc private func applyClicked() {
        guard !selectedWordIDs.isEmpty else { return }
        onApply?(selectedWordIDs)
    }

    @objc private func cancelClicked() {
        onCancel?()
    }

    @objc private func rejectClicked() {
        onReject?()
    }

    private func updateControls() {
        for (kind, button) in categoryButtons {
            let categorySuggestions = suggestions.filter { $0.kind == kind && $0.isSelectable }
            let selectedCount = categorySuggestions.lazy.filter {
                self.selectedSuggestionIDs.contains($0.id)
            }.count
            if selectedCount == 0 {
                button.state = .off
            } else if selectedCount == categorySuggestions.count {
                button.state = .on
            } else {
                button.state = .mixed
            }
        }

        let selectedSuggestions = suggestions.filter {
            selectedSuggestionIDs.contains($0.id) && $0.isSelectable
        }
        let removedDuration = selectedSuggestions.reduce(0) {
            $0 + $1.removedDuration
        }
        if let summaryProvider = configuration.summaryProvider {
            summaryLabel.stringValue = summaryProvider(
                selectedWordIDs,
                selectedSuggestions.count,
                suggestions.count
            )
        } else if selectedSuggestions.isEmpty {
            summaryLabel.stringValue = "No changes selected"
        } else {
            summaryLabel.stringValue = String(
                format: "%d of %d changes selected • about %.1fs removed",
                selectedSuggestions.count,
                suggestions.count,
                removedDuration
            )
        }
        applyButton.isEnabled = !selectedWordIDs.isEmpty
        onSelectionChanged?(selectedWordIDs)
    }
}
