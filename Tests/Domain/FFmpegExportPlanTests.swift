import Testing
@testable import Redact

@Test func ffmpegExportPlanBuildsSingleSegmentArgumentsWithoutExecutingAProcess() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mov",
        outputPath: "/output.mp4",
        segments: [TimeRange(start: 0.5, end: 3.0)],
        preset: .mp4Video,
        quality: "1080p",
        speed: 1
    )

    #expect(plan.arguments.contains("/input.mov"))
    #expect(plan.arguments.contains("/output.mp4"))
    #expect(plan.strategy == .singleRangeTranscode)
    #expect(plan.filterGraph.isEmpty)
    #expect(plan.arguments.contains("scale=-2:1080"))
    #expect(plan.arguments.contains("0.5000"))
    #expect(plan.arguments.contains("2.5000"))
}

@Test func ffmpegExportPlanPreservesCanonicalDurationAcrossMultipleSegments() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mov",
        outputPath: "/output.mp4",
        segments: [
            TimeRange(start: 0, end: 2),
            TimeRange(start: 3, end: 5),
        ],
        preset: .mp4Video,
        quality: nil,
        speed: 1
    )

    #expect(plan.filterGraph.contains("concat=n=2:v=1:a=1"))
    #expect(!plan.filterGraph.contains("xfade"))
    #expect(!plan.filterGraph.contains("acrossfade"))
    #expect(plan.filterGraph.contains("[outv]"))
    #expect(plan.filterGraph.contains("[outa]"))
}

@Test func ffmpegExportPlanScalesAfterJoiningMultipleSegments() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mov",
        outputPath: "/output.mp4",
        segments: [
            TimeRange(start: 0, end: 1),
            TimeRange(start: 2, end: 3),
        ],
        preset: .mp4Video,
        quality: "720p",
        speed: 1
    )

    #expect(plan.filterGraph.contains("concat=n=2:v=1:a=1[joinedv][joineda]"))
    #expect(plan.filterGraph.contains("scale=-2:720"))
}

@Test func ffmpegExportPlanAppliesPlaybackSpeedToVideoAndAudio() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mov",
        outputPath: "/output.mp4",
        segments: [TimeRange(start: 0, end: 2)],
        preset: .mp4Video,
        quality: nil,
        speed: 1.5
    )

    #expect(plan.filterGraph.contains("[v0]setpts=PTS/1.5[outv]"))
    #expect(plan.filterGraph.contains("[a0]atempo=1.5[outa]"))
}

@Test func ffmpegExportPlanBuildsRealAudioOnlyArguments() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mov",
        outputPath: "/output.m4a",
        segments: [
            TimeRange(start: 0, end: 1),
            TimeRange(start: 2, end: 3),
        ],
        preset: .m4aAudio,
        quality: nil,
        speed: 1
    )

    #expect(plan.filterGraph.contains("[0:a]atrim"))
    #expect(plan.filterGraph.contains("concat=n=2:v=0:a=1"))
    #expect(!plan.filterGraph.contains("acrossfade"))
    #expect(!plan.filterGraph.contains("[0:v]"))
    #expect(plan.arguments.contains("aac"))
    #expect(!plan.arguments.contains("-c:v"))
}

@Test func ffmpegExportPlanStreamCopiesUnchangedCompatibleMedia() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mp4",
        outputPath: "/output.mp4",
        segments: [TimeRange(start: 0, end: 12)],
        preset: .mp4Video,
        quality: nil,
        speed: 1,
        sourceInfo: compatibleMP4Info(),
        sourceIsUnchanged: true
    )

    #expect(plan.strategy == .streamCopy)
    #expect(plan.arguments.contains("copy"))
    #expect(!plan.arguments.contains("-filter_complex"))
}

@Test func ffmpegExportPlanEnhancesOnlyAudioForUnchangedCompatibleVideo() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mp4",
        outputPath: "/output.mp4",
        segments: [TimeRange(start: 0, end: 12)],
        preset: .mp4Video,
        quality: nil,
        speed: 1,
        enhanceAudio: true,
        sourceInfo: compatibleMP4Info(),
        sourceIsUnchanged: true
    )

    #expect(plan.strategy == .audioFilterTranscode)
    #expect(plan.arguments.contains("-af"))
    #expect(plan.arguments.contains(FFmpegExportPlan.lightAudioEnhancementFilter))
    #expect(plan.arguments.contains("-c:v"))
    #expect(plan.arguments.contains("copy"))
    #expect(plan.arguments.contains("aac"))
}

@Test func ffmpegExportPlanAppliesLightEnhancementAfterJoiningEditedAudio() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mp4",
        outputPath: "/output.mp4",
        segments: [
            TimeRange(start: 0, end: 2),
            TimeRange(start: 3, end: 5),
        ],
        preset: .mp4Video,
        quality: nil,
        speed: 1,
        enhanceAudio: true
    )

    #expect(
        plan.filterGraph.contains(
            "[joineda]" + FFmpegExportPlan.lightAudioEnhancementFilter + "[outa]"
        )
    )
}

@Test func ffmpegExportPlanUsesSimpleTranscodeForOneEditedRange() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mp4",
        outputPath: "/output.mp4",
        segments: [TimeRange(start: 2, end: 5)],
        preset: .mp4Video,
        quality: nil,
        speed: 1,
        sourceInfo: compatibleMP4Info(),
        sourceIsUnchanged: false
    )

    #expect(plan.strategy == .singleRangeTranscode)
    #expect(plan.arguments.contains("-ss"))
    #expect(plan.arguments.contains("2.0000"))
    #expect(plan.arguments.contains("-t"))
    #expect(plan.arguments.contains("3.0000"))
    #expect(!plan.arguments.contains("-filter_complex"))
}

@Test func ffmpegExportPlanDoesNotCopyIntoAnIncompatibleCodecPreset() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mp4",
        outputPath: "/output.webm",
        segments: [TimeRange(start: 0, end: 12)],
        preset: .webMVideo,
        quality: nil,
        speed: 1,
        sourceInfo: compatibleMP4Info(),
        sourceIsUnchanged: true
    )

    #expect(plan.strategy == .singleRangeTranscode)
    #expect(plan.arguments.contains("libvpx-vp9"))
    #expect(plan.arguments.contains("libopus"))
    #expect(!plan.arguments.contains("copy"))
}

@Test func ffmpegExportPlanUsesBoundedVideoSelectionForManyConstantFrameRateRanges() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mp4",
        outputPath: "/output.mp4",
        segments: manyKeptRanges(count: 50),
        preset: .mp4Video,
        quality: nil,
        speed: 1,
        sourceInfo: compatibleMP4Info(averageFrameRate: 30, realFrameRate: 30),
        sourceIsUnchanged: false
    )

    #expect(plan.strategy == .selectionFilterTranscode)
    #expect(plan.filterGraph.contains("[0:v]select="))
    #expect(plan.filterGraph.components(separatedBy: "[0:v]select=").count == 2)
    #expect(!plan.filterGraph.contains("[0:v]trim="))
    #expect(plan.filterGraph.contains("[0:a]asegment="))
    #expect(!plan.filterGraph.contains("[0:a]atrim="))
}

@Test func ffmpegExportPlanBatchesConstantFrameRateRangesAboveTheSelectionLimit() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mp4",
        outputPath: "/output.mp4",
        segments: manyKeptRanges(count: 51),
        preset: .mp4Video,
        quality: nil,
        speed: 1,
        sourceInfo: compatibleMP4Info(averageFrameRate: 30, realFrameRate: 30),
        sourceIsUnchanged: false
    )

    #expect(plan.strategy == .batchedSelectionTranscode)
    #expect(plan.filterGraph.isEmpty)
    #expect(plan.arguments.isEmpty)
}

@Test func ffmpegExportPlanKeepsAbsoluteTimestampsInsideASeekedBatch() throws {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mp4",
        outputPath: "/output.mkv",
        segments: [
            TimeRange(start: 10, end: 11),
            TimeRange(start: 12, end: 13),
        ],
        preset: ExportPreset(
            id: "test-intermediate",
            title: "Test intermediate",
            pathExtension: "mkv",
            mediaKind: .video,
            videoCodec: "libx264",
            audioCodec: "pcm_s16le"
        ),
        quality: nil,
        speed: 1,
        sourceInfo: compatibleMP4Info(averageFrameRate: 30, realFrameRate: 30),
        sourceIsUnchanged: false,
        inputSeek: 10,
        inputDuration: 3
    )

    let seekIndex = try #require(plan.arguments.firstIndex(of: "-ss"))
    let copyTimestampsIndex = try #require(plan.arguments.firstIndex(of: "-copyts"))
    let durationIndex = try #require(plan.arguments.firstIndex(of: "-t"))
    let inputIndex = try #require(plan.arguments.firstIndex(of: "-i"))
    #expect(plan.arguments[seekIndex + 1] == "10.0000")
    #expect(plan.arguments[durationIndex + 1] == "3.0000")
    #expect(copyTimestampsIndex < inputIndex)
    #expect(durationIndex < inputIndex)
    #expect(plan.filterGraph.contains("gte(t\\,10.0000)*lt(t\\,11.0000)"))
}

@Test func ffmpegExportPlanKeepsTrimFallbackForManyVariableFrameRateRanges() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mp4",
        outputPath: "/output.mp4",
        segments: manyKeptRanges(),
        preset: .mp4Video,
        quality: nil,
        speed: 1,
        sourceInfo: compatibleMP4Info(averageFrameRate: 29.5, realFrameRate: 30),
        sourceIsUnchanged: false
    )

    #expect(plan.strategy == .filterGraphTranscode)
    #expect(plan.filterGraph.contains("[0:v]trim="))
}

@Test func batchedConcatCapsOutputAtTheSpeedAdjustedDuration() {
    let arguments = FFmpegService.batchedConcatArguments(
        manifestPath: "/private/concat.txt",
        outputPath: "/private/output.mp4",
        preset: .mp4Video,
        enhanceAudio: false,
        expectedDuration: 24
    )

    #expect(argumentsContain(arguments, option: "-t", value: "24.000000"))
    #expect(arguments.contains("-c:v"))
    #expect(arguments.contains("copy"))
    #expect(arguments.contains("+faststart"))
}

private func compatibleMP4Info(
    averageFrameRate: Double? = nil,
    realFrameRate: Double? = nil
) -> MediaInfo {
    MediaInfo(
        duration: 12,
        containerNames: ["mov", "mp4"],
        streams: [
            MediaStreamInfo(
                index: 0,
                kind: .video,
                codecName: "h264",
                averageFrameRate: averageFrameRate,
                realFrameRate: realFrameRate
            ),
            MediaStreamInfo(index: 1, kind: .audio, codecName: "aac"),
        ]
    )
}

private func manyKeptRanges(count: Int = 200) -> [TimeRange] {
    (0..<count).map { index in
        let start = Double(index) * 0.2
        return TimeRange(start: start, end: start + 0.1)
    }
}

@Test func ffmpegExportPlanUsesWebMCompatibleCodecs() {
    let plan = FFmpegExportPlan(
        inputPath: "/input.mov",
        outputPath: "/output.webm",
        segments: [TimeRange(start: 0, end: 1)],
        preset: .webMVideo,
        quality: nil,
        speed: 1
    )

    #expect(plan.arguments.contains("libvpx-vp9"))
    #expect(plan.arguments.contains("libopus"))
    #expect(!plan.arguments.contains("libx264"))
    #expect(!plan.arguments.contains("aac"))
    #expect(argumentsContain(plan.arguments, option: "-deadline", value: "realtime"))
    #expect(argumentsContain(plan.arguments, option: "-cpu-used", value: "6"))
    #expect(argumentsContain(plan.arguments, option: "-row-mt", value: "1"))
    #expect(argumentsContain(plan.arguments, option: "-tile-columns", value: "2"))
    #expect(argumentsContain(plan.arguments, option: "-threads", value: "0"))
}

private func argumentsContain(_ arguments: [String], option: String, value: String) -> Bool {
    arguments.indices.dropLast().contains { index in
        arguments[index] == option && arguments[index + 1] == value
    }
}
