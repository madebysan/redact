#!/bin/bash
# README screenshots for Redact, captured from the real app in a known state.
#
#   scripts/readme-screenshots.sh           capture from committed sources
#   scripts/readme-screenshots.sh --draft   allow uncommitted sources (labelled draft)
#
# Builds the Debug app (its screenshot mode is Debug-only), fetches the public-domain
# His Girl Friday (1940) trailer as demo media, then launches one
# state at a time and captures that process's windows by ID, so nothing else on the
# screen can appear. Writes assets/screenshot.png (README hero), assets/screenshot-cleanup.png
# and assets/screenshot-agent.png (docs), compresses them with oxipng, and records
# assets/screenshots-provenance.json.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/.build/readme-screenshots"
OUT="$ROOT/assets"
DRAFT=false
[ "${1:-}" = "--draft" ] && DRAFT=true
mkdir -p "$WORK" "$OUT"
cd "$ROOT"

# 1. Known source
if [ -n "$(git status --porcelain -- Sources Package.swift scripts/readme-screenshots scripts/readme-screenshots.sh)" ] && ! $DRAFT; then
    echo "Uncommitted changes in capture inputs; commit them or run with --draft." >&2
    git status --short -- Sources Package.swift scripts/readme-screenshots >&2
    exit 1
fi
COMMIT="$(git rev-parse --short HEAD)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Sources/Info.plist)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Sources/Info.plist)"
echo "Redact $VERSION ($BUILD) at $COMMIT on $(git branch --show-current)$($DRAFT && echo ', DRAFT')"

# 2. Demo clip: the public-domain His Girl Friday (1940) trailer from Wikimedia Commons
#    (source and status in THIRD_PARTY_NOTICES.md), verified against Commons' SHA-1 and
#    converted to MP4 because AVFoundation, which runs the preview, cannot play WebM.
#    The clip stays in .build and is never committed; only the screenshots are.
MEDIA="$WORK/media"
SOURCE_URL="https://upload.wikimedia.org/wikipedia/commons/c/ca/His_Girl_Friday_%281940%29_by_Howard_Hawks%2C_Trailer.webm"
SOURCE_SHA1="ecf64801a715e96503a3aea2d46e247962614036"
SOURCE="$MEDIA/his-girl-friday-trailer-long.webm"
CLIP="$MEDIA/his-girl-friday-trailer-long.mp4"
mkdir -p "$MEDIA"
if [ ! -f "$SOURCE" ] || [ "$(shasum -a 1 "$SOURCE" | cut -d' ' -f1)" != "$SOURCE_SHA1" ]; then
    curl -fsSL --max-time 300 -o "$SOURCE.part" "$SOURCE_URL"
    [ "$(shasum -a 1 "$SOURCE.part" | cut -d' ' -f1)" = "$SOURCE_SHA1" ] || { echo "Trailer checksum mismatch; not using it." >&2; exit 1; }
    mv "$SOURCE.part" "$SOURCE"
    rm -f "$CLIP"
fi
if [ ! -f "$CLIP" ]; then
    ffmpeg -y -loglevel error -i "$SOURCE" -vf "scale=1280:-2" -c:v libx264 -crf 22 -pix_fmt yuv420p -c:a aac -b:a 160k "$CLIP"
fi

# 3. Build the Debug app and the window lister
swift build -c debug > "$WORK/build.log" 2>&1 || { tail -20 "$WORK/build.log" >&2; exit 1; }
APP="$ROOT/.build/debug/Redact"
swiftc -O scripts/readme-screenshots/windows.swift -o "$WORK/windows" 2>/dev/null

# 4. One launch per state
capture() {
    local state="$1" ready="$WORK/ready-$1"
    rm -f "$ready"
    REDACT_SCREENSHOT_MEDIA="$CLIP" REDACT_SCREENSHOT_READY="$ready" \
        "$APP" -RedactScreenshotState "$state" -welcomeWalkthroughDoNotShowAgain YES -ApplePersistenceIgnoreState YES \
        > "$WORK/$state.log" 2>&1 &
    local pid=$!
    for _ in $(seq 1 240); do [ -f "$ready" ] && break; sleep 0.5; done
    if [ ! -f "$ready" ]; then kill "$pid" 2>/dev/null; echo "$state: never became ready (log: $WORK/$state.log)" >&2; return 1; fi
    # The main window is the largest; a sheet is the other one.
    local windows; windows="$("$WORK/windows" "$pid" | sort -t$'\t' -k2 -V)"
    local main sheet
    main="$(printf '%s\n' "$windows" | awk -F'\t' '{split($2,s,"x"); a=s[1]*s[2]; if (a>m) {m=a; id=$1}} END {print id}')"
    if [ "$state" = editing ]; then
        screencapture -x -o -l "$main" "$OUT/screenshot.png"
    else
        sheet="$(printf '%s\n' "$windows" | awk -F'\t' -v main="$main" '$1 != main {print $1; exit}')"
        [ -n "$sheet" ] || { kill "$pid"; echo "$state: no sheet window" >&2; return 1; }
        screencapture -x -o -l "$sheet" "$OUT/screenshot-$state.png"
    fi
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
    local file="$OUT/screenshot-$state.png"; [ "$state" = editing ] && file="$OUT/screenshot.png"
    oxipng -q -o 4 --strip safe "$file"
    echo "  $(basename "$file")  $(sips -g pixelWidth -g pixelHeight "$file" | awk '/pixel/ {printf "%s ", $2}')$(( $(stat -f%z "$file") / 1024 )) KB"
}
for state in editing cleanup agent; do capture "$state"; done

# 5. Provenance
python3 - "$OUT" "$ROOT/assets/screenshots-provenance.json" "$COMMIT" "$VERSION" "$BUILD" "$DRAFT" <<'PY'
import hashlib, json, os, sys, platform, subprocess
out, path, commit, version, build, draft = sys.argv[1:]
files = {f: hashlib.sha256(open(os.path.join(out, f), "rb").read()).hexdigest() for f in sorted(os.listdir(out)) if f.startswith("screenshot") and f.endswith(".png")}
json.dump({"commit": commit, "version": version, "build": build, "draft": draft == "true",
           "macos": subprocess.run(["sw_vers", "-productVersion"], capture_output=True, text=True).stdout.strip(),
           "window_points": "1280x800", "files": files}, open(path, "w"), indent=2)
print("provenance:", os.path.relpath(path))
PY
