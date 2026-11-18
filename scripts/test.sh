#!/bin/bash
# Runs the Swift tests. Run on the Mac.
#
# Usage: scripts/test.sh [--skip-web] [swift test args...]
#   --skip-web   do not rebuild the formatter bundle and fixtures the
#                BridgeKit tests read (they must already exist)
set -euo pipefail
cd "$(dirname "$0")/.."

ARGS=()
SKIP_WEB=0
for a in "$@"; do
  if [ "$a" = "--skip-web" ]; then SKIP_WEB=1; else ARGS+=("$a"); fi
done

# The BridgeKit tests decode fixtures written by the TypeScript core and run
# its formatter bundle through JavaScriptCore.
if [ $SKIP_WEB -eq 0 ]; then
  [ -d web/node_modules ] || (cd web && npm ci)
  (cd web && npm run build -w @nr/core && npm run fixtures -w @nr/core)
fi
if [ ! -f Tests/BridgeKitTests/Fixtures/core.jsc.js ]; then
  echo "Tests/BridgeKitTests/Fixtures/core.jsc.js is missing. Run without --skip-web." >&2
  exit 1
fi

# With only the Command Line Tools installed (no Xcode), Swift Testing is not
# on the default search paths, so point the compiler and linker at it.
FLAGS=()
if [ "$(xcode-select -p 2>/dev/null)" = "/Library/Developer/CommandLineTools" ]; then
  F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  L=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  FLAGS=(-Xswiftc -F"$F" -Xlinker -F"$F" -Xlinker -rpath -Xlinker "$F" -Xlinker -rpath -Xlinker "$L")
fi
swift test ${FLAGS[@]+"${FLAGS[@]}"} ${ARGS[@]+"${ARGS[@]}"}
