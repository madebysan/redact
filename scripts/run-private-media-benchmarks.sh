#!/bin/bash

set -euo pipefail
shopt -s nullglob

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT=""
RESUME_ROOT=""
SHORT_MEDIA=""
MEDIUM_MEDIA=""
LONG_MEDIA=""
RUNS="${REDACT_BENCHMARK_RUNS:-3}"
CUT_COUNTS="${REDACT_BENCHMARK_CUT_COUNTS:-0,10,100,500}"
REPORT_FILES=()
REQUESTED_CLASSES=()

usage() {
    echo "Usage: $0 [--short /path/file] [--medium /path/file] [--long /path/file] [--output /private/results | --resume /private/results]" >&2
    echo "Provide at least one representative-media class." >&2
    exit 2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --short)
            [ "$#" -ge 2 ] || usage
            SHORT_MEDIA="$2"
            shift 2
            ;;
        --medium)
            [ "$#" -ge 2 ] || usage
            MEDIUM_MEDIA="$2"
            shift 2
            ;;
        --long)
            [ "$#" -ge 2 ] || usage
            LONG_MEDIA="$2"
            shift 2
            ;;
        --output)
            [ "$#" -ge 2 ] || usage
            OUTPUT_ROOT="$2"
            shift 2
            ;;
        --resume)
            [ "$#" -ge 2 ] || usage
            RESUME_ROOT="$2"
            shift 2
            ;;
        *) usage ;;
    esac
done

if [ -z "$SHORT_MEDIA" ] && [ -z "$MEDIUM_MEDIA" ] && [ -z "$LONG_MEDIA" ]; then
    usage
fi
if [ -n "$OUTPUT_ROOT" ] && [ -n "$RESUME_ROOT" ]; then
    echo "ERROR: Use either --output for a new run or --resume for an existing run, not both." >&2
    exit 2
fi
[[ "$RUNS" =~ ^[1-9][0-9]*$ ]] || { echo "ERROR: REDACT_BENCHMARK_RUNS must be a positive integer." >&2; exit 2; }
[ "$RUNS" -le 10 ] || { echo "ERROR: REDACT_BENCHMARK_RUNS must not exceed 10." >&2; exit 2; }
[[ "$CUT_COUNTS" =~ ^(0(,10)?(,100)?(,500)?|10(,100)?(,500)?|100(,500)?|500)$ ]] || {
    echo "ERROR: REDACT_BENCHMARK_CUT_COUNTS must be an ordered subset of 0,10,100,500." >&2
    exit 2
}

[ -z "$SHORT_MEDIA" ] || REQUESTED_CLASSES+=("short")
[ -z "$MEDIUM_MEDIA" ] || REQUESTED_CLASSES+=("medium")
[ -z "$LONG_MEDIA" ] || REQUESTED_CLASSES+=("long")

for required_command in ffmpeg jq swift trash; do
    command -v "$required_command" >/dev/null || { echo "ERROR: Missing required command: $required_command" >&2; exit 1; }
done

STATE_FILE=""
CONTEXT_FILE=""
if [ -n "$RESUME_ROOT" ]; then
    OUTPUT_ROOT="$RESUME_ROOT"
    [ -d "$OUTPUT_ROOT" ] || { echo "ERROR: Resume directory does not exist." >&2; exit 1; }
    STATE_FILE="$OUTPUT_ROOT/checkpoint-state.json"
    CONTEXT_FILE="$OUTPUT_ROOT/context.json"
    [ -f "$STATE_FILE" ] && [ -f "$CONTEXT_FILE" ] || {
        echo "ERROR: Resume directory is missing checkpoint-state.json or context.json." >&2
        exit 1
    }
    jq -e --argjson runs "$RUNS" --arg cuts "$CUT_COUNTS" '
        .schemaVersion == 1
        and .runsPerCutCount == $runs
        and .cutCounts == ($cuts | split(",") | map(tonumber))
    ' "$STATE_FILE" >/dev/null || {
        echo "ERROR: Resume settings do not match the original run count and cut counts." >&2
        exit 1
    }
    for label in "${REQUESTED_CLASSES[@]}"; do
        jq -e --arg label "$label" '.classes | index($label) != null' "$STATE_FILE" >/dev/null || {
            echo "ERROR: The resumed run was not configured for the $label class." >&2
            exit 1
        }
    done
else
    if [ -z "$OUTPUT_ROOT" ]; then
        OUTPUT_ROOT="$PROJECT_DIR/work/benchmarks/$(date -u +%Y%m%dT%H%M%SZ)"
    fi
    if [ -e "$OUTPUT_ROOT" ]; then
        echo "ERROR: Output path already exists. Use --resume to continue it." >&2
        exit 1
    fi
    mkdir -p "$OUTPUT_ROOT"
    chmod 700 "$OUTPUT_ROOT"
    STATE_FILE="$OUTPUT_ROOT/checkpoint-state.json"
    CONTEXT_FILE="$OUTPUT_ROOT/context.json"

    class_csv="$(IFS=,; echo "${REQUESTED_CLASSES[*]}")"
    jq -n \
        --arg classes "$class_csv" \
        --arg cuts "$CUT_COUNTS" \
        --argjson runs "$RUNS" '
        ($classes | split(",")) as $classList
        | ($cuts | split(",") | map(tonumber)) as $cutList
        | {
            schemaVersion: 1,
            classes: $classList,
            cutCounts: $cutList,
            runsPerCutCount: $runs,
            attempts: [
                $classList[] as $label
                | $cutList[] as $cut
                | range(1; $runs + 1) as $run
                | {
                    label: $label,
                    cutCount: $cut,
                    run: $run,
                    status: "pending",
                    attemptCount: 0,
                    updatedAt: null
                }
            ]
        }
    ' > "$STATE_FILE"
    chmod 600 "$STATE_FILE"

    jq -n \
        --arg commit "$(git -C "$PROJECT_DIR" rev-parse HEAD)" \
        --arg macOS "$(sw_vers -productVersion)" \
        --arg hardware "$(sysctl -n machdep.cpu.brand_string)" \
        --arg memoryBytes "$(sysctl -n hw.memsize)" \
        --arg ffmpeg "$(ffmpeg -hide_banner -version | head -n 1)" \
        --arg runs "$RUNS" \
        --arg cutCounts "$CUT_COUNTS" \
        '{
            schemaVersion: 1,
            commit: $commit,
            macOS: $macOS,
            hardware: $hardware,
            memoryBytes: ($memoryBytes | tonumber),
            ffmpeg: $ffmpeg,
            buildConfiguration: "release",
            runsPerCutCount: ($runs | tonumber),
            cutCounts: ($cutCounts | split(",") | map(tonumber))
        }' > "$CONTEXT_FILE"
    chmod 600 "$CONTEXT_FILE"
fi

preflight_media() {
    local label="$1"
    local source="$2"
    [ -f "$source" ] || { echo "ERROR: $label media is not a readable file." >&2; exit 1; }
    [ -r "$source" ] || { echo "ERROR: $label media is not readable." >&2; exit 1; }

    local source_bytes available_kb required_kb
    source_bytes="$(stat -f '%z' "$source")"
    available_kb="$(df -k "$OUTPUT_ROOT" | awk 'NR == 2 {print $4}')"
    required_kb="$((source_bytes / 512 + 5 * 1024 * 1024))"
    if [ "$available_kb" -lt "$required_kb" ]; then
        echo "ERROR: Not enough free space for the $label benchmark. Keep at least twice the source size plus 5 GB free." >&2
        exit 1
    fi
}

[ -z "$SHORT_MEDIA" ] || preflight_media short "$SHORT_MEDIA"
[ -z "$MEDIUM_MEDIA" ] || preflight_media medium "$MEDIUM_MEDIA"
[ -z "$LONG_MEDIA" ] || preflight_media long "$LONG_MEDIA"

update_attempt() {
    local label="$1"
    local cut_count="$2"
    local run_index="$3"
    local status="$4"
    local increment="$5"
    local temporary_state="$STATE_FILE.tmp"
    jq \
        --arg label "$label" \
        --argjson cut "$cut_count" \
        --argjson run "$run_index" \
        --arg status "$status" \
        --argjson increment "$increment" \
        --arg updatedAt "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .attempts |= map(
            if .label == $label and .cutCount == $cut and .run == $run then
                .status = $status
                | .attemptCount += $increment
                | .updatedAt = $updatedAt
            else . end
        )
    ' "$STATE_FILE" > "$temporary_state"
    mv "$temporary_state" "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

checkpoint_is_valid() {
    local report="$1"
    local label="$2"
    local cut_count="$3"
    jq -e \
        --arg label "$label" \
        --argjson cut "$cut_count" '
        .schemaVersion == 1
        and .label == $label
        and .runsPerCutCount == 1
        and (.results | length == 1)
        and .results[0].cutCount == $cut
        and .peakProcessResidentBytes > 0
    ' "$report" >/dev/null 2>&1
}

artifacts_are_private() {
    local source="$1"
    if grep -FRq -- "$(basename "$source")" "$OUTPUT_ROOT"; then
        return 1
    fi
    if grep -FRq -- "$source" "$OUTPUT_ROOT"; then
        return 1
    fi
    return 0
}

matches_existing_source() {
    local candidate="$1"
    local label="$2"
    local existing_reports=("$OUTPUT_ROOT/checkpoints/$label"/cut-*/run-*/report.json)
    [ "${#existing_reports[@]}" -eq 0 ] && return 0
    jq -e --slurpfile previous "${existing_reports[0]}" '
        .durationSeconds == $previous[0].durationSeconds
        and .sourceSizeBytes == $previous[0].sourceSizeBytes
        and .containers == $previous[0].containers
        and .video == $previous[0].video
        and .audio == $previous[0].audio
    ' "$candidate" >/dev/null
}

run_checkpoint() {
    local label="$1"
    local source="$2"
    local cut_count="$3"
    local run_index="$4"
    local checkpoint_dir="$OUTPUT_ROOT/checkpoints/$label/cut-$cut_count/run-$run_index"
    local report="$checkpoint_dir/report.json"

    if [ -f "$report" ] && checkpoint_is_valid "$report" "$label" "$cut_count"; then
        update_attempt "$label" "$cut_count" "$run_index" completed 0
        echo "Skipping completed $label cut=$cut_count run=$run_index checkpoint."
        return
    fi

    mkdir -p "$checkpoint_dir"
    chmod 700 "$OUTPUT_ROOT/checkpoints" "$OUTPUT_ROOT/checkpoints/$label" \
        "$OUTPUT_ROOT/checkpoints/$label/cut-$cut_count" "$checkpoint_dir"
    update_attempt "$label" "$cut_count" "$run_index" running 1
    local attempt_count
    attempt_count="$(jq -r \
        --arg label "$label" \
        --argjson cut "$cut_count" \
        --argjson run "$run_index" '
        .attempts[] | select(.label == $label and .cutCount == $cut and .run == $run) | .attemptCount
    ' "$STATE_FILE")"
    local temporary_report="$checkpoint_dir/report.tmp.json"
    local measured_report="$checkpoint_dir/report.measured.json"
    local log="$checkpoint_dir/attempt-$attempt_count.log"

    echo "Running $label cut=$cut_count run=$run_index (attempt $attempt_count)..."
    if ! /usr/bin/time -l env \
        RUN_REDACT_REPRESENTATIVE_BENCHMARKS=1 \
        REDACT_REPRESENTATIVE_MEDIA="$source" \
        REDACT_REPRESENTATIVE_LABEL="$label" \
        REDACT_REPRESENTATIVE_OUTPUT="$temporary_report" \
        REDACT_REPRESENTATIVE_RUNS=1 \
        REDACT_REPRESENTATIVE_CUT_COUNTS="$cut_count" \
        swift test -c release --skip-build --filter representativeMediaCutCountBenchmark \
        >"$log" 2>&1; then
        update_attempt "$label" "$cut_count" "$run_index" failed 0
        if ! artifacts_are_private "$source"; then
            trash "$log" "$temporary_report" 2>/dev/null || true
        fi
        echo "ERROR: $label cut=$cut_count run=$run_index failed. Resume the same output directory to retry it." >&2
        exit 1
    fi

    [ -f "$temporary_report" ] || {
        update_attempt "$label" "$cut_count" "$run_index" failed 0
        echo "ERROR: $label cut=$cut_count run=$run_index did not produce a report." >&2
        exit 1
    }
    local peak_bytes
    peak_bytes="$(awk '/maximum resident set size/ {print $1}' "$log" | tail -n 1)"
    [[ "$peak_bytes" =~ ^[0-9]+$ ]] || {
        update_attempt "$label" "$cut_count" "$run_index" failed 0
        echo "ERROR: Could not read peak memory for $label cut=$cut_count run=$run_index." >&2
        exit 1
    }
    jq --argjson peak "$peak_bytes" '. + {peakProcessResidentBytes: $peak}' \
        "$temporary_report" > "$measured_report"

    if ! checkpoint_is_valid "$measured_report" "$label" "$cut_count"; then
        update_attempt "$label" "$cut_count" "$run_index" failed 0
        echo "ERROR: $label cut=$cut_count run=$run_index produced an invalid report." >&2
        exit 1
    fi
    if ! matches_existing_source "$measured_report" "$label"; then
        update_attempt "$label" "$cut_count" "$run_index" failed 0
        echo "ERROR: The $label source does not match earlier checkpoints in this run." >&2
        exit 1
    fi

    mv "$measured_report" "$report"
    trash "$temporary_report" 2>/dev/null || true
    chmod 600 "$report" "$log"
    if ! artifacts_are_private "$source"; then
        update_attempt "$label" "$cut_count" "$run_index" failed 0
        trash "$report" "$log" 2>/dev/null || true
        echo "ERROR: Benchmark artifacts contained a private source path or filename." >&2
        exit 1
    fi
    update_attempt "$label" "$cut_count" "$run_index" completed 0
    echo "Completed $label cut=$cut_count run=$run_index."
}

cd "$PROJECT_DIR"
swift test -c release --filter representativeMediaCutCountBenchmark >/dev/null

IFS=',' read -r -a CUT_COUNT_ARRAY <<< "$CUT_COUNTS"
run_label() {
    local label="$1"
    local source="$2"
    local cut_count run_index
    for cut_count in "${CUT_COUNT_ARRAY[@]}"; do
        for ((run_index = 1; run_index <= RUNS; run_index++)); do
            run_checkpoint "$label" "$source" "$cut_count" "$run_index"
        done
    done
}

[ -z "$SHORT_MEDIA" ] || run_label short "$SHORT_MEDIA"
[ -z "$MEDIUM_MEDIA" ] || run_label medium "$MEDIUM_MEDIA"
[ -z "$LONG_MEDIA" ] || run_label long "$LONG_MEDIA"

merge_label() {
    local label="$1"
    local reports=("$OUTPUT_ROOT/checkpoints/$label"/cut-*/run-*/report.json)
    local expected_count="$(( ${#CUT_COUNT_ARRAY[@]} * RUNS ))"
    if [ "${#reports[@]}" -ne "$expected_count" ]; then
        return 1
    fi

    local merged="$OUTPUT_ROOT/$label-media.json"
    jq -s \
        --arg label "$label" \
        --arg cuts "$CUT_COUNTS" \
        --argjson runs "$RUNS" '
        def median:
            sort as $values
            | ($values | length) as $count
            | if ($count % 2) == 1 then
                $values[($count / 2 | floor)]
              else
                (($values[$count / 2 - 1] + $values[$count / 2]) / 2)
              end;
        . as $reports
        | .[0] as $base
        | ($cuts | split(",") | map(tonumber)) as $cutList
        | {
            schemaVersion: 1,
            label: $label,
            durationSeconds: $base.durationSeconds,
            sourceSizeBytes: $base.sourceSizeBytes,
            containers: $base.containers,
            video: $base.video,
            audio: $base.audio,
            probeMedianMilliseconds: ($reports | map(.probeMedianMilliseconds) | median),
            runsPerCutCount: $runs,
            peakProcessResidentBytes: ($reports | map(.peakProcessResidentBytes) | max),
            results: [
                $cutList[] as $cut
                | [$reports[] | .results[] | select(.cutCount == $cut)] as $rows
                | select(($rows | length) == $runs)
                | {
                    cutCount: $cut,
                    keptRangeCount: $rows[0].keptRangeCount,
                    expectedDurationSeconds: ($rows | map(.expectedDurationSeconds) | median),
                    previewDurationSeconds: ($rows | map(.previewDurationSeconds) | median),
                    outputDurationSeconds: ($rows | map(.outputDurationSeconds) | median),
                    previewDurationDeltaSeconds: ($rows | map(.previewDurationDeltaSeconds) | median),
                    outputDurationDeltaSeconds: ($rows | map(.outputDurationDeltaSeconds) | median),
                    previewBuildMedianMilliseconds: ($rows | map(.previewBuildMedianMilliseconds) | median),
                    exportMedianMilliseconds: ($rows | map(.exportMedianMilliseconds) | median),
                    outputSizeMedianBytes: ($rows | map(.outputSizeMedianBytes) | median | floor)
                }
            ]
        }
    ' "${reports[@]}" > "$merged.tmp"

    jq -e \
        --arg label "$label" \
        --arg cuts "$CUT_COUNTS" \
        --argjson runs "$RUNS" '
        .schemaVersion == 1
        and .label == $label
        and .runsPerCutCount == $runs
        and (.results | map(.cutCount) == ($cuts | split(",") | map(tonumber)))
        and .peakProcessResidentBytes > 0
    ' "$merged.tmp" >/dev/null
    mv "$merged.tmp" "$merged"
    chmod 600 "$merged"
    REPORT_FILES+=("$merged")
    return 0
}

while IFS= read -r label; do
    merge_label "$label" || true
done < <(jq -r '.classes[]' "$STATE_FILE")

complete="$(jq -r 'all(.attempts[]; .status == "completed")' "$STATE_FILE")"
jq -s \
    --argjson complete "$complete" '
    .[0] as $state
    | {
        schemaVersion: 1,
        complete: $complete,
        checkpointState: $state,
        reports: .[1:]
    }
' "$STATE_FILE" "${REPORT_FILES[@]}" > "$OUTPUT_ROOT/summary.json.tmp"
mv "$OUTPUT_ROOT/summary.json.tmp" "$OUTPUT_ROOT/summary.json"
chmod 600 "$OUTPUT_ROOT/summary.json"

if [ "$complete" != "true" ]; then
    echo "Checkpointed work is incomplete. Supply the remaining media classes with --resume to continue." >&2
    exit 1
fi

echo "Selected representative-media benchmarks completed with resumable per-run checkpoints."
