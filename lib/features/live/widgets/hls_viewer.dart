import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// HLS player for SRS-produced .m3u8 streams.
///
/// Works on Android, iOS, Web (via Shaka/HLS.js auto-detection by video_player).
class HlsViewer extends StatefulWidget {
  final String hlsUrl;
  final VoidCallback? onReady;
  final VoidCallback? onError;
  final bool autoplay;

  const HlsViewer({
    super.key,
    required this.hlsUrl,
    this.onReady,
    this.onError,
    this.autoplay = true,
  });

  @override
  State<HlsViewer> createState() => _HlsViewerState();
}

class _HlsViewerState extends State<HlsViewer> {
  VideoPlayerController? _controller;
  ChewieController? _chewie;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.hlsUrl));
      await ctrl.initialize();
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
      if (mounted) {
        setState(() {});
        widget.onReady?.call();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
        widget.onError?.call();
      }
    }
  }

  @override
  void didUpdateWidget(covariant HlsViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hlsUrl != widget.hlsUrl) {
      _disposePlayer();
      _init();
    }
  }

  void _disposePlayer() {
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
    if (_error != null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Không thể phát video.\n$_error',
            style: const TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (_chewie == null) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Colors.white70),
      );
    }
    return Chewie(controller: _chewie!);
  }
}
