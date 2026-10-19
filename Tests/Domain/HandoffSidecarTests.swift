import Foundation
import Testing
@testable import Redact

// MARK: - Fixtures

/// A deterministic transcript with `cuts` deleted runs: `2 * cuts + 1`
/// one-second words with every odd word removed, so the canonical plan has
/// exactly `cuts + 1` kept ranges, each well above one frame.
private func makeCutFixture(cuts: Int) -> (SourceTranscript, EditDecisionList, RenderPlan) {
    let wordCount = 2 * cuts + 1
    let words = (0..<wordCount).map { index in
        TranscriptWord(
            id: "w\(index)",
            text: index.isMultiple(of: 2) ? "keep" : "cut",
            start: Double(index),
            end: Double(index + 1),
            confidence: 1,
            isSilence: false
        )
    }
    let transcript = SourceTranscript(words: words, language: "en", duration: Double(wordCount))
    let deleted = words.filter { !Int($0.id.dropFirst())!.isMultiple(of: 2) }.map(\.id)
    let edits = EditDecisionList(deletedWordIDs: Set(deleted))
    let plan = RenderPlan(transcript: transcript, edits: edits, policy: .mediaV1)
    return (transcript, edits, plan)
}

private func makeMediaInfo(
    frameRate: Double?,
    hasVideo: Bool = true,
    duration: Double,
    width: Int = 1920,
    height: Int = 1080
) -> MediaInfo {
    var streams: [MediaStreamInfo] = []
    if hasVideo {
        streams.append(MediaStreamInfo(
            index: 0,
            kind: .video,
            codecName: "h264",
            width: width,
            height: height,
            averageFrameRate: frameRate,
            realFrameRate: frameRate
        ))
    }
    streams.append(MediaStreamInfo(
        index: streams.count,
        kind: .audio,
        codecName: "aac",
        sampleRate: 48_000,
        channels: 2
    ))
    return MediaInfo(duration: duration, containerNames: ["mov", "mp4"], streams: streams)
}

private let cutMatrix = [0, 1, 10, 500]
private let rateMatrix: [Double] = [23.976023976, 24, 25, 29.97002997, 30, 50, 59.94005994, 60]

// MARK: - Timecode

@Test func timecodeRateDetectsBroadcastRatesAndDropFrameCounting() {
    let ntsc = TimecodeRate.detect(29.97002997)
    #expect(ntsc.nominalFramesPerSecond == 30)
    #expect(ntsc.isDropFrame)
    #expect(ntsc.rationalFrameDuration == "1001/30000s")

    let film = TimecodeRate.detect(23.976)
    #expect(film.nominalFramesPerSecond == 24)
    #expect(!film.isDropFrame)
    #expect(film.rationalFrameDuration == "1001/24000s")

    let pal = TimecodeRate.detect(25)
    #expect(pal.nominalFramesPerSecond == 25)
    #expect(!pal.isDropFrame)
    #expect(pal.rationalFrameDuration == "100/2500s")

    let high = TimecodeRate.detect(59.94)
    #expect(high.nominalFramesPerSecond == 60)
    #expect(high.isDropFrame)
    #expect(high.rationalFrameDuration == "1001/60000s")

    #expect(TimecodeRate.detect(nil) == .fallback)
    #expect(TimecodeRate.detect(0) == .fallback)
    #expect(!TimecodeRate.fallback.isDropFrame)
}

@Test func dropFrameTimecodeSkipsTwoFramesPerMinuteExceptEveryTenth() {
    let rate = TimecodeRate.detect(29.97)
    #expect(rate.timecode(forFrames: 0) == "00:00:00;00")
    #expect(rate.timecode(forFrames: 29) == "00:00:00;29")
    #expect(rate.timecode(forFrames: 1_799) == "00:00:59;29")
    #expect(rate.timecode(forFrames: 1_800) == "00:01:00;02")
    #expect(rate.timecode(forFrames: 3_598) == "00:02:00;02")
    #expect(rate.timecode(forFrames: 17_982) == "00:10:00;00")
    #expect(rate.timecode(forFrames: 107_892) == "01:00:00;00")

    let fast = TimecodeRate.detect(59.94)
    #expect(fast.timecode(forFrames: 3_600) == "00:01:00;04")
    #expect(fast.timecode(forFrames: 35_964) == "00:10:00;00")
}

@Test func nonDropTimecodeCountsWholeFrames() {
    let pal = TimecodeRate.detect(25)
    #expect(pal.timecode(forFrames: 26) == "00:00:01:01")
    #expect(pal.timecode(forFrames: 1_500) == "00:01:00:00")
    #expect(pal.timecode(forFrames: 90_000) == "01:00:00:00")

    let film = TimecodeRate.detect(23.976)
    #expect(film.timecode(forFrames: 24) == "00:00:01:00")
    #expect(film.frameIndex(forSeconds: 1.001) == 24)
}

@Test func rationalTimesAreWholeFrameMultiples() {
    let ntsc = TimecodeRate.detect(29.97)
    #expect(ntsc.rationalTime(forFrames: 0) == "0s")
    #expect(ntsc.rationalTime(forFrames: 1) == "1001/30000s")
    #expect(ntsc.rationalTime(forFrames: 30) == "1001/1000s")

    let pal = TimecodeRate.detect(25)
    #expect(pal.rationalTime(forFrames: 50) == "2s")
    #expect(pal.rationalTime(forFrames: 1) == "1/25s")
}

// MARK: - EDL

@Test(arguments: cutMatrix)
func edlWritesOneEventPerKeptRangeAndMatchesTheEditedDurationWithinOneFrame(cuts: Int) {
    let (_, _, plan) = makeCutFixture(cuts: cuts)
    for frameRate in rateMatrix {
        let mediaInfo = makeMediaInfo(frameRate: frameRate, duration: Double(2 * cuts + 1))
        let sidecar = EDLSidecarBuilder.make(
            outputURL: URL(fileURLWithPath: "/tmp/interview_edited.mp4"),
            sourceURL: URL(fileURLWithPath: "/tmp/sources/interview.mov"),
            renderPlan: plan,
            mediaInfo: mediaInfo
        )

        #expect(sidecar.url.path == "/tmp/interview_edited.edl")
        #expect(sidecar.eventCount == plan.keptRanges.count)
        #expect(sidecar.eventCount == cuts + 1)

        let eventLines = sidecar.contents
            .split(separator: "\n")
            .filter { $0.first?.isNumber == true }
        #expect(eventLines.count == sidecar.eventCount)
        #expect(sidecar.contents.components(separatedBy: "* FROM CLIP NAME: interview.mov").count == sidecar.eventCount + 1)

        let events = CutListEvents.make(renderPlan: plan, rate: sidecar.rate)
        let keptFrames = events.reduce(0) { $0 + $1.frameCount }
        let keptSeconds = sidecar.rate.seconds(forFrames: keptFrames)
        #expect(
            abs(keptSeconds - plan.editedDuration) <= 1 / sidecar.rate.framesPerSecond,
            "\(frameRate) fps: \(keptSeconds) vs \(plan.editedDuration)"
        )
        for (index, event) in events.enumerated() {
            #expect(event.sourceOutFrame - event.sourceInFrame == event.frameCount)
            if index > 0 {
                #expect(event.recordInFrame == events[index - 1].recordOutFrame)
            }
        }
        #expect(events.first?.recordInFrame == 0)
    }
}

@Test func edlFormatsCMX3600EventsWithSourceAndRecordTimecodes() {
    let (_, _, plan) = makeCutFixture(cuts: 1)
    let sidecar = EDLSidecarBuilder.make(
        outputURL: URL(fileURLWithPath: "/tmp/talk_edited.mp4"),
        sourceURL: URL(fileURLWithPath: "/tmp/talk.mp4"),
        renderPlan: plan,
        mediaInfo: makeMediaInfo(frameRate: 25, duration: 3)
    )
    // Kept ranges: 0–0.925 s (23 frames) and 2.075–3 s (frames 52–75, 23 frames).
    let expected = """
    TITLE: talk_edited
    FCM: NON-DROP FRAME

    001  AX       AA/V  C        00:00:00:00 00:00:00:23 00:00:00:00 00:00:00:23
    * FROM CLIP NAME: talk.mp4

    002  AX       AA/V  C        00:00:02:02 00:00:03:00 00:00:00:23 00:00:01:21
    * FROM CLIP NAME: talk.mp4

    """
    #expect(sidecar.contents == expected)
}

@Test func edlUsesDropFrameTimecodeForNTSCSources() {
    let (_, _, plan) = makeCutFixture(cuts: 0)
    let sidecar = EDLSidecarBuilder.make(
        outputURL: URL(fileURLWithPath: "/tmp/a_edited.mp4"),
        sourceURL: URL(fileURLWithPath: "/tmp/a.mp4"),
        renderPlan: RenderPlan(
            transcript: SourceTranscript(words: [], language: "en", duration: 3_600),
            edits: EditDecisionList(),
            policy: .mediaV1
        ),
        mediaInfo: makeMediaInfo(frameRate: 29.97002997, duration: 3_600)
    )
    _ = plan
    #expect(sidecar.contents.contains("FCM: DROP FRAME"))
    #expect(sidecar.contents.contains("00:00:00;00 01:00:00;00 00:00:00;00 01:00:00;00"))
}

@Test func edlForAudioOnlySourcesUsesAudioTracksAndTheFallbackRate() {
    let (_, _, plan) = makeCutFixture(cuts: 2)
    let sidecar = EDLSidecarBuilder.make(
        outputURL: URL(fileURLWithPath: "/tmp/podcast_edited.m4a"),
        sourceURL: URL(fileURLWithPath: "/tmp/podcast.wav"),
        renderPlan: plan,
        mediaInfo: makeMediaInfo(frameRate: nil, hasVideo: false, duration: 5)
    )
    #expect(sidecar.rate == .fallback)
    #expect(sidecar.eventCount == 3)
    #expect(sidecar.contents.contains("001  AX       AA    C        "))
    #expect(!sidecar.contents.contains("AA/V"))
}

@Test func edlDropsKeptRangesShorterThanOneFrame() {
    let plan = RenderPlan(
        transcript: SourceTranscript(
            words: [
                TranscriptWord(id: "a", text: "a", start: 0, end: 1, confidence: 1, isSilence: false),
                TranscriptWord(id: "b", text: "b", start: 1, end: 1.165, confidence: 1, isSilence: false),
                TranscriptWord(id: "c", text: "c", start: 1.165, end: 2, confidence: 1, isSilence: false),
            ],
            language: "en",
            duration: 2
        ),
        edits: EditDecisionList(deletedWordIDs: ["a", "c"]),
        policy: .mediaV1
    )
    // Padding leaves a 15 ms kept range, under half a frame at 25 fps.
    #expect(plan.keptRanges.count == 1)
    #expect(plan.keptRanges.first.map { $0.duration < 0.04 } == true)
    let events = CutListEvents.make(renderPlan: plan, rate: TimecodeRate.detect(25))
    #expect(events.isEmpty)
}

// MARK: - FCPXML

@Test(arguments: cutMatrix)
func fcpxmlWritesOneAssetClipPerKeptRangeOnASingleSpine(cuts: Int) throws {
    let (_, _, plan) = makeCutFixture(cuts: cuts)
    for frameRate in rateMatrix {
        let mediaInfo = makeMediaInfo(frameRate: frameRate, duration: Double(2 * cuts + 1))
        let sidecar = try #require(FCPXMLSidecarBuilder.make(
            outputURL: URL(fileURLWithPath: "/tmp/interview_edited.mp4"),
            sourceURL: URL(fileURLWithPath: "/tmp/sources/interview.mov"),
            renderPlan: plan,
            mediaInfo: mediaInfo
        ))
        #expect(sidecar.url.path == "/tmp/interview_edited.fcpxml")
        #expect(sidecar.clipCount == cuts + 1)

        let document = try XMLDocument(xmlString: sidecar.contents, options: [])
        let root = try #require(document.rootElement())
        #expect(root.name == "fcpxml")
        #expect(root.attribute(forName: "version")?.stringValue == "1.10")
        #expect(try document.nodes(forXPath: "//spine").count == 1)
        #expect(try document.nodes(forXPath: "//spine/asset-clip").count == cuts + 1)
        #expect(try document.nodes(forXPath: "//resources/asset").count == 1)
        #expect(try document.nodes(forXPath: "//resources/asset/media-rep[@kind='original-media']").count == 1)

        let format = try #require(try document.nodes(forXPath: "//resources/format").first as? XMLElement)
        #expect(format.attribute(forName: "frameDuration")?.stringValue == sidecar.rate.rationalFrameDuration)

        let clips = try document.nodes(forXPath: "//spine/asset-clip").compactMap { $0 as? XMLElement }
        let events = CutListEvents.make(renderPlan: plan, rate: sidecar.rate)
        for (clip, event) in zip(clips, events) {
            #expect(clip.attribute(forName: "ref")?.stringValue == "r2")
            #expect(clip.attribute(forName: "offset")?.stringValue == sidecar.rate.rationalTime(forFrames: event.recordInFrame))
            #expect(clip.attribute(forName: "start")?.stringValue == sidecar.rate.rationalTime(forFrames: event.sourceInFrame))
            #expect(clip.attribute(forName: "duration")?.stringValue == sidecar.rate.rationalTime(forFrames: event.frameCount))
        }
        let keptFrames = events.reduce(0) { $0 + $1.frameCount }
        #expect(abs(sidecar.rate.seconds(forFrames: keptFrames) - plan.editedDuration) <= 1 / sidecar.rate.framesPerSecond)
    }
}

@Test func fcpxmlDescribesTheSourceAssetAndDropFrameSequence() throws {
    let (_, _, plan) = makeCutFixture(cuts: 1)
    let sidecar = try #require(FCPXMLSidecarBuilder.make(
        outputURL: URL(fileURLWithPath: "/tmp/talk_edited.mp4"),
        sourceURL: URL(fileURLWithPath: "/tmp/Clips & Takes/talk <1>.mov"),
        renderPlan: plan,
        mediaInfo: makeMediaInfo(frameRate: 29.97002997, duration: 3)
    ))
    let document = try XMLDocument(xmlString: sidecar.contents, options: [])
    let format = try #require(try document.nodes(forXPath: "//format").first as? XMLElement)
    #expect(format.attribute(forName: "name")?.stringValue == "FFVideoFormat1080p2997")
    #expect(format.attribute(forName: "width")?.stringValue == "1920")
    #expect(format.attribute(forName: "height")?.stringValue == "1080")

    let asset = try #require(try document.nodes(forXPath: "//asset").first as? XMLElement)
    #expect(asset.attribute(forName: "name")?.stringValue == "talk <1>")
    #expect(asset.attribute(forName: "hasVideo")?.stringValue == "1")
    #expect(asset.attribute(forName: "hasAudio")?.stringValue == "1")
    #expect(asset.attribute(forName: "audioRate")?.stringValue == "48000")
    #expect(asset.attribute(forName: "duration")?.stringValue == sidecar.rate.rationalTime(forFrames: 90))
    #expect(asset.attribute(forName: "uid")?.stringValue == FCPXMLSidecarBuilder.stableUID(for: URL(fileURLWithPath: "/tmp/Clips & Takes/talk <1>.mov")))

    let mediaRep = try #require(try document.nodes(forXPath: "//media-rep").first as? XMLElement)
    #expect(mediaRep.attribute(forName: "src")?.stringValue == "file:///tmp/Clips%20&%20Takes/talk%20%3C1%3E.mov")

    let sequence = try #require(try document.nodes(forXPath: "//sequence").first as? XMLElement)
    #expect(sequence.attribute(forName: "tcFormat")?.stringValue == "DF")
    #expect(sequence.attribute(forName: "audioLayout")?.stringValue == "stereo")
    #expect(sequence.attribute(forName: "audioRate")?.stringValue == "48k")

    let project = try #require(try document.nodes(forXPath: "//project").first as? XMLElement)
    #expect(project.attribute(forName: "name")?.stringValue == "talk_edited")
}

@Test func fcpxmlIsNotOfferedForAudioOnlySources() {
    let (_, _, plan) = makeCutFixture(cuts: 1)
    let sidecar = FCPXMLSidecarBuilder.make(
        outputURL: URL(fileURLWithPath: "/tmp/podcast_edited.m4a"),
        sourceURL: URL(fileURLWithPath: "/tmp/podcast.wav"),
        renderPlan: plan,
        mediaInfo: makeMediaInfo(frameRate: nil, hasVideo: false, duration: 3)
    )
    #expect(sidecar == nil)
}

@Test func fcpxmlOmitsFormatNameForUncommonDimensions() {
    #expect(FCPXMLSidecarBuilder.formatName(rate: TimecodeRate.detect(25), width: 1920, height: 1080) == "FFVideoFormat1080p25")
    #expect(FCPXMLSidecarBuilder.formatName(rate: TimecodeRate.detect(23.976), width: 3840, height: 2160) == "FFVideoFormat3840x21602398")
    #expect(FCPXMLSidecarBuilder.formatName(rate: TimecodeRate.detect(25), width: 1080, height: 1920) == nil)
    #expect(FCPXMLSidecarBuilder.formatName(rate: TimecodeRate.detect(120), width: 1920, height: 1080) == nil)
}
