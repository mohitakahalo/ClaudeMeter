#!/bin/bash
# Build ClaudeMeter and install it over the copy in /Applications.
#
# Editing sources does not rebuild, and rebuilding does not install: the build
# script only writes to build/out. This does both and relaunches, so a change
# reaches the menu bar in one command.
set -euo pipefail

SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRCROOT="$(dirname "$SCRIPTS")"
DEST="${DEST:-/Applications}"
APP="$DEST/ClaudeMeter.app"
BUILT="${WORK:-$SRCROOT/build}/out/ClaudeMeter.app"

SKIP_BUILD=no
for arg in "$@"; do
    case "$arg" in
        --no-build) SKIP_BUILD=yes ;;
        -h|--help)
            echo "usage: $(basename "$0") [--no-build]"
            echo
            echo "  --no-build   install the existing build/out artifact without rebuilding"
            echo
            echo "  DEST=<dir>   install somewhere other than /Applications"
            exit 0
            ;;
        *)
            echo "unknown option: $arg" >&2
            exit 2
            ;;
    esac
done

if [ "$SKIP_BUILD" = no ]; then
    bash "$SCRIPTS/build-without-xcode.sh"
fi

if [ ! -d "$BUILT" ]; then
    echo "no build found at $BUILT" >&2
    echo "run without --no-build to build it first" >&2
    exit 1
fi

# Ask it to quit rather than killing it, so settings are flushed on the way out.
if pgrep -x ClaudeMeter >/dev/null; then
    osascript -e 'tell application "ClaudeMeter" to quit' >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do
        pgrep -x ClaudeMeter >/dev/null || break
        sleep 0.25
    done
    pkill -x ClaudeMeter 2>/dev/null || true
    sleep 0.5
fi

rm -rf "$APP"
cp -R "$BUILT" "$APP"

# A bundle that will not verify would be rejected at launch with no useful
# explanation, so fail here where the cause is obvious.
codesign --verify --strict "$APP"

open "$APP"

VERSION="$(defaults read "$APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "?")"

echo
echo "=== INSTALLED ==="
echo "app     : $APP (v$VERSION)"
echo "signed  : $(codesign -dv --verbose=2 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
echo "reading : ~/.claudemeter/usage.json"
echo
echo "After a rebuild the keychain asks once for Claude Code's credentials —"
echo "choose \"Always Allow\". See docs/signing.md for why it asks again."
