// =============================================================================
// live_mini_cart_bag.dart — Floating "túi đồ live" (Shopee Live style)
// =============================================================================
// Bag icon nổi ở góc trái-dưới khi xem livestream. Badge hiển thị số sp
// user đã thêm vào giỏ TRONG phiên live hiện tại (liveCartItemCount, reset
// khi rời live). Tap → push thẳng CartScreen làm route mới đè lên live
// — user thấy toàn bộ giỏ (kèm Tropia voucher + voucher từng shop), back
// để quay lại live.
//
// (Trước đây mở bottom sheet mini-cart, nhưng UX hơi rườm rà khi user đã
// click bag là muốn xem giỏ đầy đủ + coupon — pop straight to cart đơn
// giản và match hành vi tap badge cart trên các tab khác.)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/cart/providers/cart_provider.dart';
import 'package:tropia/features/cart/screens/cart_screen.dart';
import 'package:tropia/features/live/providers/live_provider.dart';

const _tag = 'LiveMiniCartBag';

class LiveMiniCartBag extends StatelessWidget {
  const LiveMiniCartBag({super.key, required this.streamId});
  final String streamId;

  @override
  Widget build(BuildContext context) {
    return Consumer<LiveProvider>(
      builder: (context, live, _) {
        final count = live.liveCartItemCount;
        return GestureDetector(
          onTap: () => _open(context, count),
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFF7043), Color(0xFFFF5722)],
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Center(
                  child: Icon(Icons.shopping_bag_outlined,
                      color: Colors.white, size: 28),
                ),
                if (count > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: const Color(0xFFFF5722), width: 1.5),
                      ),
                      child: Center(
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Color(0xFFFF5722),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _open(BuildContext context, int count) {
    AppLogger.logUserEvent(
      action: 'live_mini_cart_opened',
      context: _tag,
      metadata: {'streamId': streamId, 'count': count},
    );
    // Force CartProvider refresh trước khi push để cart_items thêm từ live
    // hiển thị ngay (user có thể chưa từng mở tab Giỏ hàng nên provider
    // chưa load lần nào). Fire-and-forget, CartScreen tự `load()` lần nữa
    // trong initState — call dư ở đây chỉ rút ngắn thời gian thấy spinner.
    final cart = context.read<CartProvider>();
    // ignore: unawaited_futures
    cart.load();
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const CartScreen()),
    );
  }
}

// Visual element-only widget — màn hình mini-cart đã được gỡ bỏ. Giỏ
// đầy đủ (CartScreen) đã có đủ section: list theo shop, voucher row của
// từng shop, Tropia voucher row, checkout bar. Không cần view trùng lặp.
