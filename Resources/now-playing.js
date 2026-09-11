// Called as `osascript -l JavaScript now-playing.js`. Answers exactly one
// question — is a player currently playing — without the entitlement that
// blocks reading now-playing info from inside Roger's own process.
//
// console.log writes to stderr in JXA; the value of the script's last
// expression is what lands on stdout, hence the bare JSON.stringify(...).
const bundle = $.NSBundle.bundleWithPath(
  "/System/Library/PrivateFrameworks/MediaRemote.framework/"
);
bundle.load;

const item = $.NSClassFromString("MRNowPlayingRequest").localNowPlayingItem;

let playing = false;
if (item.js) {
  const rate = item.nowPlayingInfo.valueForKey(
    "kMRMediaRemoteNowPlayingInfoPlaybackRate"
  );
  playing = (rate.js || 0) > 0;
}

JSON.stringify({ playing: playing });
