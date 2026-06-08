// =============================================================================
// vod_replay_screen.dart
// =============================================================================
// Plays the recorded MP4 of an ended livestream.
//
// All chat / pin / coupon / bot / product-list overlays are BAKED into
// the MP4 server-side by the worker (cmd/worker + internal/vod). This
// screen therefore needs zero overlay rendering — just a video player.
// =============================================================================

import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/data/live_repository.dart';

const _tag = 'VodReplayScreen';

class VodReplayScreen extends StatefulWidget {
  final String sessionId;
  final String? title;

  const VodReplayScreen({
    super.key,
    required this.sessionId,
    this.title,
  });

  @override
  State<VodReplayScreen> createState() => _VodReplayScreenState();
}

class _VodReplayScreenState extends State<VodReplayScreen> {
  VideoPlayerController? _video;
  ChewieController? _chewie;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      // Timeline endpoint returns { vod_mp4_url, ... } — we only need
      // the URL. Everything else (chat / events) is already burned into
      // the MP4 by the worker, so we discard the rest.
      final timeline = await LiveRepository.instance.fetchVodTimeline(widget.sessionId);
      if (timeline == null) {
        throw StateError('timeline_unavailable');
      }
      final mp4 = timeline['vod_mp4_url'] as String?;
      if (mp4 == null || mp4.isEmpty) {
        throw StateError('vod_not_ready');
      }

      final vc = VideoPlayerController.networkUrl(Uri.parse(mp4));
      await vc.initialize();
      final cc = ChewieController(
        videoPlayerController: vc,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowMuting: true,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.redAccent,
          handleColor: Colors.redAccent,
          bufferedColor: Colors.white24,
          backgroundColor: Colors.white10,
        ),
      );

      if (!mounted) {
        vc.dispose();
        cc.dispose();
        return;
      }
      setState(() {
        _video = vc;
        _chewie = cc;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.logError(_tag, 'bootstrap failed', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _chewie?.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_error != null) {
      return _ErrorView(message: _errorLabel(_error!), onClose: () => Navigator.maybePop(context));
    }
    final chewie = _chewie;
    if (chewie == null) {
      return const Center(child: Text('Không phát được video', style: TextStyle(color: Colors.white)));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: AspectRatio(
            aspectRatio: _video!.value.aspectRatio == 0 ? 9 / 16 : _video!.value.aspectRatio,
            child: Chewie(controller: chewie),
          ),
        ),
        Positioned(
          top: 8, left: 8, right: 8,
          child: Row(
            children: [
              _CircleIcon(icon: Icons.close, onTap: () => Navigator.maybePop(context)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('REPLAY',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .5)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title ?? '',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _errorLabel(String raw) {
    if (raw.contains('vod_not_ready')) return 'Bản ghi đang được xử lý, thử lại sau.';
    if (raw.contains('timeline_unavailable')) return 'Không lấy được dữ liệu phát lại.';
    return 'Không phát được: $raw';
  }
}

class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onClose;
  const _ErrorView({required this.message, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 16),
            TextButton(onPressed: onClose, child: const Text('Đóng')),
          ],
        ),
      ),
    );
  }
}
