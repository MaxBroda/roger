#!/usr/bin/env bash
# Drops Roger's TCC entries so macOS asks for the permissions again.
#
# Needed exactly once: after switching from ad-hoc to certificate signing the old
# entries are bound to a binary hash that no longer exists.
set -euo pipefail

pkill -f "Roger.app/Contents/MacOS/Roger" 2>/dev/null || true

for service in Accessibility ListenEvent Microphone; do
  if tccutil reset "$service" com.mbr.roger 2>/dev/null; then
    echo "zurückgesetzt: $service"
  else
    echo "nichts zurückzusetzen: $service"
  fi
done

echo
echo "Jetzt »open ~/Applications/Roger.app« und die Berechtigungen neu erteilen."
