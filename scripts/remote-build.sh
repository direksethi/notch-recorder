#!/bin/bash
# Optional: build on a Mac over SSH from another machine (for example when
# the checkout lives on a Linux box). The plain local path is
# scripts/make-app.sh, run on the Mac itself.
#
# Usage: scripts/remote-build.sh <ssh-host> [--test] [--install] [--launch] [--force]
#   <ssh-host>  anything ssh accepts: user@host or a Host from ~/.ssh/config
#   --test      run the Swift tests on the Mac instead of building the app
#   --install   copy the built app to ~/Applications on the Mac
#   --launch    with --install, open the app afterwards
#   --force     with --install, replace the app even while it is recording
#
# Environment:
#   REMOTE_DIR               source snapshot on the Mac, relative to its home
#                            folder (default Library/Caches/notch-recorder-build/src)
#   CODESIGN_IDENTITY        passed to make-app.sh (default ad-hoc)
#   BUILD_KEYCHAIN           keychain to unlock before signing, relative to
#                            ~/Library/Keychains on the Mac (see setup-signing.sh)
#   BUILD_KEYCHAIN_PASS_FILE local file holding that keychain's password
set -euo pipefail
cd "$(dirname "$0")/.."

HOST="${1:-}"
if [ -z "$HOST" ] || [[ "$HOST" == --* ]]; then
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
fi
shift
TEST=0; INSTALL=0; LAUNCH=0; FORCE=0
for a in "$@"; do
  case "$a" in
    --test) TEST=1 ;;
    --install) INSTALL=1 ;;
    --launch) LAUNCH=1 ;;
    --force) FORCE=1 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done
REMOTE="${REMOTE_DIR:-Library/Caches/notch-recorder-build/src}"
IDENTITY="${CODESIGN_IDENTITY:--}"

echo "== web"
[ -d web/node_modules ] || (cd web && npm ci)
(cd web && npm run build && npm run fixtures -w @nr/core)

echo "== sync"
ssh "$HOST" "mkdir -p ~/'$REMOTE'"
rsync -a --delete --exclude .build --exclude build --exclude .git --exclude node_modules ./ "$HOST:$REMOTE/"

if [ $TEST -eq 1 ]; then
  echo "== test"
  # SwiftPM cannot reach the login keychain in an SSH session.
  ssh "$HOST" "cd ~/'$REMOTE' && bash scripts/test.sh --skip-web --disable-keychain"
  exit 0
fi

if [ $INSTALL -eq 1 ] && [ $FORCE -eq 0 ]; then
  STATE=$(ssh "$HOST" "cat ~/Library/Application\ Support/NotchRecorder/state.json 2>/dev/null || true")
  if [[ "$STATE" == *'"recording"'* || "$STATE" == *'"stopping"'* || "$STATE" == *'"paused"'* ]]; then
    echo "Notch Recorder is recording on $HOST; not replacing it. Re-run with --force to override." >&2
    exit 3
  fi
fi

echo "== build"
BUILD="cd ~/'$REMOTE' && CODESIGN_IDENTITY='$IDENTITY' SWIFT_FLAGS=--disable-keychain bash scripts/make-app.sh --skip-web"
if [ -n "${BUILD_KEYCHAIN:-}" ] && [ -n "${BUILD_KEYCHAIN_PASS_FILE:-}" ]; then
  # The password travels on stdin, never on a command line.
  ssh "$HOST" "read -r P; security unlock-keychain -p \"\$P\" ~/Library/Keychains/'$BUILD_KEYCHAIN' && $BUILD" < "$BUILD_KEYCHAIN_PASS_FILE"
else
  ssh "$HOST" "$BUILD"
fi

if [ $INSTALL -eq 1 ]; then
  echo "== install"
  ssh "$HOST" "osascript -e 'tell application id \"com.direksethi.NotchRecorder\" to quit' 2>/dev/null || true
for i in \$(seq 1 30); do pgrep -x NotchRecorder >/dev/null || break; sleep 0.5; done
pgrep -x NotchRecorder >/dev/null && { echo 'app did not quit' >&2; exit 4; }
mkdir -p ~/Applications && rm -rf ~/Applications/'Notch Recorder.app' && cp -R ~/'$REMOTE'/build/'Notch Recorder.app' ~/Applications/"
  echo "installed ~/Applications/Notch Recorder.app on $HOST"
  if [ $LAUNCH -eq 1 ]; then ssh "$HOST" "open ~/Applications/'Notch Recorder.app'"; fi
else
  echo "built ~/$REMOTE/build/Notch Recorder.app on $HOST"
fi
