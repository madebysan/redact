import Foundation

enum EditDecision: Codable, Equatable, Sendable {
    case delete(wordIDs: Set<String>)
    case restore(wordIDs: Set<String>)
}

struct EditDecisionList: Codable, Equatable, Sendable {
    private(set) var deletedWordIDs: Set<String>

    init(deletedWordIDs: Set<String> = []) {
        self.deletedWordIDs = deletedWordIDs
    }

    init(v1Words: [Word]) {
        deletedWordIDs = Set(v1Words.lazy.filter(\.deleted).map(\.id))
    }

    func applying(_ decision: EditDecision) -> EditDecisionList {
        var nextDeletedWordIDs = deletedWordIDs

        switch decision {
        case .delete(let wordIDs):
            nextDeletedWordIDs.formUnion(wordIDs)
        case .restore(let wordIDs):
            nextDeletedWordIDs.subtract(wordIDs)
        }

        return EditDecisionList(deletedWordIDs: nextDeletedWordIDs)
    }

    func contains(wordID: String) -> Bool {
        deletedWordIDs.contains(wordID)
    }
}
