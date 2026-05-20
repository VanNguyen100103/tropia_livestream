import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import 'package:tropia/features/live/models/live_stream_model.dart';
import 'package:tropia/features/live/services/srs_service.dart';
import 'package:tropia/features/live/widgets/rtmp_publish_info.dart';

/// MVP host screen for SRS-based live streaming.
///
/// The seller creates a stream via the Go backend and is shown the
/// RTMP/WHIP/SRT URLs. They push the actual video from OBS or Larix
/// Broadcaster. In-app camera publish (apivideo_live_stream) can be added
/// later — see lib/features/live/FLUTTER_PORT_TODO.md.
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
  StreamInfo? _session;
  PublishURLs? _publish;
  String? _error;
  bool _loading = true;

  late final SrsService _srs;

  @override
  void initState() {
    super.initState();
    _srs = SrsService(dio: _buildDio());
    _createStream();
  }

  Dio _buildDio() {
    // TODO: inject from app-wide Dio (with auth interceptor)
    return Dio(BaseOptions(baseUrl: 'http://10.0.2.2:3000'));
  }

  Future<void> _createStream() async {
    try {
      final res = await _srs.createStream(
        title: widget.title,
        category: widget.category,
        coverImageUrl: widget.thumbnailUrl,
      );
      if (!mounted) return;
      setState(() {
        _session = res.session;
        _publish = res.publish;
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
    if (_session == null) {
      Navigator.of(context).pop();
      return;
    }
    try {
      await _srs.endStream(_session!.id);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Phát livestream'),
        actions: [
          if (_session != null)
            TextButton(
              onPressed: _endStream,
              child: const Text('Kết thúc', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 56, color: Colors.red),
            const SizedBox(height: 12),
            Text('Không tạo được stream:\n$_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _createStream();
              },
              child: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_publish != null && _session != null)
            RtmpPublishInfo(publish: _publish!, streamId: _session!.id),
          const Divider(height: 32),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stream: ${_session?.title ?? '-'}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  'Trạng thái: ${_session?.status ?? '-'}',
                  style: const TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  'Sản phẩm: ${widget.products.length} • Voucher: ${widget.coupons.length}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
