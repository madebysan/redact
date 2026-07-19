#!/bin/bash

set -euo pipefail

APP_BUNDLE="${1:-}"
DMG_PATH="${2:-}"
EXPECTED_BUNDLE_ID="com.santiagoalonso.redact"

fail() {
    echo "ERROR: $1" >&2
    exit 1
}

if [ -z "$APP_BUNDLE" ] || [ ! -d "$APP_BUNDLE" ]; then
    fail "Usage: $0 /path/to/Redact.app [/path/to/Redact.dmg]"
fi

INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXECUTABLE="$APP_BUNDLE/Contents/MacOS/Redact"

plutil -lint "$INFO_PLIST" >/dev/null || fail "Info.plist is invalid"
[ -x "$EXECUTABLE" ] || fail "Redact executable is missing or not executable"

BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
[ "$BUNDLE_ID" = "$EXPECTED_BUNDLE_ID" ] || fail "Unexpected bundle identifier: $BUNDLE_ID"

codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"

SIGNATURE_DETAILS="$(codesign -dvvv --entitlements - "$APP_BUNDLE" 2>&1)"
grep -q 'Authority=Developer ID Application:' <<< "$SIGNATURE_DETAILS" \
    || fail "App is not signed with Developer ID Application"
grep -q 'flags=.*runtime' <<< "$SIGNATURE_DETAILS" \
    || fail "Hardened runtime is not enabled"
grep -q '^Timestamp=' <<< "$SIGNATURE_DETAILS" \
    || fail "Secure timestamp is missing"
if grep -q 'com.apple.security.get-task-allow' <<< "$SIGNATURE_DETAILS"; then
    fail "Distribution signature includes get-task-allow"
fi
if grep -q 'com.apple.security.app-sandbox' <<< "$SIGNATURE_DETAILS"; then
    fail "Direct-distribution build must omit the App Sandbox entitlement until the sandbox migration is complete"
fi

echo "PASS: signed app structure, Developer ID, hardened runtime, timestamp, and entitlements"

if [ -z "$DMG_PATH" ]; then
    exit 0
fi

[ -f "$DMG_PATH" ] || fail "DMG not found: $DMG_PATH"
hdiutil verify "$DMG_PATH" >/dev/null
codesign --verify --verbose=4 "$DMG_PATH"

MOUNT_ROOT="$(mktemp -d /tmp/redact-dmg.XXXXXX)"
cleanup() {
    hdiutil detach "$MOUNT_ROOT" -quiet 2>/dev/null || true
    rmdir "$MOUNT_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_ROOT" "$DMG_PATH" >/dev/null
[ -d "$MOUNT_ROOT/Redact.app" ] || fail "DMG is missing Redact.app"
[ -f "$MOUNT_ROOT/README.md" ] || fail "DMG is missing README.md"
[ -f "$MOUNT_ROOT/LICENSE" ] || fail "DMG is missing LICENSE"
[ -L "$MOUNT_ROOT/Applications" ] || fail "DMG is missing the Applications symlink"
[ "$(readlink "$MOUNT_ROOT/Applications")" = "/Applications" ] \
    || fail "DMG Applications symlink has the wrong destination"
codesign --verify --deep --strict --verbose=4 "$MOUNT_ROOT/Redact.app"

echo "PASS: DMG integrity, signature, contents, and nested app signature"
