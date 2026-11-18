#!/bin/bash
# Builds "Notch Recorder.app" in ./build. Run on the Mac, from anywhere.
#
# Usage: scripts/make-app.sh [--skip-web]
#   --skip-web   reuse the web UI already built into Resources/web
#
# Environment:
#   CODESIGN_IDENTITY  signing identity; default "-" (ad-hoc)
#   SWIFT_FLAGS        extra flags for swift build (for example --disable-keychain)
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_WEB=0
for a in "$@"; do
  case "$a" in
    --skip-web) SKIP_WEB=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done
IDENTITY="${CODESIGN_IDENTITY:--}"

if [ $SKIP_WEB -eq 0 ]; then
  echo "== web"
  [ -d web/node_modules ] || (cd web && npm ci)
  (cd web && npm run build)
fi
if [ ! -f Resources/web/index.html ] || [ ! -f web/packages/core/dist/core.jsc.js ]; then
  echo "The web UI is not built. Run without --skip-web, or run 'npm run build' in web/ first." >&2
  exit 1
fi

echo "== swift"
# shellcheck disable=SC2086
swift build -c release --product NotchRecorder ${SWIFT_FLAGS:-}

echo "== bundle"
APP="build/Notch Recorder.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/NotchRecorder "$APP/Contents/MacOS/NotchRecorder"
sed "s/__BUILD__/$(date +%Y%m%d%H%M)/" Resources/Info.plist > "$APP/Contents/Info.plist"
cp -R Resources/web "$APP/Contents/Resources/web"
cp web/packages/core/dist/core.jsc.js "$APP/Contents/Resources/core.jsc.js"
# SwiftPM resource bundles from dependencies, if any.
for b in .build/release/*.bundle; do [ -e "$b" ] && cp -R "$b" "$APP/Contents/Resources/"; done
if [ ! -f build/AppIcon.icns ]; then
  swift scripts/make-icon.swift build/AppIcon.iconset >/dev/null
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign "$IDENTITY" --identifier com.direksethi.NotchRecorder --timestamp=none "$APP"
codesign --verify "$APP"
echo "built $APP"
