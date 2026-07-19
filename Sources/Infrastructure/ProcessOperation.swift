import Foundation

final class ProcessOperation: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    @discardableResult
    func launch(_ process: Process) throws -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !cancelled else { return false }
        self.process = process

        do {
            try process.run()
            return true
        } catch {
            self.process = nil
            throw error
        }
    }

    func clear(_ completedProcess: Process) {
        lock.lock()
        defer { lock.unlock() }

        if process === completedProcess {
            process = nil
        }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let runningProcess = process
        process = nil
        lock.unlock()

        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }
}
