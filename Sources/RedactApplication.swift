import AppKit

/// Every way of quitting (the Quit command, logout, Sparkle's install and
/// relaunch) goes through terminate(_:). AppKit cancels it silently while a
/// sheet is attached to a document window, so the welcome walkthrough is
/// closed first; it holds no work.
final class RedactApplication: NSApplication {
    override func terminate(_ sender: Any?) {
        (delegate as? AppDelegate)?.closeWelcomeWalkthrough()
        super.terminate(sender)
    }
}
