#!/usr/bin/env bash
# Build native SISR.app (universal), optionally codesign + notarize, zip to dist/.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SKIP_SIGN=0
SKIP_NOTARIZE=0
for arg in "$@"; do
  case "$arg" in
    --skip-sign) SKIP_SIGN=1 ;;
    --skip-notarize) SKIP_NOTARIZE=1 ;;
  esac
done

VERSION="$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' SISR.xcodeproj/project.pbxproj | head -1 | tr -d ' \"')"
VERSION="${VERSION:-1.0.0}"
ARCH="universal"
NOTARY_WAIT_TIMEOUT="${NOTARY_WAIT_TIMEOUT:-25m}"

python3 scripts/generate_xcodeproj.py

mkdir -p dist build/swift
DERIVED="$ROOT/build/swift/DerivedData"
ARCHIVE="$ROOT/build/swift/SISR.xcarchive"
EXPORT_DIR="$ROOT/build/swift/export"

rm -rf "$DERIVED" "$ARCHIVE" "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"

echo "==> Building SISR (Release, universal)"
xcodebuild \
  -project SISR.xcodeproj \
  -scheme SISR \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_SRC="$(find "$DERIVED" -name 'SISR.app' -type d | head -1)"

if [[ -z "${APP_SRC:-}" || ! -d "$APP_SRC" ]]; then
  echo "error: SISR.app not found after build" >&2
  exit 1
fi

APP_DST="$EXPORT_DIR/SISR.app"
rm -rf "$APP_DST"
cp -R "$APP_SRC" "$APP_DST"

if [[ "$SKIP_SIGN" -eq 0 ]]; then
  IDENTITY="${SIGNING_IDENTITY:-}"
  if [[ -z "$IDENTITY" ]]; then
    IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:.*\)".*/\1/p' | head -1)"
  fi
  if [[ -z "$IDENTITY" ]]; then
    echo "error: No Developer ID Application identity. Set SIGNING_IDENTITY or import a certificate." >&2
    exit 1
  fi
  echo "==> Codesigning with $IDENTITY"
  ENTITLEMENTS="$ROOT/SISR/SISR.entitlements"
  codesign --force --deep --options runtime --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_DST"
  codesign --verify --verbose=2 "$APP_DST"
fi

if [[ "$SKIP_SIGN" -eq 0 && "$SKIP_NOTARIZE" -eq 0 ]]; then
  if [[ -z "${APPLE_API_KEY_ID:-}" || -z "${APPLE_API_ISSUER_ID:-}" || -z "${APPLE_API_KEY_PATH:-}" ]]; then
    echo "error: Set APPLE_API_KEY_ID, APPLE_API_ISSUER_ID, APPLE_API_KEY_PATH for notarization." >&2
    exit 1
  fi
  ZIP_TMP="$EXPORT_DIR/SISR-notarize.zip"
  ditto -c -k --keepParent "$APP_DST" "$ZIP_TMP"
  echo "==> Submitting for notarization (timeout $NOTARY_WAIT_TIMEOUT)"
  xcrun notarytool submit "$ZIP_TMP" \
    --key "$APPLE_API_KEY_PATH" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER_ID" \
    --wait \
    --timeout "$NOTARY_WAIT_TIMEOUT"
  xcrun stapler staple "$APP_DST"
  rm -f "$ZIP_TMP"
fi

OUT_ZIP="$ROOT/dist/SISR-native-${VERSION}-macos-${ARCH}.zip"
rm -f "$OUT_ZIP"
ditto -c -k --keepParent "$APP_DST" "$OUT_ZIP"
echo "==> Wrote $OUT_ZIP"
