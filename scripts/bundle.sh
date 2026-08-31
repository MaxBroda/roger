#!/usr/bin/env bash
# Builds Roger and wraps the binary in a .app bundle.
#
# The bundle is not cosmetic: TCC (microphone, accessibility) ties permissions to
# bundle identity and code signature. A bare SwiftPM binary has neither.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-debug}"

# Not into .build/: TCC binds permissions to the path too, and a clean build
# would take them along. ~/Applications survives that.
APP_DIR="${ROGER_APP_DIR:-$HOME/Applications}"
APP="$APP_DIR/Roger.app"
CONTENTS="$APP/Contents"
mkdir -p "$APP_DIR"

# A Developer ID keeps permissions stable across rebuilds, because the signing
# identity stays constant. Without a certificate only ad-hoc is left — then the
# signature changes on every build and the permissions are gone; Roger's setup
# window catches that instead of showing a cryptic error.
# `|| true` because grep exits 1 without a match, and pipefail would abort right
# where the normal case is: no certificate installed.
SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)".*/\1/' || true)"
: "${SIGN_ID:=-}"

swift build -c "$CONFIG" --package-path "$ROOT"
BINARY="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/Roger"

pkill -f "$APP/Contents/MacOS/Roger" 2>/dev/null || true
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BINARY" "$CONTENTS/MacOS/Roger"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
cp "$ROOT/Resources/AppIcon.icns" "$CONTENTS/Resources/AppIcon.icns"

# Share Tech Mono and IBM Plex Mono are not on every Mac. They travel along and
# get registered via `ATSApplicationFontsPath` — for Roger only, without
# installing them. If missing, the design system falls back to the system mono.
rm -rf "$CONTENTS/Resources/Fonts"
mkdir -p "$CONTENTS/Resources/Fonts"
cp "$ROOT/Resources/Fonts/"*.ttf "$CONTENTS/Resources/Fonts/"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# codesign refuses to work with extended attributes ("resource fork, Finder
# information, or similar detritus not allowed"), which the copied binary may
# have dragged in from .build.
xattr -cr "$APP"

codesign --force --sign "$SIGN_ID" \
  --identifier com.mbr.roger \
  --entitlements "$ROOT/Resources/Roger.entitlements" \
  --options runtime \
  --timestamp=none \
  "$APP"

echo "$APP  [signiert: $SIGN_ID]"
