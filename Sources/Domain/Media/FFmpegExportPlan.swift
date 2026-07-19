import Foundation

enum FFmpegExportStrategy: Equatable, Sendable {
    case streamCopy
    case audioFilterTranscode
    case singleRangeTranscode
    case selectionFilterTranscode
    case batchedSelectionTranscode
    case filterGraphTranscode
}

struct FFmpegExportPlan: Equatable, Sendable {
    static let selectionFilterMaximumRangeCount = 50
    static let lightAudioEnhancementFilter = [
        "highpass=f=70",
        "afftdn=nr=6:nf=-50:tn=1:gs=5",
        "loudnorm=I=-16:TP=-1.5:LRA=11",
        "aresample=48000",
    ].joined(separator: ",")
    private static let audioConcatChunkSize = 50

    let strategy: FFmpegExportStrategy
    let preset: ExportPreset
    let filterGraph: String
    let arguments: [String]

    init(
        inputPath: String,
        outputPath: String,
        segments: [TimeRange],
        preset: ExportPreset,
        quality: String?,
        speed: Double,
        enhanceAudio: Bool = false,
        sourceInfo: MediaInfo? = nil,
        sourceIsUnchanged: Bool = false,
        inputSeek: Double? = nil,
        inputDuration: Double? = nil
    ) {
        self.preset = preset

        if sourceIsUnchanged,
           quality == nil,
           speed == 1,
           let sourceInfo,
           preset.supportsStreamCopy(from: sourceInfo) {
            strategy = enhanceAudio ? .audioFilterTranscode : .streamCopy
            filterGraph = ""
            if enhanceAudio {
                arguments = Self.audioFilterArguments(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    preset: preset
                )
            } else {
                arguments = Self.streamCopyArguments(
                    inputPath: inputPath,
                    outputPath: outputPath,
                    preset: preset
                )
            }
            return
        }

        if segments.count == 1, speed == 1, let segment = segments.first {
            strategy = .singleRangeTranscode
            filterGraph = ""
            arguments = Self.singleRangeArguments(
                inputPath: inputPath,
                outputPath: outputPath,
                segment: segment,
                preset: preset,
                quality: quality,
                enhanceAudio: enhanceAudio
            )
            return
        }

        if segments.count >= 2,
           preset.mediaKind == .video,
           let frameRate = sourceInfo?.videoStream?.constantFrameRate {
            if segments.count > Self.selectionFilterMaximumRangeCount {
                strategy = .batchedSelectionTranscode
                filterGraph = ""
                arguments = []
                return
            }
            strategy = .selectionFilterTranscode
            let graph = Self.makeSelectionFilterGraph(
                segments: segments,
                quality: quality,
                speed: speed,
                enhanceAudio: enhanceAudio,
                frameRate: frameRate
            )
            filterGraph = graph

            var processArguments = ["-nostdin"]
            if let inputSeek {
                processArguments += [
                    "-ss", String(format: "%.4f", inputSeek),
                    "-copyts",
                ]
            }
            if let inputDuration {
                processArguments += ["-t", String(format: "%.4f", inputDuration)]
            }
            processArguments += ["-i", inputPath, "-filter_complex", graph]
            processArguments += Self.filteredMapArguments(for: preset)
            processArguments += Self.codecArguments(for: preset)
            processArguments += Self.containerArguments(for: preset)
            processArguments += ["-y", outputPath]
            arguments = processArguments
            return
        }

        strategy = .filterGraphTranscode
        let graph = Self.makeFilterGraph(
            segments: segments,
            preset: preset,
            quality: quality,
            speed: speed,
            enhanceAudio: enhanceAudio
        )
        filterGraph = graph

        var processArguments = [
            "-nostdin",
            "-i", inputPath,
            "-filter_complex", graph,
        ]
        processArguments += Self.filteredMapArguments(for: preset)
        processArguments += Self.codecArguments(for: preset)
        processArguments += Self.containerArguments(for: preset)
        processArguments += ["-y", outputPath]
        arguments = processArguments
    }

    private static func streamCopyArguments(
        inputPath: String,
        outputPath: String,
        preset: ExportPreset
    ) -> [String] {
        var processArguments = ["-nostdin", "-i", inputPath]
        processArguments += inputMapArguments(for: preset)
        processArguments += ["-c", "copy"]
        processArguments += containerArguments(for: preset)
        processArguments += ["-y", outputPath]
        return processArguments
    }

    private static func singleRangeArguments(
        inputPath: String,
        outputPath: String,
        segment: TimeRange,
        preset: ExportPreset,
        quality: String?,
        enhanceAudio: Bool
    ) -> [String] {
        var processArguments = [
            "-nostdin",
            "-ss", String(format: "%.4f", segment.start),
            "-i", inputPath,
            "-t", String(format: "%.4f", segment.duration),
        ]
        processArguments += inputMapArguments(for: preset)
        if let height = outputHeight(for: quality), preset.mediaKind == .video {
            processArguments += ["-vf", "scale=-2:\(height)"]
        }
        if enhanceAudio {
            processArguments += ["-af", lightAudioEnhancementFilter]
        }
        processArguments += codecArguments(for: preset)
        processArguments += containerArguments(for: preset)
        processArguments += ["-y", outputPath]
        return processArguments
    }

    private static func makeFilterGraph(
        segments: [TimeRange],
        preset: ExportPreset,
        quality: String?,
        speed: Double,
        enhanceAudio: Bool
    ) -> String {
        var filters: [String] = []

        for (index, segment) in segments.enumerated() {
            let start = String(format: "%.4f", segment.start)
            let end = String(format: "%.4f", segment.end)
            if preset.mediaKind == .video {
                filters.append("[0:v]trim=start=\(start):end=\(end),setpts=PTS-STARTPTS[v\(index)]")
            }
            filters.append("[0:a]atrim=start=\(start):end=\(end),asetpts=PTS-STARTPTS[a\(index)]")
        }

        let combinedAudio: String
        let combinedVideo: String?
        if segments.count == 1 {
            combinedAudio = "a0"
            combinedVideo = preset.mediaKind == .video ? "v0" : nil
        } else if preset.mediaKind == .video {
            let inputs = (0..<segments.count).map { "[v\($0)][a\($0)]" }.joined()
            filters.append("\(inputs)concat=n=\(segments.count):v=1:a=1[joinedv][joineda]")
            combinedAudio = "joineda"
            combinedVideo = "joinedv"
        } else {
            let inputs = (0..<segments.count).map { "[a\($0)]" }.joined()
            filters.append("\(inputs)concat=n=\(segments.count):v=0:a=1[joineda]")
            combinedAudio = "joineda"
            combinedVideo = nil
        }

        appendAudioOutput(
            inputLabel: combinedAudio,
            speed: speed,
            enhanceAudio: enhanceAudio,
            filters: &filters
        )

        if let combinedVideo {
            if speed != 1, let height = outputHeight(for: quality) {
                filters.append("[\(combinedVideo)]setpts=PTS/\(speed)[speedv]")
                filters.append("[speedv]scale=-2:\(height)[outv]")
            } else if speed != 1 {
                filters.append("[\(combinedVideo)]setpts=PTS/\(speed)[outv]")
            } else if let height = outputHeight(for: quality) {
                filters.append("[\(combinedVideo)]scale=-2:\(height)[outv]")
            } else {
                filters.append("[\(combinedVideo)]null[outv]")
            }
        }

        return filters.joined(separator: ";")
    }

    private static func makeSelectionFilterGraph(
        segments: [TimeRange],
        quality: String?,
        speed: Double,
        enhanceAudio: Bool,
        frameRate: Double
    ) -> String {
        var filters: [String] = []
        let rate = String(format: "%.6f", frameRate)
        let selectionExpression = segments.map { segment in
            let start = String(format: "%.4f", segment.start)
            let end = String(format: "%.4f", segment.end)
            return "gte(t\\,\(start))*lt(t\\,\(end))"
        }.joined(separator: "+")
        filters.append(
            "[0:v]select='\(selectionExpression)',setpts=N/(\(rate)*TB)[joinedv]"
        )

        let joinedAudio = appendSegmentedAudio(
            segments: segments,
            filters: &filters
        )

        appendAudioOutput(
            inputLabel: joinedAudio,
            speed: speed,
            enhanceAudio: enhanceAudio,
            filters: &filters
        )

        if speed != 1, let height = outputHeight(for: quality) {
            filters.append("[joinedv]setpts=PTS/\(speed)[speedv]")
            filters.append("[speedv]scale=-2:\(height)[outv]")
        } else if speed != 1 {
            filters.append("[joinedv]setpts=PTS/\(speed)[outv]")
        } else if let height = outputHeight(for: quality) {
            filters.append("[joinedv]scale=-2:\(height)[outv]")
        } else {
            filters.append("[joinedv]null[outv]")
        }

        return filters.joined(separator: ";")
    }

    private static func appendSegmentedAudio(
        segments: [TimeRange],
        filters: inout [String]
    ) -> String {
        var timestamps: [String] = []
        var keptOutputIndexes = Set<Int>()
        var outputIndex = 0

        func appendBoundary(_ time: Double) {
            let timestamp = String(format: "%.4f", time)
            guard timestamps.last != timestamp else { return }
            timestamps.append(timestamp)
            outputIndex += 1
        }

        for segment in segments {
            if segment.start > 0 {
                appendBoundary(segment.start)
            }
            keptOutputIndexes.insert(outputIndex)
            appendBoundary(segment.end)
        }

        let segmentLabels = (0...timestamps.count).map { "audiosegment\($0)" }
        let outputs = segmentLabels.map { "[\($0)]" }.joined()
        filters.append(
            "[0:a]asegment=timestamps='\(timestamps.joined(separator: "|"))'\(outputs)"
        )

        var audioLabels: [String] = []
        for (index, segmentLabel) in segmentLabels.enumerated() {
            guard keptOutputIndexes.contains(index) else {
                filters.append("[\(segmentLabel)]anullsink")
                continue
            }
            let audioLabel = "a\(audioLabels.count)"
            filters.append("[\(segmentLabel)]asetpts=PTS-STARTPTS[\(audioLabel)]")
            audioLabels.append(audioLabel)
        }

        return appendBoundedAudioConcat(labels: audioLabels, filters: &filters)
    }

    private static func appendBoundedAudioConcat(
        labels: [String],
        filters: inout [String]
    ) -> String {
        var chunkLabels: [String] = []
        for chunkStart in stride(
            from: 0,
            to: labels.count,
            by: audioConcatChunkSize
        ) {
            let chunkEnd = min(chunkStart + audioConcatChunkSize, labels.count)
            let chunk = labels[chunkStart..<chunkEnd]
            let inputs = chunk.map { "[\($0)]" }.joined()
            let output = "audiochunk\(chunkLabels.count)"
            filters.append("\(inputs)concat=n=\(chunk.count):v=0:a=1[\(output)]")
            chunkLabels.append(output)
        }

        guard chunkLabels.count > 1 else {
            return chunkLabels[0]
        }
        let inputs = chunkLabels.map { "[\($0)]" }.joined()
        filters.append("\(inputs)concat=n=\(chunkLabels.count):v=0:a=1[joineda]")
        return "joineda"
    }

    private static func appendAudioOutput(
        inputLabel: String,
        speed: Double,
        enhanceAudio: Bool,
        filters: inout [String]
    ) {
        var outputFilters: [String] = []
        if speed != 1 {
            outputFilters.append("atempo=\(speed)")
        }
        if enhanceAudio {
            outputFilters.append(lightAudioEnhancementFilter)
        }
        if outputFilters.isEmpty {
            outputFilters.append("anull")
        }
        filters.append("[\(inputLabel)]\(outputFilters.joined(separator: ","))[outa]")
    }

    private static func audioFilterArguments(
        inputPath: String,
        outputPath: String,
        preset: ExportPreset
    ) -> [String] {
        var processArguments = ["-nostdin", "-i", inputPath]
        processArguments += inputMapArguments(for: preset)
        if preset.mediaKind == .video {
            processArguments += ["-c:v", "copy"]
        }
        processArguments += ["-af", lightAudioEnhancementFilter]
        processArguments += audioCodecArguments(for: preset)
        processArguments += containerArguments(for: preset)
        processArguments += ["-y", outputPath]
        return processArguments
    }

    private static func filteredMapArguments(for preset: ExportPreset) -> [String] {
        var arguments: [String] = []
        if preset.mediaKind == .video {
            arguments += ["-map", "[outv]"]
        }
        arguments += ["-map", "[outa]"]
        return arguments
    }

    private static func inputMapArguments(for preset: ExportPreset) -> [String] {
        var arguments: [String] = []
        if preset.mediaKind == .video {
            arguments += ["-map", "0:v:0"]
        }
        arguments += ["-map", "0:a:0"]
        return arguments
    }

    private static func codecArguments(for preset: ExportPreset) -> [String] {
        var arguments: [String] = []
        if let videoCodec = preset.videoCodec {
            arguments += ["-c:v", videoCodec]
            if videoCodec == "libvpx-vp9" {
                arguments += [
                    "-crf", "30",
                    "-b:v", "0",
                    "-deadline", "realtime",
                    "-cpu-used", "6",
                    "-row-mt", "1",
                    "-tile-columns", "2",
                    "-threads", "0",
                ]
            } else {
                arguments += ["-preset", "fast", "-crf", "18"]
            }
        }

        arguments += audioCodecArguments(for: preset)
        return arguments
    }

    private static func audioCodecArguments(for preset: ExportPreset) -> [String] {
        var arguments = ["-c:a", preset.audioCodec]
        if preset.audioCodec != "pcm_s16le" {
            arguments += ["-b:a", "192k"]
        }
        return arguments
    }

    private static func containerArguments(for preset: ExportPreset) -> [String] {
        if preset.pathExtension == "mp4" || preset.pathExtension == "m4a" {
            return ["-movflags", "+faststart"]
        }
        return []
    }

    private static func outputHeight(for quality: String?) -> Int? {
        switch quality {
        case "1080p": 1080
        case "720p": 720
        default: nil
        }
    }
}
