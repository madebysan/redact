import AppKit

/// Custom NSTextView attribute key for storing word IDs on text ranges.
extension NSAttributedString.Key {
    static let wordID = NSAttributedString.Key("com.redact.wordID")
}

/// Read-only transcript display with styled text, paragraph breaks at gaps,
/// dimmed silence tokens, and native mouse-driven word selection.
class TranscriptView: NSView {
    private let scrollView = NSScrollView()
    private let textView: InteractiveTextView

    /// Set by MainWindowController once the project is in editing state.
    weak var project: ProjectDocument?
    var onWordClicked: ((Word) -> Void)?

    /// Maps word IDs to their NSRange in the text storage.
    private(set) var wordRanges: [String: NSRange] = [:]

    /// All words in display order (for hit-testing and interaction).
    private(set) var displayedWords: [Word] = []

    /// The word currently highlighted for playback (O(1) clear on next highlight).
    private var currentlyHighlightedId: String?

    /// The snapshot of selected/deleted state used during the last appearance pass —
    /// lets refreshAllWordAppearances touch only words whose state changed.
    private var lastAppearance: [String: (deleted: Bool, selected: Bool)] = [:]

    // MARK: - Selection state

    private var isDragging = false
    private var dragStartId: String?
    private var lastClickId: String?

    override init(frame frameRect: NSRect) {
        self.textView = InteractiveTextView()
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        self.textView = InteractiveTextView()
        super.init(coder: coder)
        setup()
    }

    /// Keeps track of the current segments for re-rendering on settings change.
    private var currentSegments: [Segment]?

    private func setup() {
        wantsLayer = true

        NotificationCenter.default.addObserver(
            self, selector: #selector(settingsDidChange),
            name: .settingsChanged, object: nil
        )

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        textView.transcriptView = self
        textView.isEditable = false
        textView.isSelectable = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    /// Build the transcript as a stack of subtitle-style lines.
    /// Each line is one paragraph with its own leading indent (room for a future
    /// drag handle) and a small timestamp prefix for orientation.
    func setTranscript(segments: [Segment]) {
        currentSegments = segments
        wordRanges = [:]
        displayedWords = []
        currentlyHighlightedId = nil
        lastAppearance = [:]

        let lines = computeLines(segments: segments)
        let textStorage = NSMutableAttributedString()
        let settings = Settings.shared
        let fontSize = settings.transcriptFontSize

        let lineStyle = NSMutableParagraphStyle()
        lineStyle.paragraphSpacing = 10               // gap after each line
        lineStyle.paragraphSpacingBefore = 0
        lineStyle.firstLineHeadIndent = 56            // room for timestamp + future drag handle
        lineStyle.headIndent = 56                     // wrapped lines align under body
        lineStyle.lineSpacing = 2

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: settings.transcriptFont(ofSize: fontSize, weight: .regular),
            .foregroundColor: Theme.wordNormal,
            .paragraphStyle: lineStyle,
        ]

        let silenceAttrs: [NSAttributedString.Key: Any] = [
            .font: settings.transcriptFont(ofSize: fontSize - 2, weight: .light),
            .foregroundColor: Theme.silenceText,
            .paragraphStyle: lineStyle,
        ]

        let timestampAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: fontSize - 3, weight: .regular),
            .foregroundColor: Theme.textDimmed,
            .paragraphStyle: lineStyle,
        ]

        for (lineIndex, line) in lines.enumerated() {
            if lineIndex > 0 {
                textStorage.append(NSAttributedString(string: "\n", attributes: normalAttrs))
            }

            // Timestamp prefix — clickable space but no .wordID, so clicks fall through.
            let timestamp = formatTime(line.startTime)
            textStorage.append(NSAttributedString(string: "\(timestamp)   ", attributes: timestampAttrs))

            for (wordIndex, word) in line.words.enumerated() {
                displayedWords.append(word)

                if wordIndex > 0 {
                    textStorage.append(NSAttributedString(string: " ", attributes: normalAttrs))
                }

                var wordAttrs = word.isActualSilence ? silenceAttrs : normalAttrs
                wordAttrs[.wordID] = word.id

                let range = NSRange(location: textStorage.length, length: word.word.count)
                textStorage.append(NSAttributedString(string: word.word, attributes: wordAttrs))
                wordRanges[word.id] = range
            }
        }

        textView.textStorage?.setAttributedString(textStorage)
    }

    /// Highlight the currently-playing word. O(1) — clears only the previous range.
    func highlightWord(id: String?) {
        guard let storage = textView.textStorage else { return }

        if let prevId = currentlyHighlightedId, let prevRange = wordRanges[prevId] {
            storage.removeAttribute(.backgroundColor, range: prevRange)
            // Re-apply selection background if still selected.
            if let project, project.selectedWordIds.contains(prevId) {
                storage.addAttribute(.backgroundColor, value: Theme.wordSelectedBackground, range: prevRange)
            }
        }

        currentlyHighlightedId = id

        if let id, let range = wordRanges[id] {
            let color = Settings.shared.highlightColor.withAlphaComponent(0.2)
            storage.addAttribute(.backgroundColor, value: color, range: range)
            textView.scrollRangeToVisible(range)
        }
    }

    /// Apply visual state for a single word.
    func updateWordAppearance(wordId: String, deleted: Bool, selected: Bool) {
        guard let storage = textView.textStorage, let range = wordRanges[wordId] else { return }
        lastAppearance[wordId] = (deleted, selected)

        if deleted {
            storage.addAttributes([
                .foregroundColor: Theme.wordDeleted,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: Theme.wordDeletedStrikethrough.withAlphaComponent(0.6),
            ], range: range)
        } else if selected {
            storage.addAttributes([
                .foregroundColor: Theme.wordNormal,
                .backgroundColor: Theme.wordSelectedBackground,
            ], range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.strikethroughColor, range: range)
        } else {
            storage.addAttributes([
                .foregroundColor: Theme.wordNormal,
            ], range: range)
            storage.removeAttribute(.backgroundColor, range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.strikethroughColor, range: range)
        }
    }

    /// Diff the full word list against the last appearance snapshot and
    /// update only the words whose visual state actually changed.
    func refreshAllWordAppearances() {
        guard let project else { return }
        let selected = project.selectedWordIds

        for word in project.allWords {
            let isSelected = selected.contains(word.id)
            let prev = lastAppearance[word.id]
            if prev?.deleted != word.deleted || prev?.selected != isSelected {
                updateWordAppearance(wordId: word.id, deleted: word.deleted, selected: isSelected)
            }
        }
    }

    @objc private func settingsDidChange() {
        guard let segments = currentSegments else { return }
        setTranscript(segments: segments)
        refreshAllWordAppearances()
    }

    /// Get the word ID at a given point in this view's coordinates.
    func wordId(at point: NSPoint) -> String? {
        let textPoint = textView.convert(point, from: self)
        return wordId(atTextViewPoint: textPoint)
    }

    fileprivate func wordId(atTextViewPoint point: NSPoint) -> String? {
        let index = textView.characterIndexForInsertion(at: point)
        guard index >= 0, index < (textView.textStorage?.length ?? 0) else { return nil }
        return textView.textStorage?.attribute(.wordID, at: index, effectiveRange: nil) as? String
    }

    // MARK: - Selection handling (was WordSelectionController)

    fileprivate func handleMouseDown(wordId: String, event: NSEvent) {
        guard let project else { return }
        guard let word = project.allWords.first(where: { $0.id == wordId }) else { return }

        // Deleted words: click to restore.
        if word.deleted {
            project.restoreWord(wordId)
            refreshAllWordAppearances()
            return
        }

        isDragging = true
        dragStartId = wordId

        let isShift = event.modifierFlags.contains(.shift)
        let isCmd = event.modifierFlags.contains(.command)

        if isShift, let lastId = lastClickId {
            project.selectWords(wordRange(from: lastId, to: wordId))
        } else if isCmd {
            if project.selectedWordIds.contains(wordId) {
                var current = project.selectedWordIds
                current.remove(wordId)
                project.selectWords(Array(current))
            } else {
                project.addToSelection([wordId])
            }
        } else {
            project.selectWords([wordId])
        }

        lastClickId = wordId
        refreshAllWordAppearances()
        onWordClicked?(word)
    }

    fileprivate func handleMouseDragged(to wordId: String?) {
        guard isDragging, let dragStartId, let project, let wordId else { return }
        project.selectWords(wordRange(from: dragStartId, to: wordId))
        refreshAllWordAppearances()
    }

    fileprivate func handleMouseUp() {
        isDragging = false
    }

    private func wordRange(from fromId: String, to toId: String) -> [String] {
        guard let project else { return [] }
        let words = project.allWords
        guard let fromIdx = words.firstIndex(where: { $0.id == fromId }),
              let toIdx = words.firstIndex(where: { $0.id == toId }) else {
            return []
        }
        let start = min(fromIdx, toIdx)
        let end = max(fromIdx, toIdx)
        return words[start...end].map(\.id)
    }
}

// MARK: - NSTextView subclass that forwards mouse events to its TranscriptView

private final class InteractiveTextView: NSTextView {
    weak var transcriptView: TranscriptView?

    override func mouseDown(with event: NSEvent) {
        guard let transcriptView else {
            super.mouseDown(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if let wordId = transcriptView.wordId(atTextViewPoint: point) {
            transcriptView.handleMouseDown(wordId: wordId, event: event)
            return
        }
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let transcriptView else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        transcriptView.handleMouseDragged(to: transcriptView.wordId(atTextViewPoint: point))
    }

    override func mouseUp(with event: NSEvent) {
        transcriptView?.handleMouseUp()
        super.mouseUp(with: event)
    }
}
