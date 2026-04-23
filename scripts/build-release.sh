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
#   - App-specific password stored as: xcrun notarytool store-credentials "Redact-Notary"

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${PROJECT_DIR}/.build/release-app"
APP_NAME="Redact"
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="Redact-1.3.0.dmg"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}"
SIGNING_IDENTITY="Developer ID Application: Santiago Alonso Alexandre (QAMM2A6WRQ)"
TEAM_ID="QAMM2A6WRQ"

MODE="${1:-build}"

echo "=== Redact Release Build ==="
echo "Mode: ${MODE}"
echo ""

# Step 1: Build release binary
echo "--- Building release binary..."
cd "${PROJECT_DIR}"
swift build -c release 2>&1
RELEASE_BIN="${PROJECT_DIR}/.build/arm64-apple-macosx/release/Redact"
RESOURCE_BUNDLE="${PROJECT_DIR}/.build/arm64-apple-macosx/release/Redact_Redact.bundle"

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
cp "${PROJECT_DIR}/Sources/Info.plist" "${APP_BUNDLE}/Contents/Info.plist"

# Copy icon
cp "${PROJECT_DIR}/Sources/Resources/icon.icns" "${APP_BUNDLE}/Contents/Resources/icon.icns"

# Copy SPM resource bundle (contains whisper-transcribe.py and icon.icns)
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

    # Verify
    codesign --verify --deep --strict "${APP_BUNDLE}"
    echo "Signature verified."
    codesign -dv --verbose=2 "${APP_BUNDLE}" 2>&1 | grep -E "Authority|TeamIdentifier"
fi

# Step 4: Notarize (if release mode)
if [ "${MODE}" = "release" ]; then
    echo ""
    echo "--- Notarizing..."

    # Create a zip for notarization
    NOTARIZE_ZIP="${BUILD_DIR}/Redact-notarize.zip"
    ditto -c -k --keepParent "${APP_BUNDLE}" "${NOTARIZE_ZIP}"

    # Submit for notarization (uses stored credentials)
    xcrun notarytool submit "${NOTARIZE_ZIP}" \
        --keychain-profile "notarytool" \
        --wait

    # Staple the ticket
    xcrun stapler staple "${APP_BUNDLE}"
    echo "Notarization complete and stapled."

    # Clean up zip
    rm -f "${NOTARIZE_ZIP}"
fi

# Step 5: Create DMG (if dmg or release mode)
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
    codesign --force --sign "${SIGNING_IDENTITY}" "${DMG_PATH}"

    # Clean up staging
    rm -rf "${DMG_STAGING}"

    echo ""
    echo "=== Release Build Complete ==="
    echo "DMG: ${DMG_PATH}"
    echo "Size: $(du -h "${DMG_PATH}" | cut -f1)"
else
    echo ""
    echo "=== Build Complete ==="
    echo "App: ${APP_BUNDLE}"
fi
