#!/bin/bash
# Build, sign, notarize, and package Redact as a .dmg
#
# Usage:
#   ./scripts/build-release.sh          # Build only (unsigned .app)
#   ./scripts/build-release.sh sign      # Build + code sign
#   ./scripts/build-release.sh dmg       # Build + sign + DMG (no notarization)
#   ./scripts/build-release.sh release   # Build + sign + notarize + DMG
#
# Prerequisites:
#   - Xcode command-line tools
#   - Developer ID certificate in keychain (for sign/release)
#   - Notary credentials stored in the existing "notarytool" keychain profile
#   - jq (for notarization result and log handling)

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build/release-app"
APP_NAME="Redact"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
INFO_PLIST="${PROJECT_DIR}/Sources/Info.plist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
APP_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
RELEASE_LABEL="${REDACT_RELEASE_LABEL:-rc.${APP_BUILD}}"
if [[ ! "${RELEASE_LABEL}" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "ERROR: REDACT_RELEASE_LABEL must use only letters, numbers, dots, dashes, or underscores." >&2
    exit 2
fi
DMG_PATH="${BUILD_DIR}/Redact-${APP_VERSION}-${RELEASE_LABEL}.dmg"
SIGNING_IDENTITY="Developer ID Application: Santiago Alonso Alexandre (QAMM2A6WRQ)"
NOTARY_PROFILE="notarytool"

MODE="${1:-build}"

case "${MODE}" in
    build|sign|dmg|release) ;;
    *)
        echo "ERROR: Unknown mode '${MODE}'. Expected build, sign, dmg, or release." >&2
        exit 2
        ;;
esac

echo "=== Redact Release Build ==="
echo "Mode: ${MODE}"
echo "Version: ${APP_VERSION} (${APP_BUILD})"
echo "Distribution label: ${RELEASE_LABEL}"
echo ""

# Step 1: Build release binary
echo "--- Building release binary..."
cd "${PROJECT_DIR}"
swift build -c release 2>&1
RELEASE_BIN_DIR="$(swift build -c release --show-bin-path)"
RELEASE_BIN="${RELEASE_BIN_DIR}/Redact"
RESOURCE_BUNDLE="${RELEASE_BIN_DIR}/Redact_Redact.bundle"

if [ ! -f "${RELEASE_BIN}" ]; then
    echo "ERROR: Release binary not found at ${RELEASE_BIN}"
    exit 1
fi

echo "Binary: ${RELEASE_BIN} ($(du -h "${RELEASE_BIN}" | cut -f1))"

# Step 2: Create .app bundle
echo ""
echo "--- Creating .app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# Copy executable
cp "${RELEASE_BIN}" "${APP_BUNDLE}/Contents/MacOS/Redact"

# Copy Info.plist
cp "${INFO_PLIST}" "${APP_BUNDLE}/Contents/Info.plist"

# Copy icon
cp "${PROJECT_DIR}/Sources/Resources/icon.icns" "${APP_BUNDLE}/Contents/Resources/icon.icns"

# Copy the SwiftPM resource bundle.
cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/Redact_Redact.bundle"

# Create PkgInfo
echo -n "APPL????" > "${APP_BUNDLE}/Contents/PkgInfo"

echo "App bundle created: ${APP_BUNDLE}"
echo "Size: $(du -sh "${APP_BUNDLE}" | cut -f1)"

# Step 3: Code sign (if requested)
if [ "${MODE}" = "sign" ] || [ "${MODE}" = "dmg" ] || [ "${MODE}" = "release" ]; then
    echo ""
    echo "--- Code signing..."

    # Sign the app bundle (resource bundle has no code, doesn't need separate signing)
    codesign --force --options runtime --timestamp \
        --entitlements "${PROJECT_DIR}/Sources/Redact.entitlements" \
        --sign "${SIGNING_IDENTITY}" \
        "${APP_BUNDLE}"

    echo "Code signing complete."

    "${PROJECT_DIR}/scripts/verify-release-artifacts.sh" "${APP_BUNDLE}"
fi

# Step 4: Create and sign DMG (if dmg or release mode)
if [ "${MODE}" = "dmg" ] || [ "${MODE}" = "release" ]; then
    echo ""
    echo "--- Creating DMG..."

    DMG_STAGING="${BUILD_DIR}/dmg-staging"
    rm -rf "${DMG_STAGING}"
    mkdir -p "${DMG_STAGING}"

    # Copy app
    cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"

    # Copy README and LICENSE
    cp "${PROJECT_DIR}/README.md" "${DMG_STAGING}/README.md"
    cp "${PROJECT_DIR}/LICENSE" "${DMG_STAGING}/LICENSE"

    # Create Applications symlink
    ln -s /Applications "${DMG_STAGING}/Applications"

    # Create DMG
    rm -f "${DMG_PATH}"
    hdiutil create -volname "Redact" \
        -srcfolder "${DMG_STAGING}" \
        -ov -format UDZO \
        "${DMG_PATH}"

    # Sign the DMG
    codesign --force --timestamp --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"

    # Clean up staging
    rm -rf "${DMG_STAGING}"

    "${PROJECT_DIR}/scripts/verify-release-artifacts.sh" "${APP_BUNDLE}" "${DMG_PATH}"

    echo "DMG structure and signatures verified."
fi

# Step 5: Notarize and staple the final distribution (release mode only)
if [ "${MODE}" = "release" ]; then
    echo ""
    echo "--- Notarizing final DMG..."

    NOTARIZATION_RESULT="${BUILD_DIR}/notarization-result.json"
    NOTARIZATION_LOG="${BUILD_DIR}/notarization-log.json"
    rm -f "${NOTARIZATION_RESULT}" "${NOTARIZATION_LOG}"

    if ! xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        --wait \
        --output-format json > "${NOTARIZATION_RESULT}"; then
        cat "${NOTARIZATION_RESULT}" >&2
        SUBMISSION_ID="$(jq -r '.id // empty' "${NOTARIZATION_RESULT}" 2>/dev/null || true)"
        if [ -n "${SUBMISSION_ID}" ]; then
            xcrun notarytool log "${SUBMISSION_ID}" \
                --keychain-profile "${NOTARY_PROFILE}" \
                "${NOTARIZATION_LOG}" || true
        fi
        echo "ERROR: Notarization failed." >&2
        exit 1
    fi

    cat "${NOTARIZATION_RESULT}"
    SUBMISSION_ID="$(jq -r '.id // empty' "${NOTARIZATION_RESULT}")"
    NOTARIZATION_STATUS="$(jq -r '.status // empty' "${NOTARIZATION_RESULT}")"
    [ -n "${SUBMISSION_ID}" ] || { echo "ERROR: Notarization returned no submission ID." >&2; exit 1; }

    xcrun notarytool log "${SUBMISSION_ID}" \
        --keychain-profile "${NOTARY_PROFILE}" \
        "${NOTARIZATION_LOG}"

    if [ "${NOTARIZATION_STATUS}" != "Accepted" ]; then
        echo "ERROR: Notarization status is '${NOTARIZATION_STATUS}'. See ${NOTARIZATION_LOG}." >&2
        exit 1
    fi

    xcrun stapler staple "${DMG_PATH}"
    xcrun stapler validate "${DMG_PATH}"
    spctl -a -t open --context context:primary-signature -vv "${DMG_PATH}"
    "${PROJECT_DIR}/scripts/verify-release-artifacts.sh" "${APP_BUNDLE}" "${DMG_PATH}"

    echo "Notarization accepted and final DMG ticket stapled."
fi

if [ "${MODE}" = "dmg" ] || [ "${MODE}" = "release" ]; then

    echo ""
    echo "=== Release Build Complete ==="
    echo "DMG: ${DMG_PATH}"
    echo "Size: $(du -h "${DMG_PATH}" | cut -f1)"
else
    echo ""
    echo "=== Build Complete ==="
    echo "App: ${APP_BUNDLE}"
fi
