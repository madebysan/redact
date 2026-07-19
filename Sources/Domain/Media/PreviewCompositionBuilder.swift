import AVFoundation
import Foundation

enum PreviewCompositionError: LocalizedError, Equatable {
    case noMediaTracks
    case couldNotCreateTrack

    var errorDescription: String? {
        switch self {
        case .noMediaTracks:
            return "The selected file has no audio or video track for preview."
        case .couldNotCreateTrack:
            return "Redact could not create the edited preview track."
        }
    }
}

/// The builder stops mutating the composition before this value crosses back to MainActor.
/// AVAsset does not declare Sendable, so this wrapper records that ownership boundary.
struct PreparedPreview: @unchecked Sendable {
    let asset: AVAsset
}

protocol PreviewCompositionBuilding: Sendable {
    func build(sourceURL: URL, keptRanges: [TimeRange]) async throws -> PreparedPreview
}

struct AVPreviewCompositionBuilder: PreviewCompositionBuilding, Sendable {
    func build(sourceURL: URL, keptRanges: [TimeRange]) async throws -> PreparedPreview {
        try Task.checkCancellation()
        let sourceAsset = AVURLAsset(url: sourceURL)
        let sourceDuration: CMTime
        let tracks: [AVAssetTrack]

        do {
            sourceDuration = try await sourceAsset.load(.duration)
            let videoTracks = try await sourceAsset.loadTracks(withMediaType: .video)
            let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
            tracks = videoTracks + audioTracks
        } catch {
            throw PreviewCompositionError.noMediaTracks
        }

        guard sourceDuration.isNumeric,
              sourceDuration.seconds.isFinite,
              sourceDuration.seconds > 0,
              !tracks.isEmpty else {
            throw PreviewCompositionError.noMediaTracks
        }

        let composition = AVMutableComposition()
        for sourceTrack in tracks {
            try Task.checkCancellation()
            let trackTimeRange = try await sourceTrack.load(.timeRange)
            guard let compositionTrack = composition.addMutableTrack(
                withMediaType: sourceTrack.mediaType,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                throw PreviewCompositionError.couldNotCreateTrack
            }

            if sourceTrack.mediaType == .video {
                compositionTrack.preferredTransform = try await sourceTrack.load(.preferredTransform)
            }

            var editedCursor = CMTime.zero
            for range in keptRanges {
                try Task.checkCancellation()
                let keptTimeRange = clampedTimeRange(
                    range,
                    sourceDuration: sourceDuration
                )
                guard keptTimeRange.duration > .zero else { continue }
                let sourceRange = CMTimeRangeGetIntersection(
                    keptTimeRange,
                    otherRange: trackTimeRange
                )
                guard sourceRange.isValid, !sourceRange.isEmpty else {
                    editedCursor = CMTimeAdd(editedCursor, keptTimeRange.duration)
                    continue
                }
                let trackOffset = CMTimeSubtract(
                    sourceRange.start,
                    keptTimeRange.start
                )
                try compositionTrack.insertTimeRange(
                    sourceRange,
                    of: sourceTrack,
                    at: CMTimeAdd(editedCursor, trackOffset)
                )
                editedCursor = CMTimeAdd(editedCursor, keptTimeRange.duration)
            }
        }

        return PreparedPreview(asset: composition)
    }

    private func clampedTimeRange(
        _ range: TimeRange,
        sourceDuration: CMTime
    ) -> CMTimeRange {
        let durationSeconds = max(0, sourceDuration.seconds)
        let start = max(0, min(range.start, durationSeconds))
        let end = max(start, min(range.end, durationSeconds))
        let timeScale = sourceDuration.timescale > 0 ? sourceDuration.timescale : 600
        return CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: timeScale),
            duration: CMTime(seconds: end - start, preferredTimescale: timeScale)
        )
    }
}
