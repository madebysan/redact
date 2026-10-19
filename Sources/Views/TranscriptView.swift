import AppKit

/// Custom NSTextView attribute key for storing word IDs on text ranges.
extension NSAttributedString.Key {
    static let wordID = NSAttributedString.Key("com.redact.wordID")
}

/// Read-only transcript laid out as a document: flowing paragraphs in a centered
/// reading column, each paragraph's start time in the margin, pauses as inline
/// length chips, all in one TextKit 2 text view so selection, Find, and VoiceOver
/// work across the whole transcript.
class TranscriptView: NSView, NSTextViewDelegate, NSGestureRecognizerDelegate {
    private let scrollView = NSScrollView()
    private let textView: TranscriptRowTextView

    /// Cut (true) or keep (false) a set of words as one undoable edit.
    var onSetWordsDeleted: ((Set<String>, Bool) -> Void)?
    /// Play one sentence's source range.
    var onPlayRange: ((Double, Double) -> Void)?

    /// Widest the reading column grows; wider windows add margin instead.
    static let readingColumnWidth: CGFloat = 720
    /// Room on the leading side for each paragraph's start time.
    static let timestampMargin: CGFloat = 72

    /// Width kept clear on the trailing side, such as for the floating preview.
    var trailingReserve: CGFloat = 0 {
        didSet { if oldValue != trailingReserve { needsLayout = true } }
    }

    /// Sentence-sized units (at most 10 words) that X and Return act on.
    private(set) var rows: [TranscriptLine] = []
    private var rowStarts: [Int] = []
    /// Character offset and source start time of each paragraph.
    private(set) var paragraphStarts: [Int] = []
    private var paragraphTimes: [Double] = []
    private var pauseRunFirstID: [String: String] = [:]
    private var pauseRuns: [String: [String]] = [:]
    /// The sentence holding the selection or the last click.
    private(set) var activeRow = 0

    /// Set by MainWindowController once the project is in editing state.
    weak var project: ProjectDocument?
    var onWordClicked: ((Word) -> Void)?
    var onRestoreWord: ((String) -> Void)?
    var onCorrectWord: ((String) -> Void)?

    /// All words in display order (for hit-testing and interaction).
    private(set) var displayedWords: [Word] = []

    /// Indexed character spans used to keep native text selection aligned to words.
    private var selectionIndex = TranscriptSelectionIndex(spans: [])

    /// The word currently highlighted for playback (O(1) clear on next highlight).
    private var currentlyHighlightedId: String?

    /// The last rendered state for each word, used to skip redundant attribute writes.
    private var lastAppearance: [String: (deleted: Bool, selected: Bool, proposed: Bool)] = [:]

    /// Proposal highlights are transient and never mutate ProjectDocument.
    private(set) var proposedWordIDs: Set<String> = []

    private var isSynchronizingSelection = false

    /// TextKit 2 lays out only the visible viewport instead of eagerly laying out
    /// the entire transcript.
    var usesViewportTextLayout: Bool {
        textView.textLayoutManager != nil
    }

    var displayedText: String {
        textView.string
    }

    var hasKeyboardFocus: Bool {
        window?.firstResponder === textView
    }

    @discardableResult
    func focusForKeyboardNavigation() -> Bool {
        window?.makeFirstResponder(textView) ?? false
    }

    func displayedWordText(id: String) -> String? {
        guard let storage = textView.textStorage,
              let range = selectionIndex.range(forWordID: id),
              range.location < storage.length,
              storage.attribute(.wordID, at: range.location, effectiveRange: nil) as? String == id else {
            return nil
        }
        return (storage.string as NSString).substring(with: range)
    }

    var displayedSelectedWordIDs: [String] {
        selectionIndex.wordIDs(intersecting: textView.selectedRanges.map(\.rangeValue))
    }

    /// Width the transcript text is laid out in; zero means nothing is visible.
    var displayedTextWidth: CGFloat {
        textView.frame.width
    }

    /// Whether the text view widens with its scroll view instead of staying at its initial width.
    var displayedTextTracksScrollWidth: Bool {
        textView.autoresizingMask.contains(.width)
    }

    override func layout() {
        super.layout()
        let width = scrollView.contentSize.width
        if width > 0, textView.frame.width != width {
            textView.setFrameSize(NSSize(width: width, height: textView.frame.height))
        }
        // Center the reading column in the space left of anything floating on the
        // trailing side, keeping room for the paragraph times on the leading side.
        let minimumLeading = Self.timestampMargin + 16
        let available = max(0, width - trailingReserve)
        let leading = max(minimumLeading, (available - Self.readingColumnWidth) / 2)
        let trailingClearance = trailingReserve > 0 ? trailingReserve + 16 : minimumLeading
        let columnWidth = max(240, min(Self.readingColumnWidth, width - leading - trailingClearance))
        if abs(textView.textContainerInset.width - leading) > 0.5 {
            textView.textContainerInset = NSSize(width: leading, height: 32)
        }
        if let container = textView.textContainer, abs(container.size.width - columnWidth) > 0.5 {
            container.widthTracksTextView = false
            container.size = NSSize(width: columnWidth, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    /// The background color drawn behind a word, if any.
    func displayedBackgroundColor(forWordID id: String) -> NSColor? {
        guard let storage = textView.textStorage,
              let range = selectionIndex.range(forWordID: id),
              range.location < storage.length else {
            return nil
        }
        return storage.attribute(.backgroundColor, at: range.location, effectiveRange: nil) as? NSColor
    }

    override init(frame frameRect: NSRect) {
        self.textView = TranscriptRowTextView(usingTextLayoutManager: true)
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        self.textView = TranscriptRowTextView(usingTextLayoutManager: true)
        super.init(coder: coder)
        setup()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
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

        textView.delegate = self
        let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleTextClick(_:)))
        clickRecognizer.buttonMask = 0x1
        let correctionRecognizer = NSClickGestureRecognizer(
            target: self,
            action: #selector(handleTextDoubleClick(_:))
        )
        correctionRecognizer.buttonMask = 0x1
        correctionRecognizer.numberOfClicksRequired = 2
        clickRecognizer.delegate = self
        correctionRecognizer.delegate = self
        textView.addGestureRecognizer(clickRecognizer)
        textView.addGestureRecognizer(correctionRecognizer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.usesFindPanel = true
        textView.isIncrementalSearchingEnabled = true
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 24, height: 24)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.setAccessibilityLabel("Transcript")
        textView.setAccessibilityHelp(
            "Select words to edit, copy, or search. X cuts or keeps the sentence you are in, and Return plays it. Click a pause to tighten it. Double-click a spoken word to correct its text. Deleted words are struck through and can be clicked to restore."
        )
        textView.rowOwner = self

        scrollView.documentView = textView
        // A programmatic NSTextView starts with a zero-width frame. Without an
        // explicit width policy the clip view never widens it, TextKit lays the
        // words out into zero width, and the transcript draws nothing.
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )

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
        displayedWords = []
        var selectionSpans: [TranscriptSelectionSpan] = []
        currentlyHighlightedId = nil
        lastAppearance = [:]
        pauseRunFirstID = [:]
        pauseRuns = [:]
        rowStarts = []
        paragraphStarts = []
        paragraphTimes = []

        rows = computeLines(segments: segments)
        let textStorage = NSMutableAttributedString()
        let settings = Settings.shared
        let fontSize = settings.transcriptFontSize

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = max(14, fontSize)
        paragraphStyle.lineSpacing = settings.transcriptLineSpacing + 3

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: settings.transcriptFont(ofSize: fontSize, weight: .regular),
            .kern: settings.transcriptLetterSpacing,
            .foregroundColor: Theme.wordNormal,
            .paragraphStyle: paragraphStyle,
        ]

        var sentencesInParagraph = 0
        for (rowIndex, row) in rows.enumerated() {
            if rowIndex == 0 {
                paragraphStarts.append(0)
                paragraphTimes.append(row.startTime)
            } else {
                let previous = rows[rowIndex - 1]
                let endedSentence = previous.words.last(where: { !$0.isActualSilence }).map { endsSentence($0.word) } ?? false
                let endedOnPause = previous.words.last?.isActualSilence == true
                if endedSentence { sentencesInParagraph += 1 }
                // A paragraph closes after three sentences, or at a pause once two have passed.
                if endedSentence && (sentencesInParagraph >= 3 || (endedOnPause && sentencesInParagraph >= 2)) {
                    textStorage.append(NSAttributedString(string: "\n", attributes: normalAttrs))
                    paragraphStarts.append(textStorage.length)
                    paragraphTimes.append(row.startTime)
                    sentencesInParagraph = 0
                } else {
                    textStorage.append(NSAttributedString(string: " ", attributes: normalAttrs))
                }
            }
            rowStarts.append(textStorage.length)

            var position = 0
            var isFirstToken = true
            while position < row.words.count {
                let word = row.words[position]
                if !isFirstToken {
                    textStorage.append(NSAttributedString(string: " ", attributes: normalAttrs))
                }
                isFirstToken = false

                if word.isActualSilence {
                    // A run of silence tokens renders as one length chip owned by its first token.
                    var run: [Word] = []
                    while position < row.words.count, row.words[position].isActualSilence {
                        run.append(row.words[position])
                        position += 1
                    }
                    let runIDs = run.map(\.id)
                    pauseRuns[word.id] = runIDs
                    runIDs.forEach { pauseRunFirstID[$0] = word.id }
                    let length = (run.last?.end ?? word.end) - word.start
                    let label = "\u{2009}" + String(format: "%.1fs", length) + "\u{2009}"
                    var chipAttrs = Self.pauseChipAttributes(fontSize: fontSize, style: paragraphStyle)
                    chipAttrs[.wordID] = word.id
                    let range = NSRange(location: textStorage.length, length: (label as NSString).length)
                    textStorage.append(NSAttributedString(string: label, attributes: chipAttrs))
                    selectionSpans.append(TranscriptSelectionSpan(wordID: word.id, range: range))
                    displayedWords.append(word)
                    continue
                }

                var wordAttrs = normalAttrs
                wordAttrs[.wordID] = word.id
                let shown = Self.displayText(word.word)
                let range = NSRange(location: textStorage.length, length: (shown as NSString).length)
                textStorage.append(NSAttributedString(string: shown, attributes: wordAttrs))
                selectionSpans.append(TranscriptSelectionSpan(wordID: word.id, range: range))
                displayedWords.append(word)
                position += 1
            }
        }

        activeRow = min(activeRow, max(0, rows.count - 1))
        selectionIndex = TranscriptSelectionIndex(spans: selectionSpans)
        isSynchronizingSelection = true
        textView.textStorage?.setAttributedString(textStorage)
        let preservedRanges = selectionIndex.characterRanges(
            forWordIDs: project?.selectedWordIds ?? []
        )
        textView.selectedRanges = preservedRanges.isEmpty
            ? [NSValue(range: NSRange(location: 0, length: 0))]
            : preservedRanges.map(NSValue.init(range:))
        isSynchronizingSelection = false
        textView.needsDisplay = true
        needsLayout = true
    }

    /// Word text as shown: transcription can carry a leading space, and the view adds its own.
    static func displayText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? text : trimmed
    }

    private static func pauseChipAttributes(fontSize: CGFloat, style: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [
            .font: NSFont.monospacedDigitSystemFont(ofSize: max(9, fontSize - 4), weight: .semibold),
            .foregroundColor: Theme.textSecondary,
            .backgroundColor: Theme.surface3,
            .baselineOffset: 1,
            .paragraphStyle: style,
            .toolTip: "Pause. Click to tighten it, or click again to restore it.",
        ]
    }

    // MARK: - Sentences and paragraphs

    /// Index of the last start at or before an offset (binary search).
    private static func index(in starts: [Int], atOrBefore offset: Int) -> Int {
        var low = 0, high = starts.count - 1, found = 0
        while low <= high {
            let mid = (low + high) / 2
            if starts[mid] <= offset { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }

    fileprivate func rowIndex(forCharacterOffset offset: Int) -> Int {
        Self.index(in: rowStarts, atOrBefore: offset)
    }

    enum RowState { case keep, cut, partial }

    func rowState(_ index: Int) -> RowState {
        guard rows.indices.contains(index), let project else { return .keep }
        let cut = rows[index].words.filter { project.word(withID: $0.id)?.deleted == true }.count
        if cut == 0 { return .keep }
        return cut == rows[index].words.count ? .cut : .partial
    }

    /// Cut a sentence, or keep it again if it is already fully cut.
    func toggleRow(_ index: Int) {
        guard rows.indices.contains(index) else { return }
        onSetWordsDeleted?(Set(rows[index].words.map(\.id)), rowState(index) != .cut)
    }

    fileprivate func toggleActiveRow() {
        toggleRow(activeRow)
    }

    fileprivate func playActiveRow() {
        guard rows.indices.contains(activeRow) else { return }
        onPlayRange?(rows[activeRow].startTime, rows[activeRow].endTime)
    }

    /// Draw each visible paragraph's start time in the leading margin.
    fileprivate func drawParagraphTimes(in dirtyRect: NSRect) {
        guard let layoutManager = textView.textLayoutManager,
              let contentManager = layoutManager.textContentManager,
              !paragraphStarts.isEmpty else { return }
        let origin = textView.textContainerOrigin
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: Theme.textDimmed,
        ]
        let top = max(0, dirtyRect.minY - origin.y - 40)
        let start = layoutManager.textLayoutFragment(for: CGPoint(x: 0, y: top))?.rangeInElement.location
            ?? layoutManager.documentRange.location
        layoutManager.enumerateTextLayoutFragments(from: start, options: [.ensuresLayout]) { fragment in
            let frame = fragment.layoutFragmentFrame.offsetBy(dx: origin.x, dy: origin.y)
            if frame.minY > dirtyRect.maxY { return false }
            let offset = contentManager.offset(from: layoutManager.documentRange.location, to: fragment.rangeInElement.location)
            let paragraph = Self.index(in: self.paragraphStarts, atOrBefore: offset)
            guard self.paragraphStarts[paragraph] == offset else { return true }
            let firstLine = fragment.textLineFragments.first
            let baselineY = frame.minY + (firstLine?.typographicBounds.minY ?? 0) + (firstLine?.glyphOrigin.y ?? 14)
            let label = formatTime(self.paragraphTimes[paragraph]) as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: frame.minX - Self.timestampMargin + 8, y: baselineY - size.height + 3), withAttributes: attrs)
            return true
        }
    }

    /// Ensure every word ID in a set is mapped onto its row's displayed span:
    /// any token of a pause run resolves to the run's chip.
    private func displayedIDs(_ ids: Set<String>) -> Set<String> {
        Set(ids.map { pauseRunFirstID[$0] ?? $0 })
    }

    /// Expand selected chip IDs to every token of their pause run.
    private func expandedIDs(_ ids: [String]) -> [String] {
        ids.flatMap { pauseRuns[$0] ?? [$0] }
    }

    /// Highlight the currently-playing word. O(1) — clears only the previous range.
    /// Playback reports its position about 30 times a second, so a repeated call
    /// for the word that is already highlighted returns without touching the text.
    func highlightWord(id: String?) {
        guard id != currentlyHighlightedId, let storage = textView.textStorage else { return }

        let previousID = currentlyHighlightedId
        currentlyHighlightedId = id
        if let previousID, let word = project?.word(withID: previousID) {
            updateWordAppearance(
                wordId: previousID,
                deleted: word.deleted,
                selected: project?.selectedWordIds.contains(previousID) == true
            )
        }

        if let id, let range = selectionIndex.range(forWordID: id) {
            applyPlaybackHighlight(to: range, in: storage)
            textView.scrollRangeToVisible(range)
        }
    }

    private func applyPlaybackHighlight(to range: NSRange, in storage: NSTextStorage) {
        let color = Settings.shared.highlightColor.withAlphaComponent(0.2)
        storage.addAttribute(.backgroundColor, value: color, range: range)
    }

    /// Apply visual state for a single word.
    func updateWordAppearance(wordId: String, deleted: Bool, selected: Bool) {
        let wordId = pauseRunFirstID[wordId] ?? wordId
        guard let storage = textView.textStorage,
              let range = selectionIndex.range(forWordID: wordId) else {
            return
        }
        if let run = pauseRuns[wordId] {
            updatePauseChipAppearance(run: run, range: range, in: storage, selected: selected)
            return
        }
        let proposed = proposedWordIDs.contains(wordId)
        lastAppearance[wordId] = (deleted, selected, proposed)
        let baseColor = project?.word(withID: wordId)?.isActualSilence == true
            ? Theme.silenceText
            : Theme.wordNormal

        if deleted {
            storage.addAttributes([
                .foregroundColor: Theme.wordDeleted,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: Theme.wordDeletedStrikethrough.withAlphaComponent(0.6),
                .toolTip: "Deleted word. Select it and use Edit > Restore Selected Words to restore it.",
            ], range: range)
            storage.removeAttribute(.backgroundColor, range: range)
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.underlineColor, range: range)
        } else if selected {
            storage.addAttributes([
                .foregroundColor: baseColor,
                .backgroundColor: Theme.wordSelectedBackground,
            ], range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.strikethroughColor, range: range)
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.underlineColor, range: range)
            storage.removeAttribute(.toolTip, range: range)
        } else if proposed {
            storage.addAttributes([
                .foregroundColor: baseColor,
                .backgroundColor: Theme.accent.withAlphaComponent(0.14),
                .underlineStyle: NSUnderlineStyle.single.union(.patternDot).rawValue,
                .underlineColor: Theme.accent,
                .toolTip: "Proposed deletion. Review it before applying the agent edits.",
            ], range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.strikethroughColor, range: range)
        } else {
            storage.addAttributes([
                .foregroundColor: baseColor,
            ], range: range)
            storage.removeAttribute(.backgroundColor, range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.strikethroughColor, range: range)
            storage.removeAttribute(.underlineStyle, range: range)
            storage.removeAttribute(.underlineColor, range: range)
            storage.removeAttribute(.toolTip, range: range)
            if wordId == currentlyHighlightedId {
                applyPlaybackHighlight(to: range, in: storage)
            }
        }
    }

    private func updatePauseChipAppearance(run: [String], range: NSRange, in storage: NSTextStorage, selected: Bool) {
        let deleted = run.allSatisfy { project?.word(withID: $0)?.deleted == true }
        lastAppearance[run[0]] = (deleted, selected, proposedWordIDs.contains(run[0]))
        storage.removeAttribute(.underlineStyle, range: range)
        if deleted {
            storage.addAttributes([
                .foregroundColor: Theme.textDimmed,
                .backgroundColor: NSColor.clear,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: Theme.wordDeletedStrikethrough.withAlphaComponent(0.6),
                .toolTip: "Tightened pause. Click to restore it.",
            ], range: range)
        } else {
            storage.addAttributes([
                .foregroundColor: proposedWordIDs.contains(run[0]) ? Theme.accent : Theme.textSecondary,
                .backgroundColor: selected ? Theme.wordSelectedBackground : Theme.surface3,
                .toolTip: "Pause. Click to tighten it, or click again to restore it.",
            ], range: range)
            storage.removeAttribute(.strikethroughStyle, range: range)
            storage.removeAttribute(.strikethroughColor, range: range)
        }
    }

    /// Diff the full word list against the last appearance snapshot and
    /// update only the words whose visual state actually changed.
    func refreshAllWordAppearances() {
        guard let project else { return }
        updateWordAppearances(wordIDs: Set(project.allWords.map(\.id)))
    }

    /// Update only words affected by an edit or selection delta.
    func updateWordAppearances(wordIDs: Set<String>) {
        guard let project else { return }
        for wordID in displayedIDs(wordIDs) {
            guard let word = project.word(withID: wordID) else { continue }
            let isSelected = project.selectedWordIds.contains(wordID)
            let isProposed = proposedWordIDs.contains(wordID)
            let previousAppearance = lastAppearance[wordID]
            if previousAppearance?.deleted != word.deleted
                || previousAppearance?.selected != isSelected
                || previousAppearance?.proposed != isProposed {
                updateWordAppearance(
                    wordId: wordID,
                    deleted: word.deleted,
                    selected: isSelected
                )
            }
        }
    }

    func setProposedWordIDs(_ wordIDs: Set<String>) {
        let wordIDs = displayedIDs(wordIDs).union(wordIDs)
        let changedWordIDs = proposedWordIDs.symmetricDifference(wordIDs)
        proposedWordIDs = wordIDs
        updateWordAppearances(wordIDs: changedWordIDs)
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

    // MARK: - Native selection

    func textView(
        _ textView: NSTextView,
        willChangeSelectionFromCharacterRanges oldSelectedCharRanges: [NSValue],
        toCharacterRanges newSelectedCharRanges: [NSValue]
    ) -> [NSValue] {
        guard !isSynchronizingSelection else { return newSelectedCharRanges }
        return selectionIndex
            .normalizedCharacterRanges(for: newSelectedCharRanges.map(\.rangeValue))
            .map(NSValue.init(range:))
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        guard !isSynchronizingSelection, let project else { return }

        if let location = textView.selectedRanges.first?.rangeValue.location, !rowStarts.isEmpty {
            activeRow = rowIndex(forCharacterOffset: location)
        }
        let selectedIDs = expandedIDs(selectionIndex
            .wordIDs(intersecting: textView.selectedRanges.map(\.rangeValue)))
        let appearanceChanges = project.selectWords(selectedIDs)
        updateWordAppearances(wordIDs: appearanceChanges)
    }

    func gestureRecognizer(
        _ gestureRecognizer: NSGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: NSGestureRecognizer
    ) -> Bool {
        guard let click = gestureRecognizer as? NSClickGestureRecognizer,
              let otherClick = otherGestureRecognizer as? NSClickGestureRecognizer else {
            return false
        }
        return click.numberOfClicksRequired == 1 && otherClick.numberOfClicksRequired == 2
    }

    /// Select the full transcript through the native text system. The delegate
    /// maps that range back to every word, including reversible deleted words.
    func selectAllTranscriptWords() {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        focusForKeyboardNavigation()
        textView.setSelectedRange(NSRange(location: 0, length: storage.length))
    }

    /// Clear both native selection and the canonical project selection.
    func clearTranscriptSelection() {
        let appearanceChanges = project?.clearSelection() ?? []
        isSynchronizingSelection = true
        textView.setSelectedRange(NSRange(location: textView.selectedRange().location, length: 0))
        isSynchronizingSelection = false
        updateWordAppearances(wordIDs: appearanceChanges)
    }

    /// Patch one corrected word and shift only the indexed character ranges that
    /// follow it. Timing, selection IDs, and edit decisions remain unchanged.
    @discardableResult
    func updateCorrectedWord(id: String, text: String, segments: [Segment]) -> Bool {
        let text = Self.displayText(text)
        guard let storage = textView.textStorage,
              let range = selectionIndex.range(forWordID: id),
              range.location < storage.length,
              !text.isEmpty else {
            return false
        }

        let previousText = (storage.string as NSString).substring(with: range)
        if endsSentence(previousText) != endsSentence(text) {
            setTranscript(segments: segments)
            refreshAllWordAppearances()
            return true
        }

        isSynchronizingSelection = true
        if let textContentStorage = textView.textContentStorage {
            textContentStorage.performEditingTransaction {
                storage.replaceCharacters(in: range, with: text)
            }
        } else {
            storage.replaceCharacters(in: range, with: text)
        }
        let delta = (text as NSString).length - range.length
        if delta != 0 {
            rowStarts = rowStarts.map { $0 > range.location ? $0 + delta : $0 }
            paragraphStarts = paragraphStarts.map { $0 > range.location ? $0 + delta : $0 }
        }
        selectionIndex = selectionIndex.replacingWordText(
            wordID: id,
            newLength: (text as NSString).length
        )
        currentSegments = segments
        if let displayedIndex = selectionIndex.position(forWordID: id),
           displayedWords.indices.contains(displayedIndex) {
            displayedWords[displayedIndex].word = text
        }
        let selectedWordIDs = project?.selectedWordIds ?? []
        if !selectedWordIDs.isEmpty {
            textView.selectedRanges = selectionIndex
                .characterRanges(forWordIDs: selectedWordIDs)
                .map(NSValue.init(range:))
        }
        isSynchronizingSelection = false
        return true
    }

    private func endsSentence(_ text: String) -> Bool {
        text.hasSuffix(".") || text.hasSuffix("!") || text.hasSuffix("?")
    }

    @objc private func handleTextClick(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: textView)
        let index = textView.characterIndexForInsertion(at: point)
        if !rowStarts.isEmpty {
            activeRow = rowIndex(forCharacterOffset: max(0, index))
        }
        guard let wordID = wordId(atTextViewPoint: point),
              let word = project?.word(withID: wordID) else {
            return
        }
        if let run = pauseRuns[wordID] {
            let allCut = run.allSatisfy { project?.word(withID: $0)?.deleted == true }
            onSetWordsDeleted?(Set(run), !allCut)
            clearTranscriptSelection()
            return
        }

        if word.deleted {
            onRestoreWord?(wordID)
            clearTranscriptSelection()
            return
        }

        onWordClicked?(word)
    }

    @objc private func handleTextDoubleClick(_ recognizer: NSClickGestureRecognizer) {
        let point = recognizer.location(in: textView)
        guard let wordID = wordId(atTextViewPoint: point),
              let word = project?.word(withID: wordID),
              !word.deleted,
              !word.isActualSilence else {
            return
        }
        onCorrectWord?(wordID)
    }
}

// MARK: - Selection index

struct TranscriptSelectionSpan: Equatable {
    let wordID: String
    let range: NSRange
}

struct TranscriptSelectionIndex {
    let spans: [TranscriptSelectionSpan]
    private let positionsByWordID: [String: Int]

    init(spans: [TranscriptSelectionSpan]) {
        self.spans = spans.sorted { $0.range.location < $1.range.location }
        self.positionsByWordID = Dictionary(
            uniqueKeysWithValues: self.spans.enumerated().map { ($0.element.wordID, $0.offset) }
        )
    }

    private init(
        orderedSpans: [TranscriptSelectionSpan],
        positionsByWordID: [String: Int]
    ) {
        self.spans = orderedSpans
        self.positionsByWordID = positionsByWordID
    }

    func wordIDs(intersecting ranges: [NSRange]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []

        for range in ranges {
            for span in intersectingSpans(for: range) where seen.insert(span.wordID).inserted {
                result.append(span.wordID)
            }
        }

        return result
    }

    func range(forWordID wordID: String) -> NSRange? {
        guard let position = position(forWordID: wordID) else { return nil }
        return spans[position].range
    }

    func position(forWordID wordID: String) -> Int? {
        positionsByWordID[wordID]
    }

    func normalizedCharacterRanges(for ranges: [NSRange]) -> [NSRange] {
        let normalized = ranges.compactMap { range -> NSRange? in
            let matches = intersectingSpans(for: range)
            guard let first = matches.first, let last = matches.last else { return nil }
            return NSRange(
                location: first.range.location,
                length: NSMaxRange(last.range) - first.range.location
            )
        }

        guard !normalized.isEmpty else {
            return ranges.first.map { [$0] } ?? [NSRange(location: 0, length: 0)]
        }

        return mergeOverlappingRanges(normalized)
    }

    func characterRanges(forWordIDs wordIDs: Set<String>) -> [NSRange] {
        guard !wordIDs.isEmpty else { return [] }
        if wordIDs.count > spans.count / 2 {
            return characterRangesByScanningAllSpans(forWordIDs: wordIDs)
        }

        let positions = wordIDs.compactMap { positionsByWordID[$0] }.sorted()
        var result: [NSRange] = []
        guard let firstPosition = positions.first else { return result }
        var runStartPosition = firstPosition
        var previousPosition = firstPosition

        for position in positions.dropFirst() {
            guard position != previousPosition + 1 else {
                previousPosition = position
                continue
            }
            result.append(characterRange(from: runStartPosition, through: previousPosition))
            runStartPosition = position
            previousPosition = position
        }
        result.append(characterRange(from: runStartPosition, through: previousPosition))
        return result
    }

    private func characterRangesByScanningAllSpans(forWordIDs wordIDs: Set<String>) -> [NSRange] {
        var result: [NSRange] = []
        var runStartPosition: Int?

        for (position, span) in spans.enumerated() {
            guard wordIDs.contains(span.wordID) else {
                if let runStartPosition {
                    result.append(characterRange(from: runStartPosition, through: position - 1))
                }
                runStartPosition = nil
                continue
            }
            runStartPosition = runStartPosition ?? position
        }

        if let runStartPosition {
            result.append(characterRange(from: runStartPosition, through: spans.count - 1))
        }
        return result
    }

    private func characterRange(from startPosition: Int, through endPosition: Int) -> NSRange {
        let firstRange = spans[startPosition].range
        let lastRange = spans[endPosition].range
        return NSRange(
            location: firstRange.location,
            length: NSMaxRange(lastRange) - firstRange.location
        )
    }

    func replacingWordText(wordID: String, newLength: Int) -> TranscriptSelectionIndex {
        guard let index = positionsByWordID[wordID] else { return self }
        var updatedSpans = spans
        let oldRange = updatedSpans[index].range
        let lengthDelta = newLength - oldRange.length
        updatedSpans[index] = TranscriptSelectionSpan(
            wordID: wordID,
            range: NSRange(location: oldRange.location, length: newLength)
        )

        guard lengthDelta != 0, index + 1 < updatedSpans.count else {
            return TranscriptSelectionIndex(
                orderedSpans: updatedSpans,
                positionsByWordID: positionsByWordID
            )
        }
        for followingIndex in (index + 1)..<updatedSpans.count {
            let span = updatedSpans[followingIndex]
            updatedSpans[followingIndex] = TranscriptSelectionSpan(
                wordID: span.wordID,
                range: NSRange(
                    location: span.range.location + lengthDelta,
                    length: span.range.length
                )
            )
        }
        return TranscriptSelectionIndex(
            orderedSpans: updatedSpans,
            positionsByWordID: positionsByWordID
        )
    }

    private func intersectingSpans(for range: NSRange) -> ArraySlice<TranscriptSelectionSpan> {
        guard range.location != NSNotFound, !spans.isEmpty else { return [] }

        let queryEnd = range.length == 0 ? range.location + 1 : NSMaxRange(range)
        var lowerBound = 0
        var upperBound = spans.count

        while lowerBound < upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            if NSMaxRange(spans[midpoint].range) <= range.location {
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint
            }
        }

        let startIndex = lowerBound
        var endIndex = startIndex
        while endIndex < spans.count, spans[endIndex].range.location < queryEnd {
            endIndex += 1
        }
        return spans[startIndex..<endIndex]
    }

    private func mergeOverlappingRanges(_ ranges: [NSRange]) -> [NSRange] {
        let sortedRanges = ranges.sorted { $0.location < $1.location }
        var merged: [NSRange] = []

        for range in sortedRanges {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            if range.location <= NSMaxRange(last) {
                merged[merged.count - 1] = NSRange(
                    location: last.location,
                    length: max(NSMaxRange(last), NSMaxRange(range)) - last.location
                )
            } else {
                merged.append(range)
            }
        }

        return merged
    }
}

// MARK: - Transcript text view

/// The transcript's text view: draws paragraph times in the margin and handles
/// X (cut or keep the current sentence) and Return (play it) without modifiers.
final class TranscriptRowTextView: NSTextView {
    weak var rowOwner: TranscriptView?

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        rowOwner?.drawParagraphTimes(in: rect)
    }

    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard let owner = rowOwner, modifiers.isEmpty else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 36 || event.keyCode == 76 {
            owner.playActiveRow()
        } else if event.charactersIgnoringModifiers?.lowercased() == "x" {
            owner.toggleActiveRow()
        } else {
            super.keyDown(with: event)
        }
    }
}
