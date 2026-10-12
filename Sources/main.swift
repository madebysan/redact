import AppKit

MainActor.assumeIsolated {
    let app = RedactApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
