import AVFoundation
import AppKit
import QuartzCore

/// Manages AVPlayer playback, the 60fps display-link loop that skips deleted ranges,
/// and audio fade in/out at cut boundaries. Port of usePlaybackSync.ts.
class PlaybackController {
    let player = AVPlayer()

    var onTimeUpdate: ((Double) -> Void)?
    var onHighlightWord: ((String?) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?

    private var displayLink: CVDisplayLink?
    private var isSeeking = false
    private var fadeInStart: CFTimeInterval = 0
    private var allWords: [Word] = []
    private var deletedRanges: [TimeRange] = []

    private static let fadeSec: Double = 0.07

    init() {
        setupDisplayLink()
    }

    deinit {
        stopDisplayLink()
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

    // MARK: - Display Link

    private func setupDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        displayLink = link

        let callback: CVDisplayLinkOutputCallback = { _, _, _, _, _, userInfo -> CVReturn in
            guard let userInfo else { return kCVReturnSuccess }
            let controller = Unmanaged<PlaybackController>.fromOpaque(userInfo).takeUnretainedValue()
            DispatchQueue.main.async {
                controller.tick()
            }
            return kCVReturnSuccess
        }

        CVDisplayLinkSetOutputCallback(link, callback, Unmanaged.passUnretained(self).toOpaque())
        CVDisplayLinkStart(link)
    }

    private func stopDisplayLink() {
        if let link = displayLink {
            CVDisplayLinkStop(link)
        }
        displayLink = nil
    }

    private func tick() {
        guard player.timeControlStatus == .playing, !isSeeking else { return }

        let time = player.currentTime().seconds
        guard time.isFinite else { return }

        // Check if in a deleted range
        if let deletedRange = findDeletedRange(time: time, deletedRanges: deletedRanges) {
            // Mute and skip past
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

        // Fade-in after a skip
        if fadeInStart > 0 {
            let elapsed = CACurrentMediaTime() - fadeInStart
            if elapsed < Self.fadeSec {
                player.volume = Float(elapsed / Self.fadeSec)
            } else {
                player.volume = 1
                fadeInStart = 0
            }
        }

        // Fade-out approaching next deleted range
        if fadeInStart == 0 {
            if let nextStart = findNextDeletedStart(time: time, deletedRanges: deletedRanges) {
                let dist = nextStart - time
                if dist < Self.fadeSec && dist > 0 {
                    player.volume = Float(dist / Self.fadeSec)
                } else if dist >= Self.fadeSec {
                    player.volume = 1
                }
            }
        }

        // Highlight current word (skip silence and deleted tokens)
        if let word = findWordAtTime(allWords, time: time), !word.deleted, !word.isActualSilence {
            onHighlightWord?(word.id)
        }
    }
}
