# MediaRemoteAdapter (vendored)

Third-party sources, BSD 3-Clause, © 2025 Jonas van den Berg — see `LICENSE`.

Origin: <https://github.com/ungive/mediaremote-adapter>, revision `73f14ab`.

## Why it is here

Since macOS 15.4 the now-playing information is behind an entitlement: loaded
from inside an app, `MRMediaRemoteGetNowPlayingInfo` returns `nil`. This adapter
gets it anyway, by having `/usr/bin/perl` — a system binary that *is* entitled —
load a helper library that prints the information to stdout.

Roger needs it to answer one question before pausing: **is a player actually
playing?** CoreAudio can only say whether sound is leaving the machine, which is
also true for a video call, a system alert, or an app that merely holds the
output device open. Acting on that started playback the user had paused
themselves (#26).

## Why vendored instead of a package dependency

The upstream repository has no tags or releases, and the Swift fork that exists
carries no `LICENSE` file. A dependency would have to be pinned to a branch or a
commit, which is the same manual step as updating these files — without the
sources being visible in review.

## What was changed

Nothing inside the files. The layout was adapted to SwiftPM: `src/*` moved to
this directory, `include/` kept as the public header path, and `src/test/main.m`
left out (it belongs to the upstream test client, which Roger does not build).
The Perl script lives at `Resources/mediaremote-adapter.pl` so that
`scripts/bundle.sh` copies it like every other resource.

## How it runs

`swift build` produces `libMediaRemoteAdapter.dylib`. Nothing links against it —
`bundle.sh` places it as `Contents/Frameworks/MediaRemoteAdapter.framework/MediaRemoteAdapter`,
the layout the script expects, and Roger only ever starts the script:

```
/usr/bin/perl mediaremote-adapter.pl <framework path> stream
```

## Updating

Copy `src/*` and `include/*` from a newer upstream revision, keep the layout,
drop `src/test/main.m`, refresh `Resources/mediaremote-adapter.pl` and the
revision noted above. Apple has broken this path before — if it stops working,
Roger logs it once and the feature stays off.
