// =============================================================================
// live_gift_overlay.dart
// =============================================================================
// Overlay hiệu ứng quà (Shopee/TikTok Live style):
//   - Banner "{tên} tặng {emoji} x{n}" trượt vào từ trái, giữ, rồi mờ dần.
//   - Emoji quà bay lên + phóng to rồi tan.
// Nguồn dữ liệu:
//   - Poll GET /api/live/gifts/recent mỗi ~2.5s (realtime cho quà người khác).
//   - addGift() được gọi ngay khi chính người dùng tặng (phản hồi tức thì).
// =============================================================================

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/data/live_repository.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/models/live_stream_model.dart';

class LiveGiftOverlay extends StatefulWidget {
  /// stream_key của phiên đang xem. Null/đổi → reset poll.
  final String? streamKey;

  const LiveGiftOverlay({super.key, this.streamKey});

  @override
  State<LiveGiftOverlay> createState() => LiveGiftOverlayState();
}

class LiveGiftOverlayState extends State<LiveGiftOverlay> {
  static const _pollInterval = Duration(milliseconds: 2500);

  Timer? _timer;
  int _lastId = 0;
  bool _primed = false; // bỏ qua lịch sử ở lần poll đầu (không replay)
  int _seq = 0;         // khoá widget duy nhất cho mỗi hiệu ứng

  final List<_OverlayItem> _banners = [];
  final List<_OverlayItem> _floats = [];

  @override
  void initState() {
    super.initState();
    _restartPoll();
  }

  @override
  void didUpdateWidget(covariant LiveGiftOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.streamKey != widget.streamKey) {
      _primed = false;
      _lastId = 0;
      _restartPoll();
    }
  }

  void _restartPoll() {
    _timer?.cancel();
    final key = widget.streamKey;
    if (key == null || key.isEmpty) return;
    _poll();
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _poll() async {
    final key = widget.streamKey;
    if (key == null || key.isEmpty) return;
    final gifts = await LiveRepository.instance.fetchRecentGifts(key, limit: 20);
    if (!mounted || gifts.isEmpty) return;

    final maxId = gifts.map((g) => g.id).reduce(max);
    if (!_primed) {
      // Lần đầu: chỉ ghi mốc, không phát lại quà cũ.
      _primed = true;
      _lastId = maxId;
      return;
    }
    // gifts mới nhất trước → lọc cái mới hơn _lastId, phát theo thứ tự cũ→mới.
    final fresh = gifts.where((g) => g.id > _lastId).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    for (final g in fresh) {
      _spawn(g);
    }
    if (maxId > _lastId) _lastId = maxId;
  }

  /// Phát hiệu ứng ngay cho quà vừa do chính người dùng tặng.
  void addGift(LiveGiftSent gift) {
    if (gift.id > _lastId) _lastId = gift.id;
    _spawn(gift);
  }

  void _spawn(LiveGiftSent gift) {
    if (!mounted) return;
    final id = _seq++;
    setState(() {
      _banners.add(_OverlayItem(id, gift));
      _floats.add(_OverlayItem(id, gift));
    });
  }

  void _removeBanner(int id) {
    if (!mounted) return;
    setState(() => _banners.removeWhere((e) => e.id == id));
  }

  void _removeFloat(int id) {
    if (!mounted) return;
    setState(() => _floats.removeWhere((e) => e.id == id));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          // Banner xếp chồng phía dưới-trái.
          Positioned(
            left: 12,
            bottom: 160,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final item in _banners)
                  _GiftBanner(
                    key: ValueKey('banner_${item.id}'),
                    gift: item.gift,
                    onDone: () => _removeBanner(item.id),
                  ),
              ],
            ),
          ),
          // Emoji bay lên (giữa-dưới).
          for (final item in _floats)
            _FloatingGift(
              key: ValueKey('float_${item.id}'),
              gift: item.gift,
              onDone: () => _removeFloat(item.id),
            ),
        ],
      ),
    );
  }
}

class _OverlayItem {
  final int id;
  final LiveGiftSent gift;
  _OverlayItem(this.id, this.gift);
}

// ─── Banner trượt vào + giữ + mờ ────────────────────────────────────────────

class _GiftBanner extends StatefulWidget {
  final LiveGiftSent gift;
  final VoidCallback onDone;
  const _GiftBanner({super.key, required this.gift, required this.onDone});

  @override
  State<_GiftBanner> createState() => _GiftBannerState();
}

class _GiftBannerState extends State<_GiftBanner> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        })
        ..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gift;
    // 0–0.12 trượt vào, 0.12–0.82 giữ, 0.82–1 mờ ra.
    final slide = CurvedAnimation(parent: _c, curve: const Interval(0, 0.12, curve: Curves.easeOut));
    final fade = CurvedAnimation(parent: _c, curve: const Interval(0.82, 1, curve: Curves.easeIn));
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        return Opacity(
          opacity: 1 - fade.value,
          child: Transform.translate(
            offset: Offset(-220 * (1 - slide.value), 0),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: child,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xCCFF6B6B), Color(0x66FF6B6B)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              backgroundImage: (g.senderAvatar.isNotEmpty)
                  ? NetworkImage(g.senderAvatar)
                  : null,
              child: g.senderAvatar.isEmpty
                  ? const Icon(Icons.person, size: 18, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  g.senderName.isEmpty ? 'Người xem' : g.senderName,
                  style: const TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Tặng ${g.giftName}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Text(g.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 2),
            Text('x${g.quantity}',
                style: const TextStyle(
                    color: Colors.amberAccent, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ─── Emoji bay lên ───────────────────────────────────────────────────────────

class _FloatingGift extends StatefulWidget {
  final LiveGiftSent gift;
  final VoidCallback onDone;
  const _FloatingGift({super.key, required this.gift, required this.onDone});

  @override
  State<_FloatingGift> createState() => _FloatingGiftState();
}

class _FloatingGiftState extends State<_FloatingGift> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) widget.onDone();
        })
        ..forward();
  late final double _drift = (Random().nextDouble() - 0.5) * 60;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value;
        // pop nhẹ lúc đầu rồi bay lên, mờ dần ở cuối.
        final scale = t < 0.2 ? (0.5 + t * 2.5) : 1.0;
        final opacity = t < 0.8 ? 1.0 : (1 - (t - 0.8) / 0.2);
        return Positioned(
          right: 70 + _drift,
          bottom: 170 + 200 * t,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: Text(widget.gift.emoji, style: const TextStyle(fontSize: 40)),
            ),
          ),
        );
      },
    );
  }
}
