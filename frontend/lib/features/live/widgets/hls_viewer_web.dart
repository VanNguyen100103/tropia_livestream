// Web-only HLS viewer: <video> element driven by hls.js for Chrome /
// Firefox / Edge (which can't decode HLS natively). Falls back to native
// playback when the browser supports HLS directly (Safari, iOS Chrome).
//
// hls.js is loaded as a global script in web/index.html — this file just
// instantiates `window.Hls(...)` via dart:js_interop when available.

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:web/web.dart' as web;

@JS('Hls')
external HlsJs? get _hlsCtor;

@JS('Hls.isSupported')
external bool _hlsIsSupported();

extension type HlsJs._(JSObject _) implements JSObject {
  external factory HlsJs([JSObject? config]);
  external void loadSource(String url);
  external void attachMedia(web.HTMLVideoElement video);
  external void destroy();
  external void on(String event, JSFunction handler);
  // Recovery helpers — hls.js fires recoverable errors (buffer stalls,
  // segment 404, network blip) that we should retry instead of giving up.
  external void startLoad([JSNumber? startPosition]);
  external void recoverMediaError();
}

class HlsViewerWeb extends StatefulWidget {
  final String hlsUrl;
  final BoxFit fit;
  final bool autoplay;
  // Card previews use muted+loop+poster so Chrome's autoplay policy lets
  // them play without a user gesture. Full buyer view leaves these at their
  // defaults (audible, single play, no poster).
  final bool muted;
  final bool loop;
  final String? posterUrl;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  // Parent can override the "Thử lại" handler. Default behavior just
  // rebuilds hls.js with the same URL — useless if the server has rotated
  // the playlist or ended the session. Buyer view passes a callback that
  // re-fetches the playback URL from /streams/:id/playback first.
  final Future<void> Function()? onRetry;

  const HlsViewerWeb({
    super.key,
    required this.hlsUrl,
    required this.fit,
    required this.autoplay,
    this.muted = false,
    this.loop = false,
    this.posterUrl,
    this.onReady,
    this.onError,
    this.onRetry,
  });

  @override
  State<HlsViewerWeb> createState() => _HlsViewerWebState();
}

class _HlsViewerWebState extends State<HlsViewerWeb> {
  late final String _viewType;
  late final web.HTMLVideoElement _video;
  HlsJs? _hls;
  String? _error;
  double _aspect = 9 / 16;
  StreamSubscription<web.Event>? _visibilitySub;
  // Timestamp when the tab last went hidden. When >3s elapses with the tab
  // hidden, SRS has likely rolled past the segments we still hold, so on
  // resume we tear down hls.js and rebuild it instead of optimistically
  // calling startLoad() (which leaves the player stuck on stale buffers
  // half the time → the "lúc được lúc không" flakiness the user reported).
  DateTime? _hiddenAt;
  // Bounded retry counters so we don't infinite-loop on a dead stream.
  // Reset on every _reattach() so a recovered player gets a fresh budget.
  int _mediaRecoverTries = 0;
  int _networkRecoverTries = 0;
  // Cold-start retry: when a buyer opens the stream before SRS has
  // published the first .m3u8 (typical 5-10s window after seller hits
  // "go live"), hls.js fires manifestLoadError → 404. Without this
  // counter we'd flip to "Lỗi phát video" on the very first miss; the
  // buyer would have to mash "Thử lại" until SRS catches up. Instead
  // we silently retry the manifest up to 10× with a 2s backoff before
  // surfacing anything to the user.
  int _manifestRetries = 0;
  static const int _manifestRetryBudget = 10;
  Timer? _manifestRetryTimer;
  // True from initState until the first manifest parses successfully.
  // While true, the UI shows "Đang kết nối live..." instead of an error
  // even on transient load failures — same reason as above.
  bool _waitingForFirstManifest = true;

  @override
  void initState() {
    super.initState();
    _viewType = 'tropia-hls-${identityHashCode(this)}';
    _video = web.HTMLVideoElement()
      ..autoplay = widget.autoplay
      ..controls = false
      ..muted = widget.muted
      ..loop = widget.loop
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.backgroundColor = 'black'
      // The DOM <video> sits above Flutter's canvas in the stacking
      // context, so without this it eats every click on the chat
      // composer / product cards / action buttons layered over it.
      // We never want the user clicking the video directly (no native
      // controls, no play/pause toggle) — all gestures go to Flutter.
      ..style.pointerEvents = 'none'
      ..style.objectFit = widget.fit == BoxFit.cover ? 'cover' : 'contain';
    if (widget.posterUrl != null && widget.posterUrl!.isNotEmpty) {
      _video.poster = widget.posterUrl!;
    }

    // Surface metadata + error events to Flutter state.
    _video.onLoadedMetadata.listen((_) {
      final w = _video.videoWidth;
      final h = _video.videoHeight;
      if (mounted) {
        setState(() {
          if (w > 0 && h > 0) _aspect = w / h;
          // Safari / iOS take the native-HLS path and don't fire hls.js
          // events — use the <video> element's metadata as the
          // "first playable manifest" signal there.
          _waitingForFirstManifest = false;
        });
      }
      widget.onReady?.call();
    });
    // Fallback signal for clearing the cold-start spinner. hlsLevelLoaded
    // *should* fire as soon as the variant playlist parses, but in
    // practice we've seen the spinner get stuck even with the manifest
    // visibly loading — likely because the JS interop callback type
    // mismatches under hls.js's specific event signature in some
    // browser versions. The DOM <video> element's `playing` event is
    // bullet-proof: it fires the instant the first frame is decoded
    // and rendered, which is the only thing the user actually cares
    // about. Either signal flips the flag, whichever arrives first.
    _video.onPlaying.listen((_) {
      if (!mounted) return;
      if (_waitingForFirstManifest) {
        setState(() => _waitingForFirstManifest = false);
      }
      // Recovered from cold start — reset the retry counter so the
      // next transient segment 404 (which will happen eventually as
      // SRS rotates segments) gets a fresh budget.
      _manifestRetries = 0;
    });
    _video.onError.listen((_) {
      if (!mounted) return;
      setState(() => _error = 'Lỗi phát video');
      widget.onError?.call();
    });

    _visibilitySub = web.document.onVisibilityChange.listen((_) {
      if (!mounted) return;
      if (web.document.visibilityState == 'hidden') {
        _hiddenAt = DateTime.now();
      } else if (web.document.visibilityState == 'visible') {
        final wasHiddenFor = _hiddenAt == null
            ? Duration.zero
            : DateTime.now().difference(_hiddenAt!);
        _hiddenAt = null;
        // Always reattach when coming back from an error state, or after
        // any meaningful background period — startLoad() is unreliable
        // once SRS's hls_window (4s) has rolled past us.
        if (_error != null || wasHiddenFor.inSeconds >= 3) {
          _reattach();
        } else {
          _resumeFromLiveEdge();
        }
      }
    });

    ui_web.platformViewRegistry.registerViewFactory(
      _viewType,
      (int _) => _video,
    );

    _attach();
  }

  void _resumeFromLiveEdge() {
    final hls = _hls;
    if (hls != null) {
      try { hls.startLoad(); } catch (_) {}
    }
    // Chrome pauses <video> when the tab is hidden; explicitly resume it
    // on visibility. Wrapped because play() returns a Promise that can
    // reject (browser autoplay policy) and Dart's JS interop would surface
    // that as an unhandled error otherwise.
    try { _video.play(); } catch (_) {}
  }

  // Full teardown + reconnect. Used when the tab was hidden long enough
  // for SRS to have purged the segments we held, or after any fatal hls.js
  // error. Clears _error so the UI flips back to the player widget.
  void _reattach() {
    if (!mounted) return;
    _mediaRecoverTries = 0;
    _networkRecoverTries = 0;
    _manifestRetries = 0;
    _manifestRetryTimer?.cancel();
    _manifestRetryTimer = null;
    // Treat the reattach itself as a fresh cold-start, so the loading
    // placeholder shows up again instead of "Lỗi phát video" briefly
    // flashing while hls.js downloads the manifest the second time.
    setState(() {
      _error = null;
      _waitingForFirstManifest = true;
    });
    try { _hls?.destroy(); } catch (_) {}
    _hls = null;
    try { _video.pause(); } catch (_) {}
    _video.removeAttribute('src');
    try { _video.load(); } catch (_) {}
    _attach();
  }

  void _attach() {
    final canNative = _video.canPlayType('application/vnd.apple.mpegurl').isNotEmpty;
    // Safari / iOS: native HLS works, skip hls.js.
    if (canNative) {
      _video.src = widget.hlsUrl;
      return;
    }
    // Other browsers: need hls.js loaded by index.html. If the global is
    // missing (offline, blocked CDN) fall back to native and let the
    // browser report the same DEMUXER error we used to see.
    if (_hlsCtor == null || !_hlsIsSupported()) {
      // hls.js missing (offline, blocked CDN). Native HLS will fail on
      // Chrome but that's the same state we had before this widget.
      // ignore: avoid_print
      print('[HlsViewerWeb] hls.js not available — falling back to native');
      _video.src = widget.hlsUrl;
      return;
    }
    final hls = HlsJs(
      {
        // Live tuning, smoothness > latency. Trades ~5s extra glass-to-glass
        // latency (5s → ~10s) for resilience against weak/jittery mobile
        // networks — same range Shopee/TikTok Live operate in. Without
        // these buffers a 3G blip surfaces as "Lỗi phát video" instead of
        // a brief stall.
        //   liveSyncDurationCount 5: target playback ~5 segments behind
        //     the live edge (10s at 2s fragments). Was 3 → 6s.
        //   liveMaxLatencyDurationCount 15: only force a seek-to-edge if
        //     we fall >30s behind. Tolerates longer stalls without a hard
        //     jump.
        //   maxBufferLength 30: download up to 30s ahead when bandwidth
        //     allows. Was 10 → ran out fast on Wi-Fi blips.
        //   maxMaxBufferLength 60: hard ceiling so we don't OOM on
        //     desktop browsers with infinite RAM.
        //   backBufferLength 30: keep 30s behind for instant seek-back
        //     after a stall. Was 4 → player had to re-fetch from the
        //     server on every recovery.
        'liveSyncDurationCount': 5,
        'liveMaxLatencyDurationCount': 15,
        'maxBufferLength': 30,
        'maxMaxBufferLength': 60,
        'lowLatencyMode': false,
        'backBufferLength': 30,
        // SRS tags every segment with #EXT-X-DISCONTINUITY because the
        // RTMP encoder (apivideo_live_stream) ships short GOPs, and SRS
        // honors each keyframe boundary as a discontinuity. Without
        // these tweaks hls.js re-inits the decoder on every segment →
        // visible stall after ~30s ("Lỗi phát video" mid-stream).
        //   appendErrorMaxRetry: retry mp4 append on transient errors
        //     instead of giving up the first time.
        //   nudgeOffset / nudgeMaxRetry: when the player stalls at a
        //     discontinuity, nudge forward a tiny bit and retry — gets
        //     past the boundary without a full re-init.
        //   stretchShortVideoTrack: smooth over audio/video drift that
        //     piles up across many discontinuities.
        'appendErrorMaxRetry': 5,
        'nudgeOffset': 0.2,
        'nudgeMaxRetry': 10,
        'stretchShortVideoTrack': true,
        // hls.js's built-in retry defaults are absurdly low for live
        // streaming against a server that's still warming up:
        //   manifestLoadingMaxRetry default = 1 (!)
        //   levelLoadingMaxRetry    default = 4
        //   fragLoadingMaxRetry     default = 6
        // SRS rotates segments every 2s and only keeps a 60s window — a
        // client that drifts a bit, or a card preview that's been off-
        // screen briefly, will see fragLoadError on the segment it
        // optimistically requested before SRS moved on. Bump everything
        // to 10 retries with a 500ms base delay (× exponential backoff)
        // so we ride through cold-start + segment rotation without ever
        // bubbling fatal up to Flutter.
        'manifestLoadingMaxRetry': 10,
        'manifestLoadingRetryDelay': 500,
        'manifestLoadingMaxRetryTimeout': 8000,
        'levelLoadingMaxRetry': 10,
        'levelLoadingRetryDelay': 500,
        'levelLoadingMaxRetryTimeout': 8000,
        'fragLoadingMaxRetry': 10,
        'fragLoadingRetryDelay': 500,
        'fragLoadingMaxRetryTimeout': 8000,
      }.jsify() as JSObject?,
    );
    hls.on('hlsError', ((JSAny _, JSObject data) {
      final fatal = (data.getProperty('fatal'.toJS) as JSBoolean?)?.toDart ?? false;
      final type = (data.getProperty('type'.toJS) as JSString?)?.toDart ?? '';
      final details = (data.getProperty('details'.toJS) as JSString?)?.toDart ?? '';
      // Log every hls.js error to the browser console so we have something
      // to look at in DevTools when a viewer reports "Lỗi phát video".
      // ignore: avoid_print
      print('[HlsViewerWeb] hlsError fatal=$fatal type=$type details=$details');
      // Transient SRS-publishing-window errors. Three flavors all
      // collapse to "try again in a moment":
      //   1. Cold start — buyer opened the room before SRS had published
      //      the first .m3u8 yet (manifestLoadError, 404 on the playlist).
      //   2. Level miss — playlist exists but the variant level URL just
      //      rotated (levelLoadError, levelLoadTimeOut).
      //   3. Segment 404 — the .ts we asked for rolled out of the
      //      hls_window before our request landed at SRS (fragLoadError).
      //      Common when a card preview wakes back up off-screen or when
      //      a viewer joins mid-stream and hls.js requests a segment from
      //      a stale playlist response.
      // In all three cases the right move is the same: pause briefly,
      // ask hls.js to re-fetch the playlist (startLoad walks back to the
      // freshest segment), and keep the spinner up rather than flipping
      // to "Lỗi phát video". 10-try budget × 2s = 20s of grace.
      final isTransient = details == 'manifestLoadError' ||
          details == 'manifestLoadTimeOut' ||
          details == 'levelLoadError' ||
          details == 'levelLoadTimeOut' ||
          details == 'fragLoadError' ||
          details == 'fragLoadTimeOut';
      if (isTransient && _manifestRetries < _manifestRetryBudget) {
        _manifestRetries++;
        _manifestRetryTimer?.cancel();
        _manifestRetryTimer = Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          try { hls.startLoad(); } catch (_) {}
        });
        return;
      }
      if (!fatal) return;
      // hls.js docs: fatal media/network errors are recoverable as long as
      // the server is still up. Two-strikes policy — recover once, but if
      // the same error fires again give up so we don't loop forever on a
      // stream the host actually ended.
      if (type == 'mediaError' && _mediaRecoverTries < 2) {
        _mediaRecoverTries++;
        try { hls.recoverMediaError(); } catch (_) {}
        return;
      }
      if (type == 'networkError' && _networkRecoverTries < 2) {
        _networkRecoverTries++;
        try { hls.startLoad(); } catch (_) {}
        return;
      }
      if (mounted && _error == null) {
        // Surface the hls.js detail so a developer (or curious user) can
        // tell `bufferStalledError` from `manifestLoadError` without
        // digging through console output.
        setState(() => _error = details.isEmpty
            ? 'Stream lỗi hoặc đã kết thúc'
            : 'Stream lỗi: $details');
        widget.onError?.call();
      }
    }).toJS);
    // Once the first level loads we know SRS is publishing — clear the
    // cold-start flag so the loading placeholder hides and subsequent
    // manifest misses (rare) are treated as real errors not first-attach.
    hls.on('hlsLevelLoaded', ((JSAny _, JSObject __) {
      if (!mounted) return;
      _manifestRetries = 0;
      _manifestRetryTimer?.cancel();
      if (_waitingForFirstManifest) {
        setState(() => _waitingForFirstManifest = false);
      }
    }).toJS);
    hls.loadSource(widget.hlsUrl);
    hls.attachMedia(_video);
    _hls = hls;
  }

  @override
  void didUpdateWidget(covariant HlsViewerWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hlsUrl != widget.hlsUrl) {
      _hls?.destroy();
      _hls = null;
      _attach();
    }
    if (oldWidget.fit != widget.fit) {
      _video.style.objectFit = widget.fit == BoxFit.cover ? 'cover' : 'contain';
    }
  }

  @override
  void dispose() {
    _visibilitySub?.cancel();
    _visibilitySub = null;
    _manifestRetryTimer?.cancel();
    _manifestRetryTimer = null;
    try { _hls?.destroy(); } catch (_) {}
    _hls = null;
    try { _video.pause(); } catch (_) {}
    _video.src = '';
    super.dispose();
  }

  Future<void> _retry() async {
    if (widget.onRetry != null) {
      // Let the parent re-resolve the playback URL before we rebuild the
      // player. If the session was force-ended server-side or SRS rotated
      // the playlist, reattaching to the stale URL would just fail again.
      if (mounted) setState(() => _error = null);
      try {
        await widget.onRetry!();
      } catch (_) {/* parent will surface its own error via state */}
      // didUpdateWidget handles the actual hls.js teardown + reattach when
      // hlsUrl changes. If the URL hasn't changed (same session, just a
      // transient blip) we still want to rebuild — call _reattach as a
      // final fallback.
      if (mounted && _error == null) _reattach();
      return;
    }
    _reattach();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off, color: Colors.white38, size: 48),
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                label: const Text('Thử lại',
                    style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    }
    // The <video> element is mounted via HtmlElementView and must stay in
    // the tree from frame 1 — hls.js needs an attached media element to
    // drive MSE buffering. The cold-start loading state is layered on top
    // with a Stack so it can fade out the moment the first manifest
    // parses, without ever tearing the <video> out of the DOM.
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: _aspect,
              child: HtmlElementView(viewType: _viewType),
            ),
          ),
          if (_waitingForFirstManifest)
            Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      color: Colors.white70,
                      strokeWidth: 2.5,
                    ),
                  ),
                  SizedBox(height: 14),
                  Text(
                    'Đang kết nối live...',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
