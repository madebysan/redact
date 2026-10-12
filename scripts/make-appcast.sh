#!/bin/bash
# Writes the Sparkle update feed (appcast.xml) for one release.
#
# Usage:
#   ./scripts/make-appcast.sh <notarized.dmg> <download-url> <release-notes.md> [output.xml]
#
# The DMG is signed with the EdDSA key stored in the login keychain (created
# once with Sparkle's generate_keys). Upload the DMG and appcast.xml to the
# same GitHub release: Info.plist's SUFeedURL reads appcast.xml from the
# latest release, so publishing a release is what makes the update available.

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_UPDATE="${PROJECT_DIR}/.build/artifacts/sparkle/Sparkle/bin/sign_update"

DMG_PATH="${1:?usage: make-appcast.sh <dmg> <download-url> <release-notes.md> [output.xml]}"
DOWNLOAD_URL="${2:?missing download URL}"
NOTES_PATH="${3:?missing release notes file}"
OUTPUT="${4:-$(dirname "${DMG_PATH}")/appcast.xml}"

[ -f "${DMG_PATH}" ] || { echo "ERROR: DMG not found: ${DMG_PATH}" >&2; exit 1; }
[ -f "${NOTES_PATH}" ] || { echo "ERROR: Release notes not found: ${NOTES_PATH}" >&2; exit 1; }
[ -x "${SIGN_UPDATE}" ] || { echo "ERROR: Run 'swift package resolve' first; sign_update not found." >&2; exit 1; }
if grep -q ']]>' "${NOTES_PATH}"; then
    echo "ERROR: Release notes cannot contain ']]>'." >&2
    exit 1
fi

# Read the version from the app inside the DMG, so the feed always describes
# exactly what users will download.
MOUNT_ROOT="$(mktemp -d /tmp/redact-appcast.XXXXXX)"
cleanup() {
    hdiutil detach "${MOUNT_ROOT}" -quiet 2>/dev/null || true
    rmdir "${MOUNT_ROOT}" 2>/dev/null || true
}
trap cleanup EXIT
hdiutil attach -readonly -nobrowse -mountpoint "${MOUNT_ROOT}" "${DMG_PATH}" >/dev/null
INFO_PLIST="${MOUNT_ROOT}/Redact.app/Contents/Info.plist"
[ -f "${INFO_PLIST}" ] || { echo "ERROR: Redact.app not found in ${DMG_PATH}" >&2; exit 1; }

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
MIN_SYSTEM="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "${INFO_PLIST}")"
FEED_URL="$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "${INFO_PLIST}")"
cleanup
trap - EXIT

# Prints: sparkle:edSignature="..." length="..."
SIGNATURE_ATTRIBUTES="$("${SIGN_UPDATE}" "${DMG_PATH}")"
PUB_DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"

cat > "${OUTPUT}" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>Redact</title>
        <link>${FEED_URL}</link>
        <item>
            <title>Redact ${APP_VERSION}</title>
            <pubDate>${PUB_DATE}</pubDate>
            <sparkle:version>${APP_BUILD}</sparkle:version>
            <sparkle:shortVersionString>${APP_VERSION}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>${MIN_SYSTEM}</sparkle:minimumSystemVersion>
            <sparkle:fullReleaseNotesLink>https://github.com/madebysan/redact/releases</sparkle:fullReleaseNotesLink>
            <description sparkle:format="markdown"><![CDATA[
$(cat "${NOTES_PATH}")
]]></description>
            <enclosure url="${DOWNLOAD_URL}" type="application/octet-stream" ${SIGNATURE_ATTRIBUTES} />
        </item>
    </channel>
</rss>
EOF

xmllint --noout "${OUTPUT}"
echo "Appcast written: ${OUTPUT} (Redact ${APP_VERSION}, build ${APP_BUILD})"
