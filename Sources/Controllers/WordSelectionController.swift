import AppKit

/// Handles word selection interactions: click, drag, shift-click, cmd-click.
/// Port of useWordSelection.ts.
class WordSelectionController {
    weak var project: ProjectDocument?
    weak var transcriptView: TranscriptView?
    var onWordClicked: ((Word) -> Void)?

    private var isDragging = false
    private var dragStartId: String?
    private var lastClickId: String?

    /// Handle mouse down on a word. Returns true if the event was consumed.
    func handleMouseDown(wordId: String, event: NSEvent) -> Bool {
        guard let project else { return false }
        guard let word = project.allWords.first(where: { $0.id == wordId }) else { return false }

        // Deleted words: click to restore
        if word.deleted {
            project.restoreWord(wordId)
            refreshAllWordAppearances()
            return true
        }

        isDragging = true
        dragStartId = wordId

        let isShift = event.modifierFlags.contains(.shift)
        let isCmd = event.modifierFlags.contains(.command)

        if isShift, let lastId = lastClickId {
            // Shift+click: range selection
            let range = getWordRange(from: lastId, to: wordId)
            project.selectWords(range)
        } else if isCmd {
            // Cmd+click: toggle word in/out of selection
            if project.selectedWordIds.contains(wordId) {
                var current = project.selectedWordIds
                current.remove(wordId)
                project.selectWords(Array(current))
            } else {
                project.addToSelection([wordId])
            }
        } else {
            // Normal click: single select
            project.selectWords([wordId])
        }

        lastClickId = wordId
        refreshAllWordAppearances()

        // Notify for seek-to-word
        onWordClicked?(word)

        return true
    }

    /// Handle mouse drag entering a word (for continuous range selection).
    func handleMouseDragged(wordId: String) {
        guard isDragging, let dragStartId, let project else { return }
        let range = getWordRange(from: dragStartId, to: wordId)
        project.selectWords(range)
        refreshAllWordAppearances()
    }

    /// Handle mouse up (end drag).
    func handleMouseUp() {
        isDragging = false
    }

    // MARK: - Helpers

    private func getWordRange(from fromId: String, to toId: String) -> [String] {
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

    func refreshAllWordAppearances() {
        guard let project, let transcriptView else { return }
        for word in project.allWords {
            let isSelected = project.selectedWordIds.contains(word.id)
            transcriptView.updateWordAppearance(wordId: word.id, deleted: word.deleted, selected: isSelected)
        }
    }
}
