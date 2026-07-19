import Foundation

struct TranscriptWord: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let text: String
    let start: Double
    let end: Double
    let confidence: Double
    let isSilence: Bool
}

struct SourceTranscript: Codable, Equatable, Sendable {
    let words: [TranscriptWord]
    let language: String
    let duration: Double

    init(words: [TranscriptWord], language: String, duration: Double) {
        self.words = words
        self.language = language
        self.duration = duration
    }

    init(v1Words: [Word], language: String, duration: Double) {
        self.init(
            words: v1Words.map {
                TranscriptWord(
                    id: $0.id,
                    text: $0.word,
                    start: $0.start,
                    end: $0.end,
                    confidence: $0.confidence,
                    isSilence: $0.isActualSilence
                )
            },
            language: language,
            duration: duration
        )
    }

    func correctingWordText(wordID: String, text: String) -> SourceTranscript? {
        guard let index = words.firstIndex(where: { $0.id == wordID }) else { return nil }
        var correctedWords = words
        let word = correctedWords[index]
        correctedWords[index] = TranscriptWord(
            id: word.id,
            text: text,
            start: word.start,
            end: word.end,
            confidence: word.confidence,
            isSilence: word.isSilence
        )
        return SourceTranscript(words: correctedWords, language: language, duration: duration)
    }
}
