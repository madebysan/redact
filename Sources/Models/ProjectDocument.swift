import Foundation

/// Undo entry recording word state changes for delta-based undo/redo.
struct UndoEntry {
    let wordChanges: [(wordId: String, deleted: Bool)]
    let textChanges: [(wordId: String, text: String)]

    init(
        wordChanges: [(wordId: String, deleted: Bool)] = [],
        textChanges: [(wordId: String, text: String)] = []
    ) {
        self.wordChanges = wordChanges
        self.textChanges = textChanges
    }
}

private struct WordLocation {
    let segmentIndex: Int
    let wordIndex: Int
}

/// Raw transcript as received from Whisper (before silence injection).
struct RawWord: Codable, Equatable, Sendable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double
}

struct RawSegment: Codable, Equatable, Sendable {
    let id: Int
    let words: [RawWord]
}

struct RawTranscript: Codable, Equatable, Sendable {
    let segments: [RawSegment]
    let language: String
    let duration: Double
}

/// Observable project state — central model for the app.
@Observable
class ProjectDocument {
    // App state
    var appState: AppState = .empty
    var filePath: String?
    var audioPath: String?
    var duration: Double = 0
    var mediaInfo: MediaInfo?

    // Transcript
    var segments: [Segment] = []
    var allWords: [Word] = []
    var language: String = ""
    private(set) var revision: ProjectRevision?
    private var transcriptIndex: TranscriptIndex?
    private var wordLocations: [String: WordLocation] = [:]

    var sourceTranscript: SourceTranscript? {
        revision?.transcript
    }

    var editDecisionList: EditDecisionList {
        revision?.edits ?? EditDecisionList()
    }

    // Playback
    var currentTime: Double = 0
    var isPlaying: Bool = false
    var playbackRate: Double = 1
    var highlightedWordId: String?

    // Selection
    var selectedWordIds: Set<String> = []

    // Transcription progress
    var transcribeProgress: TranscribeProgress?

    // Export
    var exportProgress: Double?

    // Error
    var errorMessage: String?

    // Undo/redo (delta-based, max 100)
    private(set) var undoStack: [UndoEntry] = []
    private(set) var redoStack: [UndoEntry] = []

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var hasEditableTranscript: Bool {
        appState == .editing || appState == .missingMedia
    }

    // MARK: - Constants

    private static let silenceThreshold: Double = 0.8
    private static let silenceChunk: Double = 0.5
    private static let maxUndoLevels = 100
    private static let maxCorrectedWordLength = 200

    // MARK: - Set Transcript (with silence injection)

    func setTranscript(_ transcript: RawTranscript) {
        // First pass: assign unique IDs to every spoken word
        var wordIndex = 0
        let spokenSegments: [Segment] = transcript.segments.map { seg in
            let words: [Word] = seg.words.map { w in
                let word = Word(
                    id: "w_\(wordIndex)",
                    word: w.word,
                    start: w.start,
                    end: w.end,
                    confidence: w.confidence,
                    deleted: false,
                    isSilence: nil
                )
                wordIndex += 1
                return word
            }
            return Segment(id: seg.id, words: words)
        }

        // Second pass: inject silence tokens between words where gaps exceed threshold
        var silenceIndex = 0
        let finalSegments: [Segment] = spokenSegments.enumerated().map { (segIdx, seg) in
            var wordsWithSilence: [Word] = []

            // Check gap from previous segment's last word to this segment's first word
            if segIdx > 0, !seg.words.isEmpty {
                let prevSeg = spokenSegments[segIdx - 1]
                if !prevSeg.words.isEmpty {
                    let prevEnd = prevSeg.words[prevSeg.words.count - 1].end
                    let currStart = seg.words[0].start
                    let gap = currStart - prevEnd

                    if gap > Self.silenceThreshold {
                        let numTokens = max(1, Int(round(gap / Self.silenceChunk)))
                        let tokenDuration = gap / Double(numTokens)
                        for i in 0..<numTokens {
                            wordsWithSilence.append(Word(
                                id: "s_\(silenceIndex)",
                                word: "\u{2014}",
                                start: prevEnd + Double(i) * tokenDuration,
                                end: prevEnd + Double(i + 1) * tokenDuration,
                                confidence: 1,
                                deleted: false,
                                isSilence: true
                            ))
                            silenceIndex += 1
                        }
                    }
                }
            }

            // Check gaps within the segment (between consecutive words)
            for i in 0..<seg.words.count {
                if i > 0 {
                    let prevEnd = seg.words[i - 1].end
                    let currStart = seg.words[i].start
                    let gap = currStart - prevEnd

                    if gap > Self.silenceThreshold {
                        let numTokens = max(1, Int(round(gap / Self.silenceChunk)))
                        let tokenDuration = gap / Double(numTokens)
                        for j in 0..<numTokens {
                            wordsWithSilence.append(Word(
                                id: "s_\(silenceIndex)",
                                word: "\u{2014}",
                                start: prevEnd + Double(j) * tokenDuration,
                                end: prevEnd + Double(j + 1) * tokenDuration,
                                confidence: 1,
                                deleted: false,
                                isSilence: true
                            ))
                            silenceIndex += 1
                        }
                    }
                }

                wordsWithSilence.append(seg.words[i])
            }

            return Segment(id: seg.id, words: wordsWithSilence)
        }

        installTranscriptProjection(
            segments: finalSegments,
            language: transcript.language,
            duration: transcript.duration
        )
        language = transcript.language
        duration = transcript.duration
        appState = .editing
        undoStack = []
        redoStack = []
    }

    // MARK: - Selection

    @discardableResult
    func selectWords(_ ids: [String]) -> Set<String> {
        let nextSelection = Set(ids)
        let changedWordIDs = selectedWordIds.symmetricDifference(nextSelection)
        selectedWordIds = nextSelection
        return changedWordIDs
    }

    @discardableResult
    func addToSelection(_ ids: [String]) -> Set<String> {
        let previousSelection = selectedWordIds
        selectedWordIds.formUnion(ids)
        return previousSelection.symmetricDifference(selectedWordIds)
    }

    @discardableResult
    func clearSelection() -> Set<String> {
        let changedWordIDs = selectedWordIds
        selectedWordIds = []
        return changedWordIDs
    }

    @discardableResult
    func selectAll() -> Set<String> {
        let previousSelection = selectedWordIds
        let allIds = allWords.filter { !$0.deleted }.map(\.id)
        selectedWordIds = Set(allIds)
        return previousSelection.symmetricDifference(selectedWordIds)
    }

    // MARK: - Delete / Restore

    @discardableResult
    func deleteSelected() -> Set<String> {
        guard !selectedWordIds.isEmpty else { return [] }

        let changes = selectedWordIds.compactMap { id -> (wordId: String, deleted: Bool)? in
            guard let word = word(withID: id), !word.deleted else { return nil }
            return (wordId: id, deleted: false)
        }
        guard !changes.isEmpty else { return [] }

        recordUndo(UndoEntry(wordChanges: changes))
        let selectedWordIDs = selectedWordIds
        let changedWordIDs = applyDeletionStates(
            Dictionary(uniqueKeysWithValues: changes.map { ($0.wordId, true) })
        )
        selectedWordIds = []
        return selectedWordIDs.union(changedWordIDs)
    }

    /// Delete a reviewed set of transcript words as one undoable edit.
    @discardableResult
    func deleteWords(_ ids: Set<String>) -> Set<String> {
        let changes = ids.compactMap { id -> (wordId: String, deleted: Bool)? in
            guard let word = word(withID: id), !word.deleted else { return nil }
            return (wordId: id, deleted: false)
        }
        guard !changes.isEmpty else { return [] }

        recordUndo(UndoEntry(wordChanges: changes))
        let changedWordIDs = applyDeletionStates(
            Dictionary(uniqueKeysWithValues: changes.map { ($0.wordId, true) })
        )
        selectedWordIds.subtract(changedWordIDs)
        return changedWordIDs
    }

    @discardableResult
    func restoreWord(_ id: String) -> Set<String> {
        guard let word = word(withID: id), word.deleted else { return [] }

        recordUndo(UndoEntry(wordChanges: [(wordId: id, deleted: true)]))
        return applyDeletionStates([id: false])
    }

    @discardableResult
    func restoreSelected() -> Set<String> {
        let changes = selectedWordIds.compactMap { id -> (wordId: String, deleted: Bool)? in
            guard let word = word(withID: id), word.deleted else { return nil }
            return (wordId: id, deleted: true)
        }
        guard !changes.isEmpty else { return [] }

        recordUndo(UndoEntry(wordChanges: changes))
        let selectedWordIDs = selectedWordIds
        let changedWordIDs = applyDeletionStates(
            Dictionary(uniqueKeysWithValues: changes.map { ($0.wordId, false) })
        )
        selectedWordIds = []
        return selectedWordIDs.union(changedWordIDs)
    }

    /// Correct visible transcript text while preserving the word's identity,
    /// timing, and deletion decision.
    @discardableResult
    func correctWordText(id: String, text: String) -> Set<String> {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty,
              normalizedText.count <= Self.maxCorrectedWordLength,
              let word = word(withID: id),
              !word.isActualSilence,
              word.word != normalizedText else {
            return []
        }

        recordUndo(UndoEntry(textChanges: [(wordId: id, text: word.word)]))
        return applyTextChanges([id: normalizedText])
    }

    // MARK: - Undo / Redo

    @discardableResult
    func undo() -> Set<String> {
        guard let entry = undoStack.popLast() else { return [] }
        redoStack.append(inverseEntry(for: entry))
        return applyUndoEntry(entry)
    }

    @discardableResult
    func redo() -> Set<String> {
        guard let entry = redoStack.popLast() else { return [] }
        undoStack.append(inverseEntry(for: entry))
        return applyUndoEntry(entry)
    }

    // MARK: - Indexed transcript access

    func word(withID id: String) -> Word? {
        guard let position = transcriptIndex?.position(forWordID: id),
              allWords.indices.contains(position) else {
            return nil
        }
        return allWords[position]
    }

    func wordIDs(from fromID: String, to toID: String) -> [String] {
        guard let transcript = sourceTranscript,
              let range = transcriptIndex?.closedRange(fromWordID: fromID, toWordID: toID) else {
            return []
        }
        return transcript.words[range].map(\.id)
    }

    func renderPlan(policy: EditTimingPolicy) -> RenderPlan? {
        revision?.renderPlan(policy: policy)
    }

    func renderPlan(
        deletingAdditionalWordIDs wordIDs: Set<String>,
        policy: EditTimingPolicy
    ) -> RenderPlan? {
        guard let transcript = sourceTranscript else { return nil }
        let edits = editDecisionList.applying(.delete(wordIDs: wordIDs))
        return RenderPlan(transcript: transcript, edits: edits, policy: policy)
    }

    // MARK: - Load Project

    func loadProject(segments: [Segment], language: String, duration: Double, filePath: String) {
        installTranscriptProjection(
            segments: segments,
            language: language,
            duration: duration
        )
        self.language = language
        self.duration = duration
        self.filePath = filePath
        self.appState = filePath.isEmpty ? .missingMedia : .editing
        self.undoStack = []
        self.redoStack = []
        self.selectedWordIds = []
        self.currentTime = 0
        self.isPlaying = false
        self.highlightedWordId = nil
        self.transcribeProgress = nil
        self.exportProgress = nil
    }

    func loadProject(
        transcript: SourceTranscript,
        edits: EditDecisionList,
        segmentStartWordIDs: [String],
        filePath: String
    ) {
        let segmentStarts = Set(segmentStartWordIDs)
        var projectedSegments: [Segment] = []
        var projectedWords: [Word] = []

        func appendSegment() {
            guard !projectedWords.isEmpty else { return }
            projectedSegments.append(
                Segment(id: projectedSegments.count, words: projectedWords)
            )
            projectedWords = []
        }

        for word in transcript.words {
            if segmentStarts.contains(word.id), !projectedWords.isEmpty {
                appendSegment()
            }
            projectedWords.append(
                Word(
                    id: word.id,
                    word: word.text,
                    start: word.start,
                    end: word.end,
                    confidence: word.confidence,
                    deleted: edits.contains(wordID: word.id),
                    isSilence: word.isSilence
                )
            )
        }
        appendSegment()

        loadProject(
            segments: projectedSegments,
            language: transcript.language,
            duration: transcript.duration,
            filePath: filePath
        )
    }

    // MARK: - Reset

    func reset() {
        appState = .empty
        filePath = nil
        audioPath = nil
        duration = 0
        mediaInfo = nil
        segments = []
        allWords = []
        language = ""
        revision = nil
        transcriptIndex = nil
        wordLocations = [:]
        currentTime = 0
        isPlaying = false
        playbackRate = 1
        highlightedWordId = nil
        selectedWordIds = []
        transcribeProgress = nil
        exportProgress = nil
        errorMessage = nil
        undoStack = []
        redoStack = []
    }

    // MARK: - Canonical edit projection

    private func installTranscriptProjection(
        segments: [Segment],
        language: String,
        duration: Double
    ) {
        let words = segments.flatMap(\.words)
        let transcript = SourceTranscript(
            v1Words: words,
            language: language,
            duration: duration
        )
        let edits = EditDecisionList(v1Words: words)

        self.segments = segments
        allWords = words
        revision = ProjectRevision(transcript: transcript, edits: edits)
        transcriptIndex = TranscriptIndex(transcript: transcript)
        wordLocations = Dictionary(
            uniqueKeysWithValues: segments.enumerated().flatMap { segmentIndex, segment in
                segment.words.enumerated().map { wordIndex, word in
                    (
                        word.id,
                        WordLocation(segmentIndex: segmentIndex, wordIndex: wordIndex)
                    )
                }
            }
        )
    }

    private func recordUndo(_ entry: UndoEntry) {
        undoStack.append(entry)
        if undoStack.count > Self.maxUndoLevels {
            undoStack.removeFirst(undoStack.count - Self.maxUndoLevels)
        }
        redoStack = []
    }

    private func applyDeletionStates(_ states: [String: Bool]) -> Set<String> {
        guard var nextRevision = revision else { return [] }

        let changedStates = states.filter { id, deleted in
            guard let word = word(withID: id) else { return false }
            return word.deleted != deleted
        }
        guard !changedStates.isEmpty else { return [] }

        let deletedWordIDs = Set(changedStates.compactMap { id, deleted in
            deleted ? id : nil
        })
        let restoredWordIDs = Set(changedStates.compactMap { id, deleted in
            deleted ? nil : id
        })

        if !deletedWordIDs.isEmpty {
            nextRevision = nextRevision.applying(.delete(wordIDs: deletedWordIDs))
        }
        if !restoredWordIDs.isEmpty {
            nextRevision = nextRevision.applying(.restore(wordIDs: restoredWordIDs))
        }
        revision = nextRevision

        for (id, deleted) in changedStates {
            guard let position = transcriptIndex?.position(forWordID: id),
                  allWords.indices.contains(position),
                  let location = wordLocations[id],
                  segments.indices.contains(location.segmentIndex),
                  segments[location.segmentIndex].words.indices.contains(location.wordIndex) else {
                continue
            }
            allWords[position].deleted = deleted
            segments[location.segmentIndex].words[location.wordIndex].deleted = deleted
        }

        return Set(changedStates.keys)
    }

    private func applyTextChanges(_ changes: [String: String]) -> Set<String> {
        guard var nextRevision = revision else { return [] }
        let changedText = changes.filter { id, text in
            guard let word = word(withID: id), !word.isActualSilence else { return false }
            return word.word != text
        }
        guard !changedText.isEmpty else { return [] }

        var appliedText: [String: String] = [:]
        for (id, text) in changedText {
            guard let correctedRevision = nextRevision.correctingWordText(
                wordID: id,
                text: text
            ) else {
                continue
            }
            nextRevision = correctedRevision
            appliedText[id] = text
        }
        guard !appliedText.isEmpty else { return [] }
        revision = nextRevision

        for (id, text) in appliedText {
            guard let position = transcriptIndex?.position(forWordID: id),
                  allWords.indices.contains(position),
                  let location = wordLocations[id],
                  segments.indices.contains(location.segmentIndex),
                  segments[location.segmentIndex].words.indices.contains(location.wordIndex) else {
                continue
            }
            allWords[position].word = text
            segments[location.segmentIndex].words[location.wordIndex].word = text
        }
        return Set(appliedText.keys)
    }

    private func inverseEntry(for entry: UndoEntry) -> UndoEntry {
        UndoEntry(
            wordChanges: entry.wordChanges.compactMap { change in
                guard let word = word(withID: change.wordId) else { return nil }
                return (wordId: change.wordId, deleted: word.deleted)
            },
            textChanges: entry.textChanges.compactMap { change in
                guard let word = word(withID: change.wordId) else { return nil }
                return (wordId: change.wordId, text: word.word)
            }
        )
    }

    private func applyUndoEntry(_ entry: UndoEntry) -> Set<String> {
        let deletionChanges = applyDeletionStates(
            Dictionary(uniqueKeysWithValues: entry.wordChanges.map { ($0.wordId, $0.deleted) })
        )
        let textChanges = applyTextChanges(
            Dictionary(uniqueKeysWithValues: entry.textChanges.map { ($0.wordId, $0.text) })
        )
        return deletionChanges.union(textChanges)
    }
}
