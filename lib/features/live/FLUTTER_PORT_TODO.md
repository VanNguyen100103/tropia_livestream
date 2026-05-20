# Flutter Live Module - Migration TODO (LiveKit → SRS HLS)

The Go backend (Phase 0-15) is complete and SRS-based. The Flutter live
module still references LiveKit symbols and won't compile until the two
big screens are rewritten:

- `screens/live_host_screen.dart` (1059 lines) — uses LiveKit `Room`,
  `LocalVideoTrack`, `VideoTrackRenderer`, `setCameraEnabled`, etc.
- `screens/live_stream_screen.dart` (1821 lines) — uses LiveKit `Room`,
  `VideoTrack`, `TrackSubscribedEvent`.

## Already done (Phase 16 partial)

- `services/srs_service.dart` — Dio client for the Go backend's live
  endpoints. Models: `StreamInfo`, `PublishURLs`, `PlaybackURLs`.
- `widgets/hls_viewer.dart` — drop-in HLS player using
  `video_player` + `chewie`. Works on Android / iOS / Web.
- `widgets/rtmp_publish_info.dart` — copy-able RTMP / WHIP / SRT URLs to
  hand to OBS or Larix Broadcaster.
- LiveKit + Agora files removed.
- `livekit_client` removed from `pubspec.yaml`.

## Remaining work

### Viewer screen (`live_stream_screen.dart`)
Replace WebRTC playback with HLS playback:

```dart
// Before:
_remoteVideoTrack = ...
return VideoTrackRenderer(_remoteVideoTrack!);

// After:
final res = await SrsService(dio: dio).getPlayback(streamId);
return HlsViewer(hlsUrl: res.playback.hls);
```

Drop all LiveKit imports, drop `_room`, `_remoteVideoTrack`, `_liveKitReady`
state. Keep chat / products / voucher / reward / actions widgets — they
still talk to the Go backend, not LiveKit.

### Host screen (`live_host_screen.dart`)
Two options:

1. **External publisher (MVP — recommended)**: replace the in-app camera
   preview with `RtmpPublishInfo` and instruct the seller to use OBS or
   Larix Broadcaster pushing to the returned RTMP URL.
2. **In-app RTMP publish**: add `apivideo_live_stream` (or
   `flutter_webrtc` for WHIP) and push directly. Requires CAMERA / MIC
   permissions and platform-specific setup.

For probation/demo: pick option 1, ship faster.

### Stream URLs
Call `SrsService.createStream(...)` from `live_setup_screen.dart` instead
of LiveKit token fetch. Persist `streamId` + `publish.rtmp` on the seller's
device until they end the stream.

### Provider
`LiveProvider` mock data + actions can stay — they don't reference LiveKit.
Once the API client is wired through `SrsService`, swap `_buildMockStreams`
to `SrsService.listActive()`.

## Why this isn't auto-rewritten

The two screens are tightly coupled to LiveKit's `Room` event model. A
mechanical shim (a fake `Room` that wraps an HLS player) would compile but
hide semantic differences (e.g. host preview is local-camera frames, not a
remote subscription). Better to rewrite the small UI surface explicitly.
