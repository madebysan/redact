import AppKit
import Testing
@testable import Redact

@Test @MainActor func errorBannerSkipsTransitionsWhenReduceMotionIsEnabled() {
    let banner = ErrorBannerView(
        frame: NSRect(x: 0, y: 0, width: 500, height: 36),
        reduceMotionProvider: { true }
    )
    var didDismiss = false
    banner.onDismiss = { didDismiss = true }

    banner.show(message: "Export failed")

    #expect(!banner.isHidden)
    #expect(banner.alphaValue == 1)

    banner.dismiss()

    #expect(banner.isHidden)
    #expect(banner.alphaValue == 0)
    #expect(didDismiss)
}
