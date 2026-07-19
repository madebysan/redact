import AVFoundation
import Foundation

struct PlaybackPosition: Equatable, Sendable {
    let sourceTime: Double
    let editedTime: Double
    let editedDuration: Double
}

/// Owns edited preview playback and maps its compact timeline back to source words.
@MainActor
final class PlaybackController {
    let player = AVPlayer()

    var onPositionUpdate: ((PlaybackPosition) -> Void)?
    var onHighlightWord: ((String?) -> Void)?
    var onPlayingChanged: ((Bool) -> Void)?
    var onPreviewError: ((String) -> Void)?
    var onPreviewInstalled: ((TimelineMap) -> Void)?

    private let compositionBuilder: any PreviewCompositionBuilding
    private let debounceNanoseconds: UInt64
    private var timeObserverToken: Any?
    private var previewBuildTask: Task<Void, Never>?
    private var previewGeneration = UUID()
    private var sourceURL: URL?
    private var allWords: [Word] = []
    private var activeTimelineMap = TimelineMap(keptRanges: [])
    private var preferredRate: Float = 1
    private var isPreviewUpdating = false
    private var playWhenPreviewInstalls = false

    init(
        compositionBuilder: any PreviewCompositionBuilding = AVPreviewCompositionBuilder(),
        debounceNanoseconds: UInt64 = 150_000_000
    ) {
        self.compositionBuilder = compositionBuilder
        self.debounceNanoseconds = debounceNanoseconds
        setupPeriodicObserver()
    }

    deinit {
        previewBuildTask?.cancel()
        if let timeObserverToken {
            player.removeTimeObserver(timeObserverToken)
        }
    }

    // MARK: - Project lifecycle

    func loadMedia(url: URL, words: [Word], renderPlan: RenderPlan) {
        sourceURL = url
        allWords = words
        schedulePreview(renderPlan: renderPlan, debounce: false)
    }

    func updateEditState(words: [Word], renderPlan: RenderPlan) {
        allWords = words
        schedulePreview(renderPlan: renderPlan, debounce: true)
    }

    func close() {
        previewBuildTask?.cancel()
        previewBuildTask = nil
        previewGeneration = UUID()
        sourceURL = nil
        allWords = []
        activeTimelineMap = TimelineMap(keptRanges: [])
        isPreviewUpdating = false
        playWhenPreviewInstalls = false
        player.pause()
        player.replaceCurrentItem(with: nil)
        onPositionUpdate = nil
        onHighlightWord = nil
        onPlayingChanged = nil
        onPreviewError = nil
        onPreviewInstalled = nil
    }

    // MARK: - Transport

    func togglePlayPause() {
        if isPreviewUpdating {
            playWhenPreviewInstalls.toggle()
            return
        }
        if player.timeControlStatus == .playing {
            player.pause()
            onPlayingChanged?(false)
        } else {
            player.playImmediately(atRate: preferredRate)
            onPlayingChanged?(true)
        }
    }

    func seekToSourceTime(_ sourceTime: Double) {
        seekToEditedTime(activeTimelineMap.editedTime(forSourceTime: sourceTime))
    }

    func seekToEditedTime(_ editedTime: Double) {
        let clampedTime = max(0, min(activeTimelineMap.editedDuration, editedTime))
        let time = CMTime(seconds: clampedTime, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        publishPosition(editedTime: clampedTime)
    }

    func skip(seconds: Double) {
        let current = player.currentTime().seconds
        guard current.isFinite else { return }
        seekToEditedTime(current + seconds)
    }

    func setRate(_ rate: Float) {
        preferredRate = rate
        if player.timeControlStatus == .playing {
            player.rate = rate
        }
    }

    func setVolume(_ volume: Float) {
        player.volume = min(1, max(0, volume))
    }

    func setMuted(_ muted: Bool) {
        player.isMuted = muted
    }

    func toggleMuted() -> Bool {
        player.isMuted.toggle()
        return player.isMuted
    }

    // MARK: - Composition rebuild

    private func schedulePreview(renderPlan: RenderPlan, debounce: Bool) {
        previewBuildTask?.cancel()
        let generation = UUID()
        previewGeneration = generation
        guard let sourceURL else { return }

        if player.rate != 0 || player.timeControlStatus == .playing {
            playWhenPreviewInstalls = true
            player.pause()
            onPlayingChanged?(false)
        }
        isPreviewUpdating = true

        let builder = compositionBuilder
        let delay = debounce ? debounceNanoseconds : 0
        previewBuildTask = Task { [weak self] in
            do {
                if delay > 0 {
                    try await Task.sleep(nanoseconds: delay)
                }
                try Task.checkCancellation()

                if renderPlan.keptRanges.isEmpty {
                    self?.installPreview(
                        item: nil,
                        renderPlan: renderPlan,
                        generation: generation
                    )
                    return
                }

                if renderPlan.deletedRanges.isEmpty {
                    self?.installPreview(
                        item: AVPlayerItem(url: sourceURL),
                        renderPlan: renderPlan,
                        generation: generation
                    )
                    return
                }

                let prepared = try await builder.build(
                    sourceURL: sourceURL,
                    keptRanges: renderPlan.keptRanges
                )
                try Task.checkCancellation()
                self?.installPreview(
                    item: AVPlayerItem(asset: prepared.asset),
                    renderPlan: renderPlan,
                    generation: generation
                )
            } catch is CancellationError {
                return
            } catch {
                guard self?.previewGeneration == generation else { return }
                self?.isPreviewUpdating = false
                self?.playWhenPreviewInstalls = false
                self?.onPlayingChanged?(false)
                self?.onPreviewError?(error.localizedDescription)
            }
        }
    }

    private func installPreview(
        item: AVPlayerItem?,
        renderPlan: RenderPlan,
        generation: UUID
    ) {
        guard previewGeneration == generation else { return }

        let currentEditedTime = player.currentTime().seconds
        let sourceTime = currentEditedTime.isFinite
            ? activeTimelineMap.sourceTime(forEditedTime: currentEditedTime)
            : 0
        let shouldPlay = playWhenPreviewInstalls
            || player.rate != 0
            || player.timeControlStatus == .playing

        player.pause()
        player.replaceCurrentItem(with: item)
        activeTimelineMap = renderPlan.timelineMap
        isPreviewUpdating = false
        playWhenPreviewInstalls = false

        let newEditedTime = activeTimelineMap.editedTime(forSourceTime: sourceTime)
        let target = CMTime(seconds: newEditedTime, preferredTimescale: 600)
        player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)

        if shouldPlay, item != nil {
            player.playImmediately(atRate: preferredRate)
        }
        onPlayingChanged?(shouldPlay && item != nil)
        onPreviewInstalled?(activeTimelineMap)
        publishPosition(editedTime: newEditedTime)
    }

    // MARK: - Periodic updates

    private func setupPeriodicObserver() {
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
            }
        }
    }

    private func tick() {
        guard player.timeControlStatus == .playing else { return }
        let editedTime = player.currentTime().seconds
        guard editedTime.isFinite else { return }
        publishPosition(editedTime: editedTime)
    }

    private func publishPosition(editedTime: Double) {
        let sourceTime = activeTimelineMap.sourceTime(forEditedTime: editedTime)
        onPositionUpdate?(
            PlaybackPosition(
                sourceTime: sourceTime,
                editedTime: editedTime,
                editedDuration: activeTimelineMap.editedDuration
            )
        )

        let highlightedWord = findWordAtTime(allWords, time: sourceTime)
        if let highlightedWord,
           !highlightedWord.deleted,
           !highlightedWord.isActualSilence {
            onHighlightWord?(highlightedWord.id)
        } else {
            onHighlightWord?(nil)
        }
    }
}
