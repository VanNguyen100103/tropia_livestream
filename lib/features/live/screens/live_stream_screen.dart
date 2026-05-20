import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/features/live/data/live_repository.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';
import 'package:tropia/features/live/providers/live_provider.dart';
import 'package:tropia/features/live/widgets/hls_viewer.dart';
import 'package:tropia/features/live/widgets/live_actions_widget.dart';
import 'package:tropia/features/live/widgets/live_chat_widget.dart';
import 'package:tropia/features/live/widgets/live_product_card_widget.dart';
import 'package:tropia/features/live/widgets/live_product_popup.dart';

/// Full viewer screen for an SRS live stream.
///
/// Stack:
///   - [HlsViewer]              fills the background.
///   - Top bar                  back arrow + seller + LIVE badge + viewer count.
///   - Floating product card    bottom-left (taps open [LiveProductPopup]).
///   - [LiveChatWidget]         bottom, last 180 px of comments.
///   - [LiveActionsWidget]      right side (like / share / comment / follow).
///
/// All overlays read state from [LiveProvider], which polls the Go backend.
class LiveStreamScreen extends StatefulWidget {
  final String streamId;

  const LiveStreamScreen({super.key, required this.streamId});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  String? _hlsUrl;
  String? _error;
  bool _loading = true;
  LiveStream? _stream;

  late final LiveProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = context.read<LiveProvider>();
    _provider.onSessionEnded = _handleSessionEnded;
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final res = await LiveRepository.instance.fetchPlayback(widget.streamId);
      final playback = res['playback'] as Map<String, dynamic>;
      final hls = (playback['hls'] as String?) ?? '';

      await LiveRepository.instance.joinAsViewer(widget.streamId);
      await _provider.openStream(widget.streamId);

      if (!mounted) return;
      setState(() {
        _hlsUrl = hls.isEmpty ? null : hls;
        _stream = _provider.currentStream;
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

  void _handleSessionEnded() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Buổi live đã kết thúc')),
    );
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _provider.onSessionEnded = null;
    LiveRepository.instance.leaveAsViewer(widget.streamId).catchError((_) {});
    _provider.closeStream();
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
      return const Center(child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null) {
      return _ErrorState(
        message: _error!,
        onRetry: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          _bootstrap();
        },
      );
    }

    return Consumer<LiveProvider>(
      builder: (context, provider, _) {
        final stream = provider.currentStream ?? _stream;
        if (stream == null) {
          return const Center(
            child: Text('Stream không khả dụng',
                style: TextStyle(color: Colors.white70)),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Video
            if (_hlsUrl != null)
              HlsViewer(hlsUrl: _hlsUrl!)
            else
              Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: const Text(
                  'Stream chưa sẵn sàng',
                  style: TextStyle(color: Colors.white70),
                ),
              ),

            // Top bar
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _TopBar(stream: stream),
            ),

            // Pinned product card (bottom-left, above chat)
            if (stream.products.isNotEmpty)
              Positioned(
                left: 12,
                bottom: 220,
                width: 220,
                child: LiveProductCardWidget(
                  product: stream.products.first,
                  streamId: stream.id,
                  onTap: () => _showProductPopup(stream.products.first, stream.id),
                  onBuyNow: () => provider.buyNow(stream.id, stream.products.first.id),
                ),
              ),

            // Right-side actions
            Positioned(
              right: 6,
              bottom: 120,
              child: LiveActionsWidget(
                stream: stream,
                onLike: () => provider.toggleLike(stream.id),
                onShare: () {},
                onCommentTap: () {},
                onFollowTap: () => provider.toggleFollow(stream.id),
              ),
            ),

            // Chat at bottom
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.black.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: LiveChatWidget(comments: stream.comments),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showProductPopup(LiveProduct product, String streamId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => LiveProductPopup(
        product: product,
        onBuyNow: (skuId) {
          Navigator.of(sheetCtx).pop();
          if (skuId != null) {
            _provider.buySkuNow(streamId, product.id, skuId);
          } else {
            _provider.buyNow(streamId, product.id);
          }
        },
        onAddToCart: (skuId) {
          Navigator.of(sheetCtx).pop();
          if (skuId != null) {
            _provider.addSkuToCart(streamId, product.id, skuId, 1);
          } else {
            _provider.addToCart(streamId, product.id);
          }
        },
        onClose: () => Navigator.of(sheetCtx).pop(),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final LiveStream stream;
  const _TopBar({required this.stream});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        ClipOval(
          child: Image.network(
            stream.sellerAvatarUrl,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              width: 36, height: 36, color: Colors.grey,
              child: const Icon(Icons.person, color: Colors.white70),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                stream.sellerName,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${_formatViewers(stream.viewerCount)} đang xem',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'LIVE',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  String _formatViewers(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
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
            const Icon(Icons.error_outline, color: Colors.white, size: 56),
            const SizedBox(height: 12),
            Text(
              'Không vào được phòng:\n$message',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
