import Foundation

/// Undo entry recording word state changes for delta-based undo/redo.
struct UndoEntry {
    let wordChanges: [(wordId: String, deleted: Bool)]
}

/// Raw transcript as received from Whisper (before silence injection).
struct RawWord: Codable {
    let word: String
    let start: Double
    let end: Double
    let confidence: Double
}

struct RawSegment: Codable {
    let id: Int
    let words: [RawWord]
}

struct RawTranscript: Codable {
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

    // Transcript
    var segments: [Segment] = []
    var allWords: [Word] = []
    var language: String = ""

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

    // MARK: - Constants

    private static let silenceThreshold: Double = 0.8
    private static let silenceChunk: Double = 0.5
    private static let maxUndoLevels = 100

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

        segments = finalSegments
        allWords = finalSegments.flatMap(\.words)
        language = transcript.language
        duration = transcript.duration
        appState = .editing
        undoStack = []
        redoStack = []
    }

    // MARK: - Selection

    func selectWords(_ ids: [String]) {
        selectedWordIds = Set(ids)
    }

    func addToSelection(_ ids: [String]) {
        for id in ids {
            selectedWordIds.insert(id)
        }
    }

    func clearSelection() {
        selectedWordIds = []
    }

    func selectAll() {
        let allIds = allWords.filter { !$0.deleted }.map(\.id)
        selectedWordIds = Set(allIds)
    }

    // MARK: - Delete / Restore

    func deleteSelected() {
        guard !selectedWordIds.isEmpty else { return }

        var changes: [(wordId: String, deleted: Bool)] = []
        let newSegments = segments.map { seg in
            Segment(id: seg.id, words: seg.words.map { w in
                if selectedWordIds.contains(w.id) && !w.deleted {
                    changes.append((wordId: w.id, deleted: false))
                    return Word(id: w.id, word: w.word, start: w.start, end: w.end,
                                confidence: w.confidence, deleted: true, isSilence: w.isSilence)
                }
                return w
            })
        }

        guard !changes.isEmpty else { return }

        undoStack.append(UndoEntry(wordChanges: changes))
        if undoStack.count > Self.maxUndoLevels {
            undoStack.removeFirst(undoStack.count - Self.maxUndoLevels)
        }
        redoStack = []

        segments = newSegments
        allWords = newSegments.flatMap(\.words)
        selectedWordIds = []
    }

    func restoreWord(_ id: String) {
        var changes: [(wordId: String, deleted: Bool)] = []
        let newSegments = segments.map { seg in
            Segment(id: seg.id, words: seg.words.map { w in
                if w.id == id && w.deleted {
                    changes.append((wordId: w.id, deleted: true))
                    return Word(id: w.id, word: w.word, start: w.start, end: w.end,
                                confidence: w.confidence, deleted: false, isSilence: w.isSilence)
                }
                return w
            })
        }

        guard !changes.isEmpty else { return }

        undoStack.append(UndoEntry(wordChanges: changes))
        if undoStack.count > Self.maxUndoLevels {
            undoStack.removeFirst(undoStack.count - Self.maxUndoLevels)
        }
        redoStack = []

        segments = newSegments
        allWords = newSegments.flatMap(\.words)
    }

    // MARK: - Undo / Redo

    func undo() {
        guard let entry = undoStack.last else { return }

        let wordMap = Dictionary(uniqueKeysWithValues: entry.wordChanges.map { ($0.wordId, $0.deleted) })

        let newSegments = segments.map { seg in
            Segment(id: seg.id, words: seg.words.map { w in
                if let previousDeleted = wordMap[w.id] {
                    return Word(id: w.id, word: w.word, start: w.start, end: w.end,
                                confidence: w.confidence, deleted: previousDeleted, isSilence: w.isSilence)
                }
                return w
            })
        }

        // Build redo entry (inverse)
        let redoChanges = entry.wordChanges.map { (wordId: $0.wordId, deleted: !$0.deleted) }

        undoStack.removeLast()
        redoStack.append(UndoEntry(wordChanges: redoChanges))

        segments = newSegments
        allWords = newSegments.flatMap(\.words)
    }

    func redo() {
        guard let entry = redoStack.last else { return }

        let wordMap = Dictionary(uniqueKeysWithValues: entry.wordChanges.map { ($0.wordId, $0.deleted) })

        let newSegments = segments.map { seg in
            Segment(id: seg.id, words: seg.words.map { w in
                if let targetDeleted = wordMap[w.id] {
                    return Word(id: w.id, word: w.word, start: w.start, end: w.end,
                                confidence: w.confidence, deleted: !targetDeleted, isSilence: w.isSilence)
                }
                return w
            })
        }

        // Build undo entry (inverse of redo)
        let undoChanges = entry.wordChanges.map { (wordId: $0.wordId, deleted: $0.deleted) }

        redoStack.removeLast()
        undoStack.append(UndoEntry(wordChanges: undoChanges))

        segments = newSegments
        allWords = newSegments.flatMap(\.words)
    }

    // MARK: - Load Project

    func loadProject(segments: [Segment], language: String, duration: Double, filePath: String) {
        self.segments = segments
        self.allWords = segments.flatMap(\.words)
        self.language = language
        self.duration = duration
        self.filePath = filePath
        self.appState = .editing
        self.undoStack = []
        self.redoStack = []
        self.selectedWordIds = []
        self.currentTime = 0
        self.isPlaying = false
        self.highlightedWordId = nil
        self.transcribeProgress = nil
        self.exportProgress = nil
    }

    // MARK: - Reset

    func reset() {
        appState = .empty
        filePath = nil
        audioPath = nil
        duration = 0
        segments = []
        allWords = []
        language = ""
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
}
