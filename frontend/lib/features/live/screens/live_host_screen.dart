import 'package:apivideo_live_stream/apivideo_live_stream.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:tropia/features/live/data/live_repository.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';
import 'package:tropia/features/live/widgets/rtmp_publish_info.dart';

/// Host screen — supports two ways to publish:
///   1. **Mobile camera** (tab 1): app captures camera + mic and pushes
///      RTMP directly to SRS via `apivideo_live_stream`. Shopee-Live style.
///   2. **External encoder** (tab 2): show RTMP / WHIP / SRT URLs so the
///      seller can publish from OBS / Larix Broadcaster / etc.
///
/// Both modes target the same stream key returned by `LiveRepository.startLive`.
class LiveHostScreen extends StatefulWidget {
  final String title;
  final String category;
  final List<LiveProduct> products;
  final String? thumbnailUrl;
  final List<Map<String, dynamic>> coupons;

  const LiveHostScreen({
    super.key,
    required this.title,
    required this.category,
    required this.products,
    this.thumbnailUrl,
    this.coupons = const [],
  });

  @override
  State<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends State<LiveHostScreen> {
  Map<String, dynamic>? _session;
  PublishURLs? _publish;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _createStream();
  }

  Future<void> _createStream() async {
    try {
      final res = await LiveRepository.instance.startLive(
        title:         widget.title,
        category:      widget.category,
        coverImageUrl: widget.thumbnailUrl,
      );
      if (!mounted) return;
      setState(() {
        _session = res['session'] as Map<String, dynamic>?;
        final publishJson = res['publish'] as Map<String, dynamic>?;
        _publish = publishJson != null ? PublishURLs.fromJson(publishJson) : null;
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

  Future<void> _endStream() async {
    final sessionId = _session?['id'] as String?;
    if (sessionId == null) {
      Navigator.of(context).pop();
      return;
    }
    try {
      await LiveRepository.instance.endLive(sessionId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Phát livestream'),
          actions: [
            if (_session != null)
              TextButton(
                onPressed: _endStream,
                child: const Text('Kết thúc', style: TextStyle(color: Colors.red)),
              ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.videocam), text: 'Phát từ điện thoại'),
              Tab(icon: Icon(Icons.desktop_windows), text: 'Phát từ OBS'),
            ],
          ),
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: () {
        setState(() { _loading = true; _error = null; });
        _createStream();
      });
    }
    final sessionId = _session?['id'] as String? ?? '';
    return TabBarView(
      children: [
        _MobilePublisherTab(rtmpUrl: _publish?.rtmp ?? '', sessionId: sessionId),
        _ExternalEncoderTab(
          publish:       _publish,
          sessionId:     sessionId,
          sessionTitle:  _session?['title'] as String? ?? '-',
          sessionStatus: _session?['status'] as String? ?? '-',
          productCount:  widget.products.length,
          couponCount:   widget.coupons.length,
        ),
      ],
    );
  }
}

// ─── Tab 1: in-app camera publisher (Shopee Live style) ─────────────────────

class _MobilePublisherTab extends StatefulWidget {
  final String rtmpUrl;
  final String sessionId;

  const _MobilePublisherTab({required this.rtmpUrl, required this.sessionId});

  @override
  State<_MobilePublisherTab> createState() => _MobilePublisherTabState();
}

class _MobilePublisherTabState extends State<_MobilePublisherTab> {
  ApiVideoLiveStreamController? _ctrl;
  bool _initializing = true;
  bool _isLive = false;
  bool _permGranted = false;
  String? _initError;
  CameraPosition _cam = CameraPosition.back;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final cam = await Permission.camera.request();
    final mic = await Permission.microphone.request();
    if (!cam.isGranted || !mic.isGranted) {
      if (!mounted) return;
      setState(() {
        _permGranted = false;
        _initializing = false;
      });
      return;
    }

    try {
      _ctrl = ApiVideoLiveStreamController(
        initialAudioConfig: AudioConfig(),
        initialVideoConfig: VideoConfig.withDefaultBitrate(),
        initialCameraPosition: _cam,
        onError: (e) {
          if (mounted) setState(() => _initError = e.toString());
        },
      );
      await _ctrl!.initialize();
      if (!mounted) return;
      setState(() {
        _permGranted = true;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initError = e.toString();
        _initializing = false;
      });
    }
  }

  Future<void> _toggleLive() async {
    if (_ctrl == null) return;
    try {
      if (_isLive) {
        await _ctrl!.stopStreaming();
        setState(() => _isLive = false);
      } else {
        // Parse rtmp://host:port/app/streamKey → server + key
        final uri = Uri.parse(widget.rtmpUrl);
        final server = 'rtmp://${uri.host}:${uri.port}${_appPath(uri.path)}';
        final streamKey = _streamKeyOf(uri.path);
        if (streamKey.isEmpty) {
          throw 'Stream key trống';
        }
        await _ctrl!.startStreaming(streamKey: streamKey, url: server);
        setState(() => _isLive = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_ctrl == null) return;
    final next = _cam == CameraPosition.back ? CameraPosition.front : CameraPosition.back;
    await _ctrl!.setCameraPosition(next);
    setState(() => _cam = next);
  }

  /// rtmp://host:port/live/streamkey → "/live"
  String _appPath(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.isNotEmpty ? '/${parts.first}' : '/live';
  }

  /// rtmp://host:port/live/streamkey → "streamkey"
  String _streamKeyOf(String path) {
    final parts = path.split('/').where((s) => s.isNotEmpty).toList();
    return parts.length >= 2 ? parts.last : '';
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_permGranted) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.videocam_off, size: 56, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Tropia cần quyền Camera & Microphone để live.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: openAppSettings, child: const Text('Mở cài đặt')),
          ],
        ),
      );
    }
    if (_initError != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 12),
            Text('Không khởi động được camera:\n$_initError', textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: Colors.black),
        if (_ctrl != null)
          ApiVideoCameraPreview(controller: _ctrl!),

        // LIVE badge
        if (_isLive)
          Positioned(
            top: 16, left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.fiber_manual_record, color: Colors.white, size: 14),
                  SizedBox(width: 4),
                  Text('LIVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),

        // Side controls (switch cam)
        Positioned(
          right: 16, top: 80,
          child: Column(
            children: [
              _circleBtn(Icons.flip_camera_ios, _switchCamera),
            ],
          ),
        ),

        // Big start / stop button
        Positioned(
          left: 0, right: 0, bottom: 32,
          child: Center(
            child: ElevatedButton.icon(
              onPressed: widget.rtmpUrl.isEmpty ? null : _toggleLive,
              icon: Icon(_isLive ? Icons.stop : Icons.play_arrow),
              label: Text(_isLive ? 'Dừng phát' : 'Bắt đầu live'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isLive ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _circleBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(28),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

// ─── Tab 2: external encoder (OBS / Larix) ─────────────────────────────────

class _ExternalEncoderTab extends StatelessWidget {
  final PublishURLs? publish;
  final String sessionId;
  final String sessionTitle;
  final String sessionStatus;
  final int productCount;
  final int couponCount;

  const _ExternalEncoderTab({
    required this.publish,
    required this.sessionId,
    required this.sessionTitle,
    required this.sessionStatus,
    required this.productCount,
    required this.couponCount,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (publish != null && sessionId.isNotEmpty)
            RtmpPublishInfo(publish: publish!, streamId: sessionId),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Stream: $sessionTitle',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('Trạng thái: $sessionStatus', style: const TextStyle(color: Colors.black54)),
                const SizedBox(height: 4),
                Text('Sản phẩm: $productCount • Voucher: $couponCount',
                    style: const TextStyle(color: Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 12),
            Text('Không tạo được stream:\n$message', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
