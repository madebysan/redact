import Foundation
@testable import Redact

func makeSyntheticWords(count: Int) -> [Word] {
    (0..<count).map { index in
        let start = Double(index) * 0.22
        return Word(
            id: "synthetic_\(index)",
            word: index.isMultiple(of: 12) ? "sentence." : "word",
            start: start,
            end: start + 0.16,
            confidence: 0.95,
            deleted: index.isMultiple(of: 9),
            isSilence: index.isMultiple(of: 31)
        )
    }
}
