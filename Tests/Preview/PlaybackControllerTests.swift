import AVFoundation
import Foundation
import Testing
@testable import Redact

private actor PreviewBuildRecorder {
    private(set) var requests: [[TimeRange]] = []

    func record(_ keptRanges: [TimeRange]) {
        requests.append(keptRanges)
    }
}

private struct RecordingPreviewBuilder: PreviewCompositionBuilding {
    let recorder: PreviewBuildRecorder

    func build(sourceURL: URL, keptRanges: [TimeRange]) async throws -> PreparedPreview {
        await recorder.record(keptRanges)
        return PreparedPreview(asset: AVMutableComposition())
    }
}

private actor SuspendedPreviewBuild {
    private(set) var didStart = false
    private var continuation: CheckedContinuation<Void, Never>?

    func waitUntilReleased() async {
        didStart = true
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private struct SuspendedPreviewBuilder: PreviewCompositionBuilding {
    let build: SuspendedPreviewBuild

    func build(sourceURL: URL, keptRanges: [TimeRange]) async throws -> PreparedPreview {
        await build.waitUntilReleased()
        return PreparedPreview(asset: AVMutableComposition())
    }
}

@Test @MainActor func playbackControllerDebouncesRapidPreviewRebuilds() async throws {
    let recorder = PreviewBuildRecorder()
    let controller = PlaybackController(
        compositionBuilder: RecordingPreviewBuilder(recorder: recorder),
        debounceNanoseconds: 20_000_000
    )
    defer { controller.close() }
    let sourceURL = URL(fileURLWithPath: "/preview-source.mov")
    let transcript = makePreviewTranscript()
    let initialPlan = RenderPlan(
        transcript: transcript,
        edits: EditDecisionList(),
        policy: .mediaV1
    )
    let firstPlan = RenderPlan(
        transcript: transcript,
        edits: EditDecisionList(deletedWordIDs: ["silence"]),
        policy: .mediaV1
    )
    let secondPlan = RenderPlan(
        transcript: transcript,
        edits: EditDecisionList(deletedWordIDs: ["last"]),
        policy: .mediaV1
    )

    controller.loadMedia(url: sourceURL, words: [], renderPlan: initialPlan)
    controller.updateEditState(words: [], renderPlan: firstPlan)
    controller.updateEditState(words: [], renderPlan: secondPlan)

    let requests = try await waitForPreviewRequests(recorder)
    #expect(requests == [secondPlan.keptRanges])
}

@Test @MainActor func playbackControllerMapsEditedPlaybackBackToSourceTime() async throws {
    let recorder = PreviewBuildRecorder()
    let controller = PlaybackController(
        compositionBuilder: RecordingPreviewBuilder(recorder: recorder),
        debounceNanoseconds: 0
    )
    defer { controller.close() }
    let transcript = makePreviewTranscript()
    let plan = RenderPlan(
        transcript: transcript,
        edits: EditDecisionList(deletedWordIDs: ["silence"]),
        policy: .mediaV1
    )
    var positions: [PlaybackPosition] = []
    controller.onPositionUpdate = { positions.append($0) }

    let installedMap = await withCheckedContinuation { continuation in
        controller.onPreviewInstalled = { timelineMap in
            controller.onPreviewInstalled = nil
            continuation.resume(returning: timelineMap)
        }
        controller.loadMedia(
            url: URL(fileURLWithPath: "/preview-source.mov"),
            words: [],
            renderPlan: plan
        )
    }
    #expect(installedMap == plan.timelineMap)
    controller.seekToSourceTime(2.5)

    let position = try #require(positions.last)
    #expect(position.sourceTime == 2.5)
    #expect(position.editedTime == 1.5)
    #expect(position.editedDuration == 3)
}

@Test @MainActor func playbackWaitsForEditedPreviewBeforeHonoringPlay() async throws {
    let suspendedBuild = SuspendedPreviewBuild()
    let controller = PlaybackController(
        compositionBuilder: SuspendedPreviewBuilder(build: suspendedBuild),
        debounceNanoseconds: 0
    )
    defer { controller.close() }
    let transcript = makePreviewTranscript()
    let initialPlan = RenderPlan(
        transcript: transcript,
        edits: EditDecisionList(),
        policy: .mediaV1
    )
    let editedPlan = RenderPlan(
        transcript: transcript,
        edits: EditDecisionList(deletedWordIDs: ["silence"]),
        policy: .mediaV1
    )

    await withCheckedContinuation { continuation in
        controller.onPreviewInstalled = { _ in
            controller.onPreviewInstalled = nil
            continuation.resume()
        }
        controller.loadMedia(
            url: URL(fileURLWithPath: "/preview-source.mov"),
            words: [],
            renderPlan: initialPlan
        )
    }

    var playingStates: [Bool] = []
    var installedMaps: [TimelineMap] = []
    controller.onPlayingChanged = { playingStates.append($0) }
    controller.onPreviewInstalled = { installedMaps.append($0) }

    controller.updateEditState(words: [], renderPlan: editedPlan)
    controller.togglePlayPause()

    for _ in 0..<50 where !(await suspendedBuild.didStart) {
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    #expect(await suspendedBuild.didStart)
    #expect(!playingStates.contains(true))
    #expect(installedMaps.isEmpty)

    await suspendedBuild.release()
    for _ in 0..<50 where installedMaps.isEmpty {
        try await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(installedMaps == [editedPlan.timelineMap])
    #expect(playingStates.last == true)
}

private func makePreviewTranscript() -> SourceTranscript {
    SourceTranscript(
        words: [
            TranscriptWord(
                id: "first",
                text: "First",
                start: 0,
                end: 1,
                confidence: 1,
                isSilence: false
            ),
            TranscriptWord(
                id: "silence",
                text: "—",
                start: 1,
                end: 2,
                confidence: 1,
                isSilence: true
            ),
            TranscriptWord(
                id: "last",
                text: "Last",
                start: 2,
                end: 4,
                confidence: 1,
                isSilence: false
            ),
        ],
        language: "en",
        duration: 4
    )
}

private func waitForPreviewRequests(
    _ recorder: PreviewBuildRecorder,
    attempts: Int = 50
) async throws -> [[TimeRange]] {
    for _ in 0..<attempts {
        let requests = await recorder.requests
        if !requests.isEmpty {
            return requests
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    return await recorder.requests
}
