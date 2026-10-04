#!/usr/bin/env bash
# Build SISR for the local Mac and launch the .app (no Xcode GUI required).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="SISR"
CONFIG="${SISR_CONFIGURATION:-Debug}"
DERIVED="${SISR_DERIVED_DATA:-$ROOT/.derivedData}"

echo "→ Building $SCHEME ($CONFIG)…"
xcodebuild \
  -project "$ROOT/SISR.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -quiet \
  build

APP="$DERIVED/Build/Products/$CONFIG/SISR.app"
if [[ ! -d "$APP" ]]; then
  echo "error: expected app at $APP" >&2
  exit 1
fi

# Replace a running instance so you always test the fresh build.
if pgrep -xq "SISR" 2>/dev/null; then
  echo "→ Quitting running SISR…"
  osascript -e 'tell application "SISR" to quit' >/dev/null 2>&1 || true
  # Give it a moment; fall back to kill if needed.
  for _ in 1 2 3 4 5; do
    pgrep -xq "SISR" || break
    sleep 0.2
  done
  pkill -x "SISR" 2>/dev/null || true
fi

echo "→ Launching $APP"
open "$APP"
echo "✓ SISR is running."
