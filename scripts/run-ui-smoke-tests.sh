#!/bin/bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_BUNDLE="$PROJECT_DIR/.build/release-app/Redact.app"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Redact"
APP_PROCESS_PATTERN="^${APP_EXECUTABLE}( |$)"
TEST_SCRIPT="$PROJECT_DIR/Tests/UI/RedactUISmokeTests.applescript"
PROJECT_TEST_SCRIPT="$PROJECT_DIR/Tests/UI/RedactProjectSmokeTests.applescript"
PERSISTENCE_TEST_SCRIPT="$PROJECT_DIR/Tests/UI/RedactPersistenceSmokeTests.applescript"
REOPEN_TEST_SCRIPT="$PROJECT_DIR/Tests/UI/RedactReopenSmokeTests.applescript"
EXPORT_TEST_SCRIPT="$PROJECT_DIR/Tests/UI/RedactExportSmokeTests.applescript"
CLEANUP_TEST_SCRIPT="$PROJECT_DIR/Tests/UI/RedactCleanupSmokeTests.applescript"
RELINK_TEST_SCRIPT="$PROJECT_DIR/Tests/UI/RedactRelinkSmokeTests.applescript"
FIXTURE_DIR="$PROJECT_DIR/.build/ui-smoke-fixtures"
MEDIA_FILE="$FIXTURE_DIR/sample.mov"
PROJECT_FILE="$FIXTURE_DIR/sample.rdt"
CLEANUP_PROJECT_FILE="$FIXTURE_DIR/cleanup.rdt"
MISSING_DIR="$FIXTURE_DIR/missing"
MISSING_PROJECT_FILE="$MISSING_DIR/missing.rdt"
OUTPUT_DIR="$PROJECT_DIR/.build/ui-smoke-output"

cleanup() {
    local running_pids
    running_pids="$(pgrep -f "$APP_PROCESS_PATTERN" || true)"
    if [ -n "$running_pids" ]; then
        while IFS= read -r running_pid; do
            kill "$running_pid" 2>/dev/null || true
        done <<< "$running_pids"
    fi
    for _ in {1..50}; do
        if ! pgrep -f "$APP_PROCESS_PATTERN" >/dev/null; then
            break
        fi
        sleep 0.1
    done
}
trap cleanup EXIT

launch_app() {
    open -n "$APP_BUNDLE" --args \
        -ApplePersistenceIgnoreState YES \
        -welcomeWalkthroughDoNotShowAgain YES \
        -exportPresetID mp4-video \
        -exportSpeed 1 \
        -exportEnhanceAudio NO \
        -exportSubtitles NO
    app_pid=""
    for _ in {1..50}; do
        app_pid="$(pgrep -n -f "$APP_PROCESS_PATTERN" || true)"
        if [ -n "$app_pid" ]; then
            break
        fi
        sleep 0.1
    done

    if [ -z "$app_pid" ]; then
        echo "FAIL: Redact process did not launch" >&2
        exit 1
    fi
}

open_project() {
    local project_file="$1"
    open -a "$APP_BUNDLE" "$project_file"
    osascript - "$app_pid" <<'APPLESCRIPT'
on run arguments
    set appPID to (item 1 of arguments) as integer

    tell application "System Events"
        tell first process whose unix id is appPID
            repeat 100 times
                if exists first window whose name is not "Untitled" then exit repeat
                delay 0.1
            end repeat
            if not (exists first window whose name is not "Untitled") then error "Project window did not open"

            if exists window "Untitled" then
                perform action "AXPress" of (value of attribute "AXCloseButton" of window "Untitled")
            end if
            repeat 50 times
                if not (exists window "Untitled") then exit repeat
                delay 0.1
            end repeat
            if exists window "Untitled" then error "Untitled window did not close"
        end tell
    end tell
end run
APPLESCRIPT
}

cd "$PROJECT_DIR"
./scripts/build-release.sh build

mkdir -p "$FIXTURE_DIR"
mkdir -p "$MISSING_DIR" "$OUTPUT_DIR"
rm -f \
    "$OUTPUT_DIR/smoke-subtitles.srt" \
    "$OUTPUT_DIR/smoke-video.mp4" \
    "$OUTPUT_DIR/smoke-video.mp4.mp3" \
    "$OUTPUT_DIR/smoke-audio.mp3"
ffmpeg \
    -hide_banner -loglevel error -y \
    -f lavfi -i "testsrc2=size=640x360:rate=30" \
    -f lavfi -i "sine=frequency=440:sample_rate=48000" \
    -t 4 \
    -c:v h264_videotoolbox -b:v 1M \
    -c:a aac -shortest \
    "$MEDIA_FILE"

jq -n --arg media "$MEDIA_FILE" '{
    version: 1,
    videoFile: "sample.mov",
    videoPath: $media,
    language: "en",
    duration: 4,
    segments: [{
        id: 0,
        words: [
            {id: "w_0", word: "Redact", start: 0.2, end: 0.8, confidence: 0.99, deleted: false},
            {id: "w_1", word: "makes", start: 0.9, end: 1.3, confidence: 0.99, deleted: false},
            {id: "w_2", word: "editing", start: 1.4, end: 2.0, confidence: 0.99, deleted: false},
            {id: "w_3", word: "direct.", start: 2.1, end: 2.8, confidence: 0.99, deleted: false}
        ]
    }]
}' > "$PROJECT_FILE"

jq -n --arg media "$MEDIA_FILE" '{
    version: 1,
    videoFile: "sample.mov",
    videoPath: $media,
    language: "en",
    duration: 4,
    segments: [{
        id: 0,
        words: [
            {id: "cleanup_filler", word: "um", start: 0.1, end: 0.3, confidence: 0.99, deleted: false},
            {id: "cleanup_repeat_1", word: "Redact", start: 0.4, end: 0.7, confidence: 0.99, deleted: false},
            {id: "cleanup_repeat_2", word: "Redact", start: 0.75, end: 1.05, confidence: 0.99, deleted: false},
            {id: "cleanup_silence_1", word: "—", start: 1.1, end: 1.6, confidence: 1, deleted: false, isSilence: true},
            {id: "cleanup_silence_2", word: "—", start: 1.6, end: 2.1, confidence: 1, deleted: false, isSilence: true},
            {id: "cleanup_silence_3", word: "—", start: 2.1, end: 2.6, confidence: 1, deleted: false, isSilence: true},
            {id: "cleanup_end", word: "works.", start: 2.7, end: 3.1, confidence: 0.99, deleted: false}
        ]
    }]
}' > "$CLEANUP_PROJECT_FILE"

jq -n --arg media "$MISSING_DIR/no-longer-here.mov" '{
    version: 1,
    videoFile: "sample.mov",
    videoPath: $media,
    language: "en",
    duration: 4,
    segments: [{
        id: 0,
        words: [
            {id: "w_0", word: "Redact", start: 0.2, end: 0.8, confidence: 0.99, deleted: false},
            {id: "w_1", word: "makes", start: 0.9, end: 1.3, confidence: 0.99, deleted: false},
            {id: "w_2", word: "editing", start: 1.4, end: 2.0, confidence: 0.99, deleted: false},
            {id: "w_3", word: "direct.", start: 2.1, end: 2.8, confidence: 0.99, deleted: false}
        ]
    }]
}' > "$MISSING_PROJECT_FILE"

cleanup
launch_app

osascript "$TEST_SCRIPT" "$app_pid"

open_project "$PROJECT_FILE"
osascript "$PROJECT_TEST_SCRIPT" "$app_pid"
osascript "$PERSISTENCE_TEST_SCRIPT" "$app_pid"

for _ in {1..50}; do
    if jq -e '.version == 2 and (.edits.deletedWordIDs | length) == 4' "$PROJECT_FILE" >/dev/null; then
        break
    fi
    sleep 0.1
done
jq -e '.version == 2 and (.edits.deletedWordIDs | length) == 4' "$PROJECT_FILE" >/dev/null

cleanup
launch_app
open_project "$PROJECT_FILE"
osascript "$REOPEN_TEST_SCRIPT" "$app_pid"
jq -e '.version == 2 and (.edits.deletedWordIDs | length) == 0' "$PROJECT_FILE" >/dev/null

osascript "$EXPORT_TEST_SCRIPT" "$app_pid" "$OUTPUT_DIR"
test -s "$OUTPUT_DIR/smoke-subtitles.srt"
grep -q "Redact makes editing direct." "$OUTPUT_DIR/smoke-subtitles.srt"
test -s "$OUTPUT_DIR/smoke-video.mp4"
test -s "$OUTPUT_DIR/smoke-audio.mp3"
ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$OUTPUT_DIR/smoke-video.mp4" | grep -q '^video$'
ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$OUTPUT_DIR/smoke-video.mp4" | grep -q '^audio$'
ffprobe -v error -show_entries stream=codec_type -of csv=p=0 "$OUTPUT_DIR/smoke-audio.mp3" | grep -q '^audio$'

kill "$app_pid"
for _ in {1..50}; do
    if ! kill -0 "$app_pid" 2>/dev/null; then
        break
    fi
    sleep 0.1
done
if kill -0 "$app_pid" 2>/dev/null; then
    echo "FAIL: Redact test process did not terminate before cleanup test" >&2
    exit 1
fi

launch_app
open_project "$CLEANUP_PROJECT_FILE"
osascript "$CLEANUP_TEST_SCRIPT" "$app_pid"
jq -e '.version == 2 and (.edits.deletedWordIDs | sort) == ["cleanup_filler", "cleanup_repeat_1", "cleanup_silence_1", "cleanup_silence_2"]' "$CLEANUP_PROJECT_FILE" >/dev/null

kill "$app_pid"
for _ in {1..50}; do
    if ! kill -0 "$app_pid" 2>/dev/null; then
        break
    fi
    sleep 0.1
done
if kill -0 "$app_pid" 2>/dev/null; then
    echo "FAIL: Redact test process did not terminate before relink test" >&2
    exit 1
fi

launch_app
open_project "$MISSING_PROJECT_FILE"
osascript "$RELINK_TEST_SCRIPT" "$app_pid" "$MEDIA_FILE"
jq -e '.version == 2 and .media.displayName == "sample.mov" and .media.relativePath == "../sample.mov"' "$MISSING_PROJECT_FILE" >/dev/null
