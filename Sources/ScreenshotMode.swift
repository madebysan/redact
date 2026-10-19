#if DEBUG
import AppKit

/// Debug-only staging for README screenshots (scripts/readme-screenshots.sh).
///
/// Launch with `-RedactScreenshotState editing|cleanup|agent` and the environment
/// variables `REDACT_SCREENSHOT_MEDIA` (the demo clip) and `REDACT_SCREENSHOT_READY`
/// (a file written once the state is on screen). Redact then opens the clip in a
/// 1280 x 800 window, applies a fixed set of demo edits, opens the requested sheet,
/// and writes the ready file. Overrides arrive as launch arguments, which macOS does
/// not store, so screenshot runs never read or change saved settings. Release
/// builds do not compile this file.
@MainActor
final class ScreenshotMode {
    enum State: String {
        case editing, cleanup, agent
    }

    static let shared: ScreenshotMode? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let flag = arguments.firstIndex(of: "-RedactScreenshotState"),
              arguments.indices.contains(flag + 1),
              let state = State(rawValue: arguments[flag + 1]),
              let media = ProcessInfo.processInfo.environment["REDACT_SCREENSHOT_MEDIA"] else {
            return nil
        }
        return ScreenshotMode(
            state: state,
            media: URL(fileURLWithPath: media),
            ready: ProcessInfo.processInfo.environment["REDACT_SCREENSHOT_READY"].map(URL.init(fileURLWithPath:))
        )
    }()

    static let contentSize = NSSize(width: 1_280, height: 800)

    let state: State
    private let media: URL
    private let ready: URL?
    private var didStage = false

    private init(state: State, media: URL, ready: URL?) {
        self.state = state
        self.media = media
        self.ready = ready
    }

    func begin(with controller: MainWindowController) {
        if let window = controller.window {
            window.setContentSize(Self.contentSize)
            window.center()
        }
        controller.handleImportedFile(media)
    }

    func editorDidLoad(_ controller: MainWindowController) {
        guard !didStage else { return }
        didStage = true
        // Let the preview composition and waveform settle before staging.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            controller.stageScreenshotDemo(self.state)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.markReady()
            }
        }
    }

    private func markReady() {
        guard let ready else { return }
        try? Data(state.rawValue.utf8).write(to: ready)
    }
}
#endif
