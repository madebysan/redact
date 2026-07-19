import Foundation

enum TranscriptCleanupKind: String, CaseIterable, Hashable {
    case fillerWords
    case repeatedWords
    case longPauses
    case namedTerms
    case semanticCuts

    var title: String {
        switch self {
        case .fillerWords: "Filler words"
        case .repeatedWords: "Repeated words"
        case .longPauses: "Long pauses"
        case .namedTerms: "Named terms"
        case .semanticCuts: "Semantic cuts"
        }
    }

    var rowTitle: String {
        switch self {
        case .fillerWords: "Filler"
        case .repeatedWords: "Repeat"
        case .longPauses: "Pause"
        case .namedTerms: "Named term"
        case .semanticCuts: "Semantic cut"
        }
    }
}

enum TranscriptEditRequirement: String, Equatable {
    case required
    case optional

    var title: String {
        switch self {
        case .required: "Required"
        case .optional: "Optional"
        }
    }
}

struct TranscriptCleanupSuggestion: Identifiable, Equatable {
    let id: String
    let kind: TranscriptCleanupKind
    let wordIDs: [String]
    let changeDescription: String
    let context: String
    let startTime: Double
    let removedDuration: Double
    let requirement: TranscriptEditRequirement
    let validationMessage: String?

    init(
        id: String,
        kind: TranscriptCleanupKind,
        wordIDs: [String],
        changeDescription: String,
        context: String,
        startTime: Double,
        removedDuration: Double,
        requirement: TranscriptEditRequirement = .optional,
        validationMessage: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.wordIDs = wordIDs
        self.changeDescription = changeDescription
        self.context = context
        self.startTime = startTime
        self.removedDuration = removedDuration
        self.requirement = requirement
        self.validationMessage = validationMessage
    }

    var isSelectable: Bool {
        validationMessage == nil
    }
}

enum TranscriptCleanupAnalyzer {
    private static let singleFillers: Set<String> = [
        "ah", "eh", "er", "erm", "hm", "hmm", "mm", "uh", "uhh", "uhm", "um", "umm",
    ]

    private static let fillerPhrases: [[String]] = [
        ["you", "know"],
        ["i", "mean"],
    ]

    static func suggestions(for words: [Word]) -> [TranscriptCleanupSuggestion] {
        var claimedWordIDs = Set<String>()
        var results: [TranscriptCleanupSuggestion] = []
        let normalizedTokens = words.map { normalizedToken($0.word) }

        let phraseSuggestions = fillerPhraseSuggestions(
            for: words,
            normalizedTokens: normalizedTokens,
            claimedWordIDs: &claimedWordIDs
        )
        results.append(contentsOf: phraseSuggestions)

        let singleSuggestions = singleFillerSuggestions(
            for: words,
            normalizedTokens: normalizedTokens,
            claimedWordIDs: &claimedWordIDs
        )
        results.append(contentsOf: singleSuggestions)

        results.append(
            contentsOf: repeatedWordSuggestions(
                for: words,
                normalizedTokens: normalizedTokens,
                claimedWordIDs: &claimedWordIDs
            )
        )
        results.append(contentsOf: longPauseSuggestions(for: words))

        return results.sorted { first, second in
            if first.startTime == second.startTime {
                return first.kind.rawValue < second.kind.rawValue
            }
            return first.startTime < second.startTime
        }
    }

    private static func fillerPhraseSuggestions(
        for words: [Word],
        normalizedTokens: [String],
        claimedWordIDs: inout Set<String>
    ) -> [TranscriptCleanupSuggestion] {
        var suggestions: [TranscriptCleanupSuggestion] = []
        var index = 0

        while index < words.count {
            var match: (phrase: [String], words: ArraySlice<Word>)?
            for phrase in fillerPhrases {
                let endIndex = index + phrase.count
                guard endIndex <= words.count else { continue }
                let candidates = words[index..<endIndex]
                guard candidates.allSatisfy({ !$0.deleted && !$0.isActualSilence }),
                      phrase.indices.allSatisfy({
                          normalizedTokens[index + $0] == phrase[$0]
                      }),
                      candidates.allSatisfy({ !claimedWordIDs.contains($0.id) }) else {
                    continue
                }
                match = (phrase, candidates)
                break
            }

            guard let match else {
                index += 1
                continue
            }

            let matchedWords = Array(match.words)
            let detectedText = matchedWords.map { displayText($0.word) }.joined(separator: " ")
            let wordIDs = matchedWords.map(\.id)
            claimedWordIDs.formUnion(wordIDs)
            suggestions.append(
                makeSuggestion(
                    kind: .fillerWords,
                    words: matchedWords,
                    wordIDs: wordIDs,
                    changeDescription: "Remove “\(detectedText)”",
                    allWords: words,
                    range: index..<(index + matchedWords.count)
                )
            )
            index += matchedWords.count
        }

        return suggestions
    }

    private static func singleFillerSuggestions(
        for words: [Word],
        normalizedTokens: [String],
        claimedWordIDs: inout Set<String>
    ) -> [TranscriptCleanupSuggestion] {
        words.enumerated().compactMap { index, word in
            guard !word.deleted,
                  !word.isActualSilence,
                  !claimedWordIDs.contains(word.id),
                  singleFillers.contains(normalizedTokens[index]) else {
                return nil
            }
            claimedWordIDs.insert(word.id)
            return makeSuggestion(
                kind: .fillerWords,
                words: [word],
                wordIDs: [word.id],
                changeDescription: "Remove “\(displayText(word.word))”",
                allWords: words,
                range: index..<(index + 1)
            )
        }
    }

    private static func repeatedWordSuggestions(
        for words: [Word],
        normalizedTokens: [String],
        claimedWordIDs: inout Set<String>
    ) -> [TranscriptCleanupSuggestion] {
        var suggestions: [TranscriptCleanupSuggestion] = []
        var index = 0

        while index < words.count {
            let first = words[index]
            let token = normalizedTokens[index]
            guard !first.deleted, !first.isActualSilence, !token.isEmpty else {
                index += 1
                continue
            }

            var runEnd = index + 1
            while runEnd < words.count {
                let candidate = words[runEnd]
                guard !candidate.deleted,
                      !candidate.isActualSilence,
                      normalizedTokens[runEnd] == token else {
                    break
                }
                runEnd += 1
            }

            guard runEnd - index > 1 else {
                index += 1
                continue
            }

            let repeatedWords = Array(words[index..<runEnd])
            let deletions = repeatedWords.dropLast().filter {
                !claimedWordIDs.contains($0.id)
            }
            let wordIDs = deletions.map(\.id)
            if !wordIDs.isEmpty {
                claimedWordIDs.formUnion(wordIDs)
                suggestions.append(
                    makeSuggestion(
                        kind: .repeatedWords,
                        words: Array(deletions),
                        wordIDs: wordIDs,
                        changeDescription: "Keep one “\(displayText(repeatedWords.last?.word ?? first.word))”",
                        allWords: words,
                        range: index..<runEnd
                    )
                )
            }
            index = runEnd
        }

        return suggestions
    }

    private static func longPauseSuggestions(
        for words: [Word]
    ) -> [TranscriptCleanupSuggestion] {
        var suggestions: [TranscriptCleanupSuggestion] = []
        var index = 0

        while index < words.count {
            guard words[index].isActualSilence, !words[index].deleted else {
                index += 1
                continue
            }

            var runEnd = index + 1
            while runEnd < words.count,
                  words[runEnd].isActualSilence,
                  !words[runEnd].deleted {
                runEnd += 1
            }

            let pauseWords = Array(words[index..<runEnd])
            guard pauseWords.count > 1, let preservedWord = pauseWords.last else {
                index = runEnd
                continue
            }

            let deletions = Array(pauseWords.dropLast())
            let originalDuration = pauseWords.reduce(0) { $0 + wordDuration($1) }
            let remainingDuration = wordDuration(preservedWord)
            suggestions.append(
                makeSuggestion(
                    kind: .longPauses,
                    words: deletions,
                    wordIDs: deletions.map(\.id),
                    changeDescription: String(
                        format: "Shorten %.1fs pause to %.1fs",
                        originalDuration,
                        remainingDuration
                    ),
                    allWords: words,
                    range: index..<runEnd
                )
            )
            index = runEnd
        }

        return suggestions
    }

    private static func makeSuggestion(
        kind: TranscriptCleanupKind,
        words: [Word],
        wordIDs: [String],
        changeDescription: String,
        allWords: [Word],
        range: Range<Int>
    ) -> TranscriptCleanupSuggestion {
        TranscriptCleanupSuggestion(
            id: kind.rawValue + ":" + wordIDs.joined(separator: ","),
            kind: kind,
            wordIDs: wordIDs,
            changeDescription: changeDescription,
            context: context(in: allWords, around: range),
            startTime: words.first?.start ?? allWords[range.lowerBound].start,
            removedDuration: words.reduce(0) { $0 + wordDuration($1) }
        )
    }

    private static func context(in words: [Word], around range: Range<Int>) -> String {
        var prefix: [String] = []
        var prefixIndex = range.lowerBound - 1
        while prefixIndex >= 0, prefix.count < 3 {
            let word = words[prefixIndex]
            if !word.deleted, !word.isActualSilence {
                prefix.append(displayText(word.word))
            }
            prefixIndex -= 1
        }
        prefix.reverse()

        let detected = words[range]
            .filter { !$0.isActualSilence }
            .map { displayText($0.word) }
        var suffix: [String] = []
        var suffixIndex = range.upperBound
        while suffixIndex < words.count, suffix.count < 3 {
            let word = words[suffixIndex]
            if !word.deleted, !word.isActualSilence {
                suffix.append(displayText(word.word))
            }
            suffixIndex += 1
        }
        let parts = [
            prefix.isEmpty ? nil : "… " + prefix.joined(separator: " "),
            detected.isEmpty ? "[pause]" : "[" + detected.joined(separator: " ") + "]",
            suffix.isEmpty ? nil : suffix.joined(separator: " ") + " …",
        ].compactMap { $0 }
        return parts.joined(separator: " ")
    }

    private static func normalizedToken(_ text: String) -> String {
        text.lowercased().filter { character in
            character.isLetter || character.isNumber || character == "'"
        }
    }

    private static func displayText(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func wordDuration(_ word: Word) -> Double {
        max(0, word.end - word.start)
    }
}
