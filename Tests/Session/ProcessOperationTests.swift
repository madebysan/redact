import Foundation
import Testing
@testable import Redact

@Test func processOperationsHaveIndependentCancellationState() {
    let first = ProcessOperation()
    let second = ProcessOperation()

    first.cancel()

    #expect(first.isCancelled)
    #expect(!second.isCancelled)
}

@Test func cancelledProcessOperationRejectsAProcessBeforeLaunch() throws {
    let operation = ProcessOperation()
    operation.cancel()

    let launched = try operation.launch(Process())

    #expect(!launched)
}
