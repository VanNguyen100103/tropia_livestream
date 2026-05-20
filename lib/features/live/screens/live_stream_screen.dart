import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:tropia/features/live/services/srs_service.dart';
import 'package:tropia/features/live/widgets/hls_viewer.dart';

/// MVP viewer screen for SRS-based live streaming.
///
/// Resolves playback URLs from the Go backend, then plays via HLS using
/// `video_player`/`chewie`. Chat / products / voucher / reward overlays
/// from the previous LiveKit-based UI can be re-added on top of HlsViewer.
class LiveStreamScreen extends StatefulWidget {
  final String streamId;

  const LiveStreamScreen({super.key, required this.streamId});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  StreamInfo? _session;
  PlaybackURLs? _playback;
  String? _error;
  bool _loading = true;

  late final SrsService _srs;

  @override
  void initState() {
    super.initState();
    _srs = SrsService(dio: _buildDio());
    _load();
  }

  Dio _buildDio() {
    // TODO: inject from app-wide Dio (with auth interceptor)
    return Dio(BaseOptions(baseUrl: 'http://10.0.2.2:3000'));
  }

  Future<void> _load() async {
    try {
      final res = await _srs.getPlayback(widget.streamId);
      try {
        await _srs.join(widget.streamId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _session = res.session;
        _playback = res.playback;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    if (_session != null) {
      _srs.leave(_session!.id).catchError((_) {});
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(_session?.title ?? 'Live'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 56),
              const SizedBox(height: 12),
              Text(
                'Không vào được phòng:\n$_error',
                style: const TextStyle(color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }
    if (_playback == null || _playback!.hls.isEmpty) {
      return const Center(
        child: Text(
          'Stream chưa sẵn sàng',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        HlsViewer(hlsUrl: _playback!.hls),
        Positioned(
          top: 12,
          left: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }
}
