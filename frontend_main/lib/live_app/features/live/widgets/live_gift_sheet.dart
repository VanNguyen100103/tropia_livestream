// =============================================================================
// live_gift_sheet.dart
// =============================================================================
// Bottom sheet chọn & tặng quà cho host (Shopee Live style).
// Map đúng LIVESTREAM_API.md §8:
//   GET  /api/live/gifts        → danh mục quà
//   POST /api/live/gift/send    → trừ điểm loyalty + gửi quà
// =============================================================================

import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/data/live_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/models/live_stream_model.dart';

class LiveGiftSheet extends StatefulWidget {
  /// stream_key của phiên đang xem (bắt buộc để gọi gift/send).
  final String streamKey;

  /// Gọi sau khi tặng thành công — để màn hình live hiển thị overlay quà.
  final void Function(LiveGiftSent gift)? onSent;

  const LiveGiftSheet({super.key, required this.streamKey, this.onSent});

  /// Mở sheet. Không làm gì nếu [streamKey] rỗng.
  static Future<void> show(
    BuildContext context,
    String? streamKey, {
    void Function(LiveGiftSent gift)? onSent,
  }) {
    if (streamKey == null || streamKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chưa sẵn sàng tặng quà, vui lòng thử lại')),
      );
      return Future.value();
    }
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => LiveGiftSheet(streamKey: streamKey, onSent: onSent),
    );
  }

  @override
  State<LiveGiftSheet> createState() => _LiveGiftSheetState();
}

class _LiveGiftSheetState extends State<LiveGiftSheet> {
  List<LiveGiftCatalogItem> _gifts = const [];
  LiveGiftCatalogItem? _selected;
  int _quantity = 1;
  bool _loading = true;
  bool _sending = false;
  int? _pointsRemaining;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await LiveRepository.instance.fetchGiftCatalog();
    if (!mounted) return;
    setState(() {
      _gifts = items;
      _selected = items.isNotEmpty ? items.first : null;
      _loading = false;
    });
  }

  Future<void> _send() async {
    final gift = _selected;
    if (gift == null || _sending) return;
    setState(() => _sending = true);
    try {
      final res = await LiveRepository.instance.sendGift(
        streamKey: widget.streamKey,
        giftId: gift.id,
        quantity: _quantity,
      );
      if (!mounted) return;
      setState(() => _pointsRemaining = res.pointsRemaining);
      widget.onSent?.call(res.gift);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Đã tặng ${_quantity}x ${gift.name} 🎉')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AuthService.errorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Text(
              'Tặng quà',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (_pointsRemaining != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Điểm còn lại: $_pointsRemaining',
                    style: const TextStyle(color: Colors.white60, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_gifts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text('Chưa có quà', style: TextStyle(color: Colors.white60)),
                ),
              )
            else
              GridView.count(
                crossAxisCount: 4,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
                children: _gifts.map(_buildGiftTile).toList(),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                _qtyButton(Icons.remove, () {
                  if (_quantity > 1) setState(() => _quantity--);
                }),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('$_quantity',
                      style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                _qtyButton(Icons.add, () {
                  if (_quantity < 99) setState(() => _quantity++);
                }),
                const Spacer(),
                ElevatedButton(
                  onPressed: (_selected == null || _sending) ? null : _send,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_selected == null
                          ? 'Tặng'
                          : 'Tặng • ${(_selected!.pointCost * _quantity)} điểm'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _buildGiftTile(LiveGiftCatalogItem gift) {
    final selected = _selected?.id == gift.id;
    return GestureDetector(
      onTap: () => setState(() => _selected = gift),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.18) : Colors.white10,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppColors.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(gift.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 2),
            Text(gift.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
            Text('${gift.pointCost}',
                style: const TextStyle(color: Colors.amber, fontSize: 11, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
