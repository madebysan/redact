import AppKit
import Testing
@testable import Redact

@Test @MainActor func transcriptionProgressDoesNotRenderPartialTranscript() {
    let view = TranscribeProgressView(frame: NSRect(x: 0, y: 0, width: 1_000, height: 700))

    view.updateProgress(
        TranscribeProgress(
            status: .transcribing,
            message: "876 words ready",
            completedTextPreview: "Raw model output should stay hidden.",
            completedWordCount: 876
        )
    )

    #expect(view.descendants(ofType: NSScrollView.self).isEmpty)
    #expect(view.descendants(ofType: NSTextView.self).isEmpty)
}

private extension NSView {
    func descendants<View: NSView>(ofType type: View.Type) -> [View] {
        subviews.flatMap { subview in
            let matchingSubview = (subview as? View).map { [$0] } ?? []
            return matchingSubview + subview.descendants(ofType: type)
        }
    }
}
