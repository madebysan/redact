import AppKit

/// Custom NSTextView attribute key for storing word IDs on text ranges.
extension NSAttributedString.Key {
    static let wordID = NSAttributedString.Key("com.redact.wordID")
}

/// Read-only transcript display with styled text, paragraph breaks at gaps,
/// dimmed silence tokens, and native TextKit 2 selection.
class TranscriptView: NSView, NSTextViewDelegate, NSGestureRecognizerDelegate {
    private let scrollView = NSScrollView()
    private let textView: NSTextView

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

    override init(frame frameRect: NSRect) {
        self.textView = NSTextView(usingTextLayoutManager: true)
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        self.textView = NSTextView(usingTextLayoutManager: true)
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
            "Select transcript words to edit, copy, or search. Double-click a spoken word to correct its text. Deleted words are struck through and can be clicked to restore."
        )

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
        displayedWords = []
        var selectionSpans: [TranscriptSelectionSpan] = []
        currentlyHighlightedId = nil
        lastAppearance = [:]

        let lines = computeLines(segments: segments)
        let textStorage = NSMutableAttributedString()
        let settings = Settings.shared
        let fontSize = settings.transcriptFontSize

        let lineStyle = NSMutableParagraphStyle()
        lineStyle.paragraphSpacing = settings.transcriptLineSpacing
        lineStyle.paragraphSpacingBefore = 0
        lineStyle.firstLineHeadIndent = 56            // room for timestamp + future drag handle
        lineStyle.headIndent = 56                     // wrapped lines align under body
        lineStyle.lineSpacing = settings.transcriptLineSpacing * 0.2

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: settings.transcriptFont(ofSize: fontSize, weight: .regular),
            .kern: settings.transcriptLetterSpacing,
            .foregroundColor: Theme.wordNormal,
            .paragraphStyle: lineStyle,
        ]

        let silenceAttrs: [NSAttributedString.Key: Any] = [
            .font: settings.transcriptFont(ofSize: fontSize - 2, weight: .light),
            .kern: settings.transcriptLetterSpacing,
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

                let range = NSRange(
                    location: textStorage.length,
                    length: (word.word as NSString).length
                )
                textStorage.append(NSAttributedString(string: word.word, attributes: wordAttrs))
                selectionSpans.append(TranscriptSelectionSpan(wordID: word.id, range: range))
            }
        }

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
    }

    /// Highlight the currently-playing word. O(1) — clears only the previous range.
    func highlightWord(id: String?) {
        guard let storage = textView.textStorage else { return }

        if let prevId = currentlyHighlightedId,
           let word = project?.word(withID: prevId) {
            updateWordAppearance(
                wordId: prevId,
                deleted: word.deleted,
                selected: project?.selectedWordIds.contains(prevId) == true
            )
        }

        currentlyHighlightedId = id

        if let id, let range = selectionIndex.range(forWordID: id) {
            let color = Settings.shared.highlightColor.withAlphaComponent(0.2)
            storage.addAttribute(.backgroundColor, value: color, range: range)
            textView.scrollRangeToVisible(range)
        }
    }

    /// Apply visual state for a single word.
    func updateWordAppearance(wordId: String, deleted: Bool, selected: Bool) {
        guard let storage = textView.textStorage,
              let range = selectionIndex.range(forWordID: wordId) else {
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

        for wordID in wordIDs {
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

        let selectedIDs = selectionIndex
            .wordIDs(intersecting: textView.selectedRanges.map(\.rangeValue))
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
        guard let wordID = wordId(atTextViewPoint: point),
              let word = project?.word(withID: wordID) else {
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
