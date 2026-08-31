#!/usr/bin/env bash
# Builds Roger for release and packs a distributable ZIP into dist/ — the archive
# to attach to a GitHub release or put behind a download button.
#
#     ./scripts/release.sh            # version from Info.plist
#     ./scripts/release.sh 0.2.0      # set the version (writes Info.plist)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLIST="$ROOT/Resources/Info.plist"
DIST="$ROOT/dist"

if [[ $# -ge 1 ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $1" "$PLIST"
  # The build number has to increase every release, or macOS treats an update as
  # the same program and keeps the old copy cached.
  BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD + 1))" "$PLIST"
fi

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST")"

# Build into dist/ rather than ~/Applications: a release must not touch the
# installed copy and the permissions granted to it.
ROGER_APP_DIR="$DIST" "$ROOT/scripts/bundle.sh" release

ARCHIVE="$DIST/Roger-$VERSION.zip"
rm -f "$ARCHIVE"

# `ditto`, not `zip`: only ditto stores the code signature and resource forks so
# the signature survives unpacking. A `zip`-packed bundle arrives damaged.
ditto -c -k --sequesterRsrc --keepParent "$DIST/Roger.app" "$ARCHIVE"

echo
echo "Archiv:     $ARCHIVE"
echo "Größe:      $(du -h "$ARCHIVE" | cut -f1)"
echo "SHA-256:    $(shasum -a 256 "$ARCHIVE" | cut -d' ' -f1)"
echo "Signatur:   $(codesign -dv "$DIST/Roger.app" 2>&1 | grep -E '^Authority|^Signature' | head -2 | tr '\n' ' ')"
echo

if ! codesign -dv "$DIST/Roger.app" 2>&1 | grep -q "^Authority"; then
  cat <<'WARN'
Achtung: ad-hoc signiert, nicht notarisiert.

Wer dieses Archiv aus dem Netz lädt, bekommt von Gatekeeper »Roger ist
beschädigt« zu sehen — das ist kein Fehler im Archiv, sondern die Quarantäne.
Der Empfänger muss sie einmal entfernen:

    xattr -dr com.apple.quarantine /Applications/Roger.app

Für eine Weitergabe ohne diesen Satz braucht es eine Developer ID
(99 €/Jahr) und `xcrun notarytool submit`. Siehe README, Abschnitt
»Weitergeben«.
WARN
fi
