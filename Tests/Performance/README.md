# Performance Baselines

These tests measure Redact's transcript-domain operations with deterministic synthetic data. They do not use or commit private media.

## Run the synthetic baseline

From the repository root:

```bash
RUN_REDACT_BENCHMARKS=1 swift test --filter canonicalEditPlanPerformance
```

The benchmark creates transcripts at 5K, 25K, and 100K words. Each result reports:

- the v1 kept/deleted range calculation;
- the v2 canonical `RenderPlan` calculation;
- construction of the v2 `TranscriptIndex`.

## Phase 1 baseline

Captured on 2026-07-15 on san's Apple Silicon Mac from the `v2` branch.

| Words | V1 ranges | V2 render plan | V2 index |
| ---: | ---: | ---: | ---: |
| 5,000 | 0.173 ms | 0.450 ms | 0.939 ms |
| 25,000 | 0.617 ms | 2.357 ms | 4.912 ms |
| 100,000 | 2.331 ms | 8.454 ms | 16.822 ms |

These are architecture baselines, not release claims. Results vary with machine load and debug instrumentation. Compare changes on the same machine and use repeated runs before treating a small difference as meaningful.

## Phase 3 indexed-edit baseline

Run the focused 100K-word edit check with:

```bash
RUN_REDACT_BENCHMARKS=1 swift test --filter indexedProjectEditPerformance
```

The benchmark starts with half of the 100K words deleted, then applies one more deletion in the middle. The final 2026-07-15 verification measured 0.842 ms. The operation updates the canonical edit decision list and the two v1 compatibility projections at indexed positions. It does not rebuild either complete word array. The test fails if this operation exceeds the 16 ms main-thread budget in `DESIGN.md`.

Run the synthetic composition check with:

```bash
RUN_REDACT_BENCHMARKS=1 swift test --filter previewCompositionBuildPerformance
```

The test builds an audio preview from 500 kept ranges. The final 2026-07-15 verification measured 3.032 ms, compared with the 150 ms budget in `DESIGN.md`. Its 25-second result may differ by up to 50 ms after 500 insertions because AVFoundation rounds each boundary to an audio sample. This is a synthetic audio baseline, not a substitute for the private video and codec matrix below.

Run the focused 100K-word transcript-selection check with:

```bash
RUN_REDACT_BENCHMARKS=1 swift test --filter transcriptSelectionIndexPerformance
```

The final three-run median on 2026-07-15 measured 23.217 ms to build the selection index, 0.033 ms to resolve a point selection, 16.514 ms to resolve Select All, and 3.967 ms to shift indexed ranges after a correction. TextKit 2 owns viewport layout and native text behavior; the index translates character ranges into Redact's stable word IDs and keeps word lookup constant-time.

Run the 100K-word correction checks with:

```bash
RUN_REDACT_BENCHMARKS=1 swift test --filter displayTextCorrectionPerformance
RUN_REDACT_BENCHMARKS=1 swift test --filter transcriptViewLoadAndCorrectionPerformance
```

The model-only correction measured 3.091 ms. Across three initial full-view runs, TextKit 2 transcript loading had a 374.159 ms median and the complete visible correction path had a 13.810 ms median.

A 2026-07-16 background run exposed that attributed-string replacement plus redundant selection reassignment could exceed the 16 ms budget under load. Redact now uses a TextKit editing transaction with a plain string replacement and only restores a non-empty selection. The focused 100K-word verification measured 1.306 ms for the complete visible correction path while the selection-preservation regression test remained green. The correction test fails if the visible update exceeds the 16 ms main-thread budget in `DESIGN.md`.

## Phase 4 synthetic media baseline

Run the deterministic media cut-count benchmark with:

```bash
RUN_REDACT_MEDIA_BENCHMARKS=1 swift test --filter mediaRenderingCutCountBenchmark
```

The fixture is a generated 12-second, 160 × 90, 15 fps H.264/AAC file. It contains no private media. The benchmark builds an AVFoundation preview and renders an MP4 through FFmpeg at 0, 10, 100, and 500 cuts. These 2026-07-15 results are medians from three runs on san's Apple Silicon Mac:

| Cuts | Kept ranges | Preview build | FFmpeg export |
| ---: | ---: | ---: | ---: |
| 0 | 1 | 7.212 ms | 19.615 ms |
| 10 | 11 | 0.874 ms | 142.850 ms |
| 100 | 101 | 1.098 ms | 216.973 ms |
| 500 | 501 | 2.298 ms | 420.313 ms |

The zero-cut case uses verified stream copy. A single edited range uses input seeking plus a normal transcode. Multiple ranges use canonical hard cuts, with no duration-shortening crossfade. Likely constant-frame-rate exports use one video selector and sample-level audio segmentation through 50 ranges. Larger jobs run as sequential batches of at most 50 ranges, then concatenate the private intermediates with canonical duration directives. Video is copied from the intermediates and audio is encoded once. Variable-frame-rate media retains the ordinary trim/concat path. This keeps filter graphs and decoded-frame buffering bounded as the cut count grows.

The 500-cut fixture deliberately creates sub-frame ranges to stress graph construction; accumulated AVFoundation frame rounding can reach roughly half a second in that synthetic case. It is not a substitute for the representative private-media procedure below.

## Initial private-media result

An explicitly selected 14:59, 1280 x 720, 29.97 fps H.264/AAC file provided the first real-media check. This is one warm single-run sample between the formal short and medium classes, so it does not complete the representative matrix. Only aggregate measurements are recorded here; the source filename, path, transcript, hashes, and speech content remain outside version control.

| Cuts | Kept ranges | Preview build | FFmpeg export | Output duration delta |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 1 | 7.189 ms | 170.169 ms | 0 ms |
| 10 | 11 | 1.098 ms | 17,606.043 ms | 0.049 ms |
| 100 | 101 | 1.291 ms | 23,323.097 ms | 10.502 ms |
| 500 | 501 | 2.988 ms | 25,837.716 ms | 40.757 ms |

Before sequential batching, the 500-cut export reached 17.49 GB peak resident memory. The bounded implementation completed at 441.6 MB, a 39.6x or 97.5% reduction, while keeping the duration error below one 29.97 fps frame plus normal container rounding. The packaged app also passed import, transcription, playback, save/reopen, SRT/MP4/MP3 export, forced missing-media recovery, and relink with this file.

## WhisperKit compatibility decision

WhisperKit 0.15.0 and 1.0.0 were compared on the same private five-minute, 16 kHz mono excerpt using the Small model and the same local model cache. The transcript output was identical: 1,094 words, 99 segments, and matching text and timestamp hashes.

| Version | First text | Total transcription | Whole invocation peak RSS |
| --- | ---: | ---: | ---: |
| 0.15.0 | 3.315 s | 11.792 s | 719 MB |
| 1.0.0 | 4.075 s | 12.360 s | 1,007 MB |

The 1.0.0 peak includes a fresh isolated dependency build, so it is a conservative whole-command measurement rather than a runtime-only memory comparison. Since 1.0.0 produced no transcript improvement and was slightly slower, Redact remains pinned to WhisperKit 0.15.0.

## Representative medium-media result

An explicitly selected 28:54, 1280 x 720, 29.97 fps H.264/AAC talking-head video completed the background medium-class pass. It contained 6,276 transcribed words across 510 segments. The warm Small-model run reached first text in 9.972 seconds and completed in 57.838 seconds with 1.12 GB peak RSS.

Only aggregate measurements are recorded here. The source filename, path, transcript, hashes, and speech content remain outside version control.

| Cuts | Kept ranges | Preview build | FFmpeg export | Output duration delta | Output size |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0 | 1 | 18.002 ms | 0.591 s | 0 ms | 72.5 MB |
| 10 | 11 | 5.700 ms | 183.754 s | 0.031 ms | 103.9 MB |
| 100 | 101 | 6.069 ms | 192.800 s | 1.387 ms | 103.8 MB |
| 500 | 501 | 10.657 ms | 199.137 s | 24.511 ms | 111.3 MB |

The same source also passed a five-minute feature matrix covering unchanged and edited MP4, 1.25x playback speed, MKV, WebM, M4A, plain and enhanced MP3, and enhanced WAV. All ten outputs had the requested container and codecs, and duration error stayed at or below 100 ms.

Light enhancement lowered the measured quiet-section noise floor by about 8.5 dB while retaining a safe true peak. Listening quality remains a foreground acceptance check.

The initial VP9 WebM configuration required 105.261 seconds to export the 50-second edited sample. A measured encoder comparison selected realtime VP9 with `cpu-used=6`, row multithreading, four tile columns, and automatic thread count. The final Redact feature matrix completed the same export in 12.143 seconds, an 8.67x speedup and 88.5% time reduction. Output size increased from 4.83 MB to 5.58 MB. Full-clip VMAF changed from 94.162 to 94.116, while duration, VP9 video, Opus audio, and 720p resolution remained correct.

## Representative short- and long-media results

The formal three-sample matrix completed with a private 5:00 H.264/AAC excerpt and a private 2:06:17, 1920 x 1080 HEVC/AAC video. All 24 class, cut-count, and sample checkpoints completed. The merged reports contain medians; source paths, filenames, transcripts, hashes, and speech content remain outside version control.

The short class peaked at 286.0 MB RSS. Its largest output-duration error was 74.625 ms.

| Cuts | Preview build | FFmpeg export | Output duration delta | Output size |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 10.454 ms | 0.094 s | 0 ms | 33.8 MB |
| 10 | 10.544 ms | 7.828 s | 33.764 ms | 25.9 MB |
| 100 | 10.543 ms | 10.623 s | 54.225 ms | 26.8 MB |
| 500 | 12.238 ms | 11.752 s | 74.625 ms | 29.6 MB |

The long class peaked at 1.181 GB RSS across all cases. The 500-cut samples used 1.078, 1.075, and 1.076 GB, showing no increasing trend. The initial one-pass 500-cut result had exposed 820.060 ms of container tail beyond the canonical duration. Capping the final batched concat to the speed-adjusted expected duration reduced all three formal samples to 111.060 ms. Each completed sample removed its private UUID batch workspace.

| Cuts | Preview build | FFmpeg export | Output duration delta | Output size |
| ---: | ---: | ---: | ---: | ---: |
| 0 | 12.402 ms | 21:00.598 | 0 ms | 4.134 GB |
| 10 | 13.816 ms | 12:03.493 | 0.524 ms | 2.206 GB |
| 100 | 12.905 ms | 12:20.815 | 0.378 ms | 2.092 GB |
| 500 | 15.402 ms | 11:39.773 | 111.060 ms | 2.124 GB |

The long source also carried an unnamed data stream. The first probe rejected it even though the audio and video streams were valid. The media parser now preserves unnamed non-audio/video streams as `other`, and the same file completes the benchmark. Across both classes, every median stayed within the 250 ms export-duration, 750 ms 500-cut preview, and 1.5 GB long-memory gates in `DESIGN.md`.

## Private-media procedure

Media benchmarks belong outside the repository. Use representative local files in three classes:

1. Short: roughly 2-5 minutes.
2. Medium: roughly 20-45 minutes.
3. Long: at least 90 minutes.

Run the automated cut-count matrix from the repository root, supplying one or more files you selected explicitly. A full three-class run uses:

```bash
./scripts/run-private-media-benchmarks.sh \
  --short "/absolute/path/to/short-media" \
  --medium "/absolute/path/to/medium-media" \
  --long "/absolute/path/to/long-media"
```

When a class is already complete, omit it. For example, the remaining short and long passes can run without repeating the medium benchmark:

```bash
./scripts/run-private-media-benchmarks.sh \
  --short "/absolute/path/to/short-media" \
  --long "/absolute/path/to/long-media"
```

The runner builds the release test bundle once, then measures probe, AVFoundation preview construction, FFmpeg export, output size, duration accuracy, and peak process memory at 0, 10, 100, and 500 cuts for each supplied class. It runs each scenario three times by default. Every class, cut count, and sample has its own checkpoint. Set `REDACT_BENCHMARK_RUNS=1` for a smoke test or use a value up to 10 for additional samples.

If a run stops, resume the same output directory with the same media arguments and run settings. Completed checkpoints are validated and skipped; missing or failed samples run again. The runner rebuilds the per-class medians and `summary.json` from the complete checkpoint set.

```bash
REDACT_BENCHMARK_RUNS=3 REDACT_BENCHMARK_CUT_COUNTS=0,10,100,500 \
  ./scripts/run-private-media-benchmarks.sh \
  --short "/absolute/path/to/short-media" \
  --long "/absolute/path/to/long-media" \
  --resume "/absolute/path/to/private/results"
```

`REDACT_BENCHMARK_CUT_COUNTS` may be an ordered subset of `0,10,100,500` when starting a deliberately scoped run. A resumed run must use the same cut counts and sample count as the original checkpoint state.

Results default to a timestamped folder under the gitignored `work/benchmarks/` directory. Files and directories are owner-only. Reports contain aggregate media properties and timings, not source paths, filenames, transcript text, media hashes, or speech excerpts. The runner rejects its output if a supplied source path or filename appears in any generated artifact.

For each class, record the media duration, resolution, video codec, audio codec, file size, transcript word count, and cut count. Measure:

- import probe time;
- time to first transcript text;
- total transcription time;
- project reopen time with and without cache;
- preview-plan or composition rebuild time at 0, 10, 100, and 500 cuts;
- export wall time and output size at the same cut counts;
- peak memory during transcription, transcript interaction, preview rebuild, and export.

Store raw results under `work/benchmarks/` or another private, gitignored location. Record only anonymized aggregate measurements in tracked documentation. Never copy source media, transcripts, filenames, file paths, or speech excerpts into the repository.

Before comparing media results, capture the Redact commit, macOS version, hardware, build configuration, Whisper model, and FFmpeg version. Run each scenario three times and report the median, noting whether caches were warm or cold.
