import AVFoundation
import AppKit
import QuartzCore

/// Manages AVPlayer playback. Uses AVPlayer's own periodic time observer for the
/// 30Hz "skip deleted ranges + fade audio + highlight current word" loop, so we
/// don't need to babysit a CVDisplayLink.
class PlaybackController {
    let player = AVPlayer()

    var onTimeUpdate: ((Double) -> Void)?
    var onHighlightWord: ((String?) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?

    private var timeObserverToken: Any?
    private var isSeeking = false
    private var fadeInStart: CFTimeInterval = 0
    private var allWords: [Word] = []
    private var deletedRanges: [TimeRange] = []

    private var fadeSec: Double { Settings.shared.crossfadeSec }

    init() {
        setupPeriodicObserver()
    }

    deinit {
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
    }

    // MARK: - Public API

    func loadMedia(url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
    }

    func updateWords(_ words: [Word]) {
        allWords = words
        deletedRanges = buildDeletedRanges(words)
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
            onPlayingChanged?(false)
        } else {
            player.play()
            onPlayingChanged?(true)
        }
    }

    func seekToWord(start: Double) {
        let time = CMTime(seconds: start, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        onTimeUpdate?(start)
    }

    func skip(seconds: Double) {
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite else { return }
        let current = player.currentTime().seconds
        let target = max(0, min(duration, current + seconds))
        let time = CMTime(seconds: target, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ rate: Float) {
        player.rate = rate
    }

    // MARK: - Observer

    private func setupPeriodicObserver() {
        // 30Hz is plenty for the skip-over-deleted-range check and visibly smooth
        // for cursor movement. Observer only fires during playback, after seeks,
        // and on rate changes — no work wasted while paused.
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard player.timeControlStatus == .playing, !isSeeking else { return }

        let time = player.currentTime().seconds
        guard time.isFinite else { return }

        // Inside a deleted range → mute and skip past.
        if let deletedRange = findDeletedRange(time: time, deletedRanges: deletedRanges) {
            player.volume = 0
            isSeeking = true
            let target = CMTime(seconds: deletedRange.end + 0.01, preferredTimescale: 600)
            player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
                guard let self, finished else { return }
                DispatchQueue.main.async {
                    self.isSeeking = false
                    self.player.volume = 0
                    self.fadeInStart = CACurrentMediaTime()
                }
            }
            return
        }

        onTimeUpdate?(time)

        // Fade-in after a skip.
        if fadeInStart > 0 {
            let elapsed = CACurrentMediaTime() - fadeInStart
            if elapsed < fadeSec {
                player.volume = Float(elapsed / fadeSec)
            } else {
                player.volume = 1
                fadeInStart = 0
            }
        }

        // Fade-out approaching next deleted range.
        if fadeInStart == 0 {
            if let nextStart = findNextDeletedStart(time: time, deletedRanges: deletedRanges) {
                let dist = nextStart - time
                if dist < fadeSec && dist > 0 {
                    player.volume = Float(dist / fadeSec)
                } else if dist >= fadeSec {
                    player.volume = 1
                }
            }
        }

        if let word = findWordAtTime(allWords, time: time), !word.deleted, !word.isActualSilence {
            onHighlightWord?(word.id)
        }
    }
}
