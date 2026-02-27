import AppKit

/// Custom NSTextView attribute key for storing word IDs on text ranges.
extension NSAttributedString.Key {
    static let wordID = NSAttributedString.Key("com.redact.wordID")
}

/// Read-only transcript display with styled text, paragraph breaks at gaps, and dimmed silence tokens.
/// In Phase 4 this gets click/drag interaction and visual states.
class TranscriptView: NSView {
    private let scrollView = NSScrollView()
    private let textView = NSTextView()

    /// Maps word IDs to their NSRange in the text storage.
    private(set) var wordRanges: [String: NSRange] = [:]

    /// All words in display order (for hit-testing and interaction).
    private(set) var displayedWords: [Word] = []

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

        // Scroll view
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        // Text view
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

    /// Build the transcript text from segments with paragraph breaks.
    func setTranscript(segments: [Segment]) {
        wordRanges = [:]
        displayedWords = []

        let textStorage = NSMutableAttributedString()

        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .regular),
            .foregroundColor: Theme.wordNormal,
        ]

        let silenceAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .light),
            .foregroundColor: Theme.silenceText,
        ]

        var previousWordEnd: Double = 0
        var isFirstWord = true

        for segment in segments {
            for word in segment.words {
                displayedWords.append(word)

                // Add paragraph break at >1s gaps between spoken words (not silence tokens)
                if !isFirstWord && !word.isActualSilence {
                    let gap = word.start - previousWordEnd
                    if gap > 1.0 {
                        textStorage.append(NSAttributedString(string: "\n\n", attributes: normalAttrs))
                    }
                }

                // Add space between words (not at start)
                if !isFirstWord {
                    textStorage.append(NSAttributedString(string: " ", attributes: normalAttrs))
                }

                // Word text
                let attrs = word.isActualSilence ? silenceAttrs : normalAttrs
                var wordAttrs = attrs
                wordAttrs[.wordID] = word.id

                let range = NSRange(location: textStorage.length, length: word.word.count)
                textStorage.append(NSAttributedString(string: word.word, attributes: wordAttrs))
                wordRanges[word.id] = range

                if !word.isActualSilence {
                    previousWordEnd = word.end
                }
                isFirstWord = false
            }
        }

        textView.textStorage?.setAttributedString(textStorage)
    }

    /// Highlight the currently-playing word with a subtle background.
    func highlightWord(id: String?) {
        guard let storage = textView.textStorage else { return }

        // Clear previous highlight
        storage.enumerateAttribute(.backgroundColor, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value != nil {
                storage.removeAttribute(.backgroundColor, range: range)
            }
        }

        // Apply new highlight
        if let id, let range = wordRanges[id] {
            let highlightColor = Theme.wordHighlightBackground
            storage.addAttribute(.backgroundColor, value: highlightColor, range: range)

            // Auto-scroll to visible
            textView.scrollRangeToVisible(range)
        }
    }

    /// Update visual state for a word (deleted, selected, normal).
    func updateWordAppearance(wordId: String, deleted: Bool, selected: Bool) {
        guard let storage = textView.textStorage, let range = wordRanges[wordId] else { return }

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

    /// Get the word ID at a given point in the view.
    func wordId(at point: NSPoint) -> String? {
        let textPoint = textView.convert(point, from: self)
        let index = textView.characterIndexForInsertion(at: textPoint)
        guard index >= 0, index < (textView.textStorage?.length ?? 0) else { return nil }
        return textView.textStorage?.attribute(.wordID, at: index, effectiveRange: nil) as? String
    }
}
