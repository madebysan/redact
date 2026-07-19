import AVFoundation
import AppKit
import Testing
@testable import Redact

@Test @MainActor func videoPreviewMakesFullScreenDiscoverableWhenMediaIsLoaded() throws {
    let view = VideoPreviewView(frame: NSRect(x: 0, y: 0, width: 640, height: 360))
    let button = try #require(
        view.subviews.compactMap { $0 as? NSButton }
            .first { $0.accessibilityLabel() == "Enter full screen preview" }
    )
    #expect(button.isHidden)

    view.player = AVPlayer()

    #expect(!button.isHidden)
    #expect(button.toolTip == "Enter full screen preview")
}
