import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'hls_viewer_web_stub.dart'
    if (dart.library.js_interop) 'hls_viewer_web.dart';

/// HLS player for SRS-produced .m3u8 streams.
///
/// - Android / iOS / desktop: video_player + chewie (HLS is supported
///   natively by ExoPlayer / AVPlayer).
/// - Web: HlsViewerWeb (HtmlElementView + hls.js loaded from index.html).
///   Chrome / Firefox / Edge can't decode HLS natively, so video_player
///   ends up with `DEMUXER_ERROR_COULD_NOT_PARSE`; routing through hls.js
///   fixes it. Safari and iOS Chrome use native playback inside that same
///   widget.
///
/// Layout: viewer is a black box that centers the video at its real aspect
/// ratio — never crops, never zooms.
///
/// [fit] is forwarded to the inner FittedBox (mobile) or `<video>` object-fit
/// (web). Default `BoxFit.contain` keeps the whole frame visible.
class HlsViewer extends StatefulWidget {
  final String hlsUrl;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  // Optional retry handler used by the web error UI. When the buyer view
  // wires this up it re-fetches /streams/:id/playback before rebuilding
  // the player, so a stale URL doesn't trap the user behind a button
  // that just reattaches the same dead playlist.
  final Future<void> Function()? onRetry;
  final bool autoplay;
  final BoxFit fit;

  const HlsViewer({
    super.key,
    required this.hlsUrl,
    this.onReady,
    this.onError,
    this.onRetry,
    this.autoplay = true,
    this.fit = BoxFit.contain,
  });

  @override
  State<HlsViewer> createState() => _HlsViewerState();
}

class _HlsViewerState extends State<HlsViewer> {
  VideoPlayerController? _controller;
  ChewieController? _chewie;
  String? _error;
  // Cold-start retry budget. When a buyer opens the stream before SRS has
  // published the first .m3u8 (5-10s race after seller hits "go live"),
  // VideoPlayerController.initialize() throws with a 404 / source error.
  // Without retry we'd flash "Buổi live đã kết thúc" within a second of
  // opening the room. Instead retry up to 10× with a 2s backoff, showing
  // "Đang kết nối live..." in the meantime.
  int _initRetries = 0;
  static const int _initRetryBudget = 10;
  Timer? _initRetryTimer;

  @override
  void initState() {
    super.initState();
    // On web, HlsViewerWeb handles its own <video> + hls.js lifecycle —
    // don't spin up video_player (which is what produced the demuxer error
    // we're working around in the first place).
    if (!kIsWeb) _init();
  }

  Future<void> _init() async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.hlsUrl));
      // Surface playback errors via _error so the user gets a friendly
      // message instead of Chewie's default red ! icon when the m3u8
      // disappears (stream ended, SRS purged the playlist after
      // hls_dispose, etc.).
      ctrl.addListener(() {
        final err = ctrl.value.errorDescription;
        if (err != null && mounted && _error == null) {
          setState(() => _error = err);
          widget.onError?.call();
        }
      });
      await ctrl.initialize();
      // First playable manifest — reset the cold-start counter so any
      // mid-stream failure later gets the normal "stream ended" UI.
      _initRetries = 0;
      _controller = ctrl;
      _chewie = ChewieController(
        videoPlayerController: ctrl,
        autoPlay: widget.autoplay,
        looping: false,
        aspectRatio: ctrl.value.aspectRatio == 0 ? 9 / 16 : ctrl.value.aspectRatio,
        allowFullScreen: true,
        allowMuting: true,
        showControlsOnInitialize: false,
        showOptions: false,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.redAccent,
          handleColor: Colors.redAccent,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white12,
        ),
      );
      // Live-edge keeper: HLS players will gradually drift behind the live
      // window if the user pauses, scrolls, or has a network blip. Every 5s
      // we check the buffered position and, if we're more than ~3s behind
      // the latest buffered chunk, seek back to the edge.
      ctrl.addListener(_keepAtLiveEdge);
      if (mounted) {
        setState(() {});
        widget.onReady?.call();
      }
    } catch (e) {
      // Cold-start race: SRS hasn't published the .m3u8 yet. ExoPlayer /
      // AVPlayer surface this as a "source error" or 404. Retry quietly
      // with backoff before flipping the UI to an error state — without
      // this the buyer hits "Buổi live đã kết thúc" within a second of
      // opening a stream that's actually about to come up.
      final msg = e.toString().toLowerCase();
      final transient = msg.contains('404') ||
          msg.contains('source') ||
          msg.contains('not found') ||
          msg.contains('mediacodec') ||
          msg.contains('timeout');
      if (transient && _initRetries < _initRetryBudget) {
        _initRetries++;
        _initRetryTimer?.cancel();
        _initRetryTimer = Timer(const Duration(seconds: 2), () {
          if (!mounted) return;
          _init();
        });
        return;
      }
      if (mounted) {
        setState(() => _error = e.toString());
        widget.onError?.call();
      }
    }
  }

  DateTime _lastEdgeCheck = DateTime.fromMillisecondsSinceEpoch(0);
  void _keepAtLiveEdge() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized || !ctrl.value.isPlaying) return;
    final now = DateTime.now();
    if (now.difference(_lastEdgeCheck) < const Duration(seconds: 5)) return;
    _lastEdgeCheck = now;
    final buffered = ctrl.value.buffered;
    if (buffered.isEmpty) return;
    final liveEnd = buffered.last.end;
    final pos = ctrl.value.position;
    final lag = liveEnd - pos;
    // Player is >3s behind the live edge — jump forward. Skipping back to
    // within ~1s of the edge avoids the "always 8s late" drift problem.
    if (lag > const Duration(seconds: 3)) {
      ctrl.seekTo(liveEnd - const Duration(seconds: 1));
    }
  }

  @override
  void didUpdateWidget(covariant HlsViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb) return;
    if (oldWidget.hlsUrl != widget.hlsUrl) {
      _disposePlayer();
      _init();
    }
  }

  void _disposePlayer() {
    _initRetryTimer?.cancel();
    _initRetryTimer = null;
    _controller?.removeListener(_keepAtLiveEdge);
    _chewie?.dispose();
    _controller?.dispose();
    _chewie = null;
    _controller = null;
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return HlsViewerWeb(
        hlsUrl: widget.hlsUrl,
        fit: widget.fit,
        autoplay: widget.autoplay,
        onReady: widget.onReady,
        onError: widget.onError,
        onRetry: widget.onRetry,
      );
    }
    if (_error != null) {
      // 404 / source not found = stream has ended (SRS purged the m3u8
      // after hls_dispose). Show a softer message than a raw stack trace.
      final friendly = _error!.contains('404') ||
              _error!.toLowerCase().contains('not found') ||
              _error!.toLowerCase().contains('source error')
          ? 'Buổi live đã kết thúc.'
          : 'Không thể phát video.\n$_error';
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
                friendly,
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              if (widget.onRetry != null) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () async {
                    if (!mounted) return;
                    setState(() => _error = null);
                    await widget.onRetry!();
                    if (!mounted) return;
                    _disposePlayer();
                    await _init();
                  },
                  icon: const Icon(Icons.refresh, color: Colors.white70, size: 18),
                  label: const Text('Thử lại',
                      style: TextStyle(color: Colors.white70)),
                ),
              ],
            ],
          ),
        ),
      );
    }
    if (_chewie == null) {
      // Spinner + "Đang kết nối live..." — same wording as the web path
      // so buyers see consistent messaging while we either init for the
      // first time or quietly retry against a not-yet-ready SRS playlist.
      return Container(
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
      );
    }
    // Letterbox layout: black background fills the viewer, video is centered
    // and constrained to its real aspect ratio. With `BoxFit.contain` (the
    // default) the video shrinks to fit inside the box — never crops, never
    // overflows. Portrait 9:16 inside a portrait phone shows black bars on
    // top/bottom; landscape 16:9 inside the same phone shows wide black
    // bars top/bottom. On web, `value.size` is sometimes (0,0) right after
    // init even though the stream is playing — fall back to portrait so the
    // player doesn't render as a 1x1 dot.
    final raw = _controller!.value.size;
    final double width  = raw.width  > 0 ? raw.width  : 360.0;
    final double height = raw.height > 0 ? raw.height : 640.0;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: width / height,
          child: FittedBox(
            fit: widget.fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: width,
              height: height,
              child: Chewie(controller: _chewie!),
            ),
          ),
        ),
      ),
    );
  }
}
