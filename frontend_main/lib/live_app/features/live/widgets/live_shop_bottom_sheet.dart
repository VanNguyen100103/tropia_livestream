import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/models/live_stream_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/providers/live_provider.dart';
import 'package:tropia_mobile_app_android/live_app/features/shop/screens/shop_detail_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/initials_avatar.dart';

const _tag = 'LiveShopBottomSheet';

/// Bottom sheet "Khám phá shop" – giống Shopee Live.
/// Hiển thị thông tin shop (avatar, tên, rating, follower) + danh sách sản phẩm đang bán.
void showLiveShopBottomSheet({
  required BuildContext context,
  required LiveStream stream,
  required LiveProvider provider,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _LiveShopBottomSheet(stream: stream, provider: provider),
  );
}

class _LiveShopBottomSheet extends StatelessWidget {
  final LiveStream stream;
  final LiveProvider provider;

  const _LiveShopBottomSheet({required this.stream, required this.provider});

  void _goToShop(BuildContext context) {
    final shopId = stream.shopId ?? stream.sellerId;
    Navigator.of(context).pop(); // đóng bottom sheet trước
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShopDetailScreen(shopId: shopId),
      ),
    );
    AppLogger.logUserEvent(
      action: 'shop_profile_tapped_from_sheet',
      context: _tag,
      metadata: {'shopId': shopId},
    );
  }

  @override
  Widget build(BuildContext context) {
    // Lắng nghe LiveProvider để cập nhật isFollowing real-time
    final liveStream = context.watch<LiveProvider>().currentStream;
    final s = liveStream?.id == stream.id ? liveStream! : stream;
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.82,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.radiusXl)),
      ),
      child: Column(
        children: [
          // ── Handle ────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // ── Shop header ───────────────────────────────────────────────────
          _buildShopHeader(context, s),

          const Divider(height: 1, color: AppColors.divider),

          // ── Voucher strip (nếu có) ────────────────────────────────────────
          if (s.vouchers.isNotEmpty) ...[
            _buildVoucherStrip(context),
            const Divider(height: 1, color: AppColors.divider),
          ],

          // ── Tab label ─────────────────────────────────────────────────────
          Container(
            color: AppColors.background,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: AppSizes.xs),
                const Text(
                  'Sản phẩm đang bán',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppSizes.fontMd,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${s.products.length} sản phẩm',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppSizes.fontSm,
                  ),
                ),
              ],
            ),
          ),

          // ── Product list ──────────────────────────────────────────────────
          Expanded(
            child: s.products.isEmpty
                ? const Center(
                    child: Text(
                      'Chưa có sản phẩm nào',
                      style: TextStyle(color: AppColors.textHint),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(
                        bottom: AppSizes.xxl + AppSizes.md),
                    itemCount: s.products.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.divider),
                    itemBuilder: (context, index) {
                      final product = s.products[index];
                      final isPinned = index == 0;
                      return _ShopProductRow(
                        product: product,
                        isPinned: isPinned,
                        onBuyNow: () {
                          Navigator.of(context).pop();
                          provider.showProductPopup(s.id, product.id);
                          AppLogger.logUserEvent(
                            action: 'shop_sheet_buy_now',
                            context: _tag,
                            metadata: {
                              'streamId': s.id,
                              'productId': product.id,
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildShopHeader(BuildContext context, LiveStream s) {
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm),
      child: Row(
        children: [
          // Avatar — tap → ShopDetailScreen
          GestureDetector(
            onTap: () => _goToShop(context),
            child: InitialsAvatar(
              imageUrl: s.sellerAvatarUrl,
              name: s.sellerName,
              radius: AppSizes.avatarLg / 2,
            ),
          ),
          const SizedBox(width: AppSizes.md),

          // Name + stats — tap → ShopDetailScreen
          Expanded(
            child: GestureDetector(
              onTap: () => _goToShop(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          s.sellerName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: AppSizes.fontLg,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (s.isVerified) ...[
                        const SizedBox(width: AppSizes.xs),
                        const Icon(Icons.verified,
                            size: 16, color: AppColors.primary),
                      ],
                      const SizedBox(width: AppSizes.xs),
                      const Icon(Icons.chevron_right,
                          size: 16, color: AppColors.textSecondary),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          size: 14, color: AppColors.gold),
                      const SizedBox(width: 2),
                      Text(
                        '${s.viewerCountFormatted} người xem',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: AppSizes.fontSm,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Follow button — gọi API thực
          GestureDetector(
            onTap: () async {
              final wasFollowing = s.isFollowing;
              await provider.toggleFollow(s.id);
              AppLogger.logUserEvent(
                action: wasFollowing
                    ? 'unfollow_from_shop_sheet'
                    : 'follow_from_shop_sheet',
                context: _tag,
                metadata: {'streamId': s.id},
              );
              if (!wasFollowing && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(AppStrings.notifFollowSuccess),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.md, vertical: AppSizes.sm),
              decoration: BoxDecoration(
                color: s.isFollowing
                    ? AppColors.surfaceVariant
                    : AppColors.liveRed,
                borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                border: Border.all(
                  color: s.isFollowing
                      ? AppColors.divider
                      : AppColors.liveRed,
                ),
              ),
              child: Text(
                s.isFollowing
                    ? AppStrings.liveFollowing
                    : '+ ${AppStrings.liveFollow}',
                style: TextStyle(
                  color: s.isFollowing ? AppColors.textSecondary : Colors.white,
                  fontSize: AppSizes.fontSm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoucherStrip(BuildContext context) {
    return Container(
      color: const Color(0xFFFFF3F0),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.xs, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.liveRed,
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: const Text(
              'LIVE',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Text(
              stream.vouchers.first.discountDisplay,
              style: const TextStyle(
                color: AppColors.liveRed,
                fontSize: AppSizes.fontSm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          GestureDetector(
            onTap: () {
              AppLogger.logUserEvent(
                action: 'use_voucher_from_shop_sheet',
                context: _tag,
                metadata: {'voucherId': stream.vouchers.first.id},
              );
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text(AppStrings.notifVoucherSaved)),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.sm, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.liveRed,
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              ),
              child: const Text(
                'Dùng',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.fontXs,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}

// ─────────────────────────────────────────────────────────────────────────────
// _ShopProductRow – một dòng sản phẩm trong danh sách
// ─────────────────────────────────────────────────────────────────────────────

class _ShopProductRow extends StatelessWidget {
  final LiveProduct product;
  final bool isPinned;
  final VoidCallback onBuyNow;

  const _ShopProductRow({
    required this.product,
    required this.isPinned,
    required this.onBuyNow,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: isPinned
          ? AppColors.primaryContainer.withValues(alpha: 0.4)
          : AppColors.surface,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm + 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Product image ──────────────────────────────────────────────
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl,
                  width: 80,
                  height: 80,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    width: 80,
                    height: 80,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.broken_image_outlined,
                        color: AppColors.textHint),
                  ),
                ),
              ),
              // Discount badge
              if (product.discountPercent > 0)
                Positioned(
                  top: 4,
                  left: 4,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.liveRed,
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    ),
                    child: Text(
                      '-${product.discountPercent}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          const SizedBox(width: AppSizes.sm),

          // ── Product info ───────────────────────────────────────────────
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // "Đang hiển thị" badge + name
                if (isPinned)
                  Container(
                    margin: const EdgeInsets.only(bottom: AppSizes.xs),
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.xs + 2, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.circular(AppSizes.radiusSm),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.equalizer_rounded,
                            size: 10, color: Colors.white),
                        SizedBox(width: 2),
                        Text(
                          'Đang hiển thị',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),

                Text(
                  product.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppSizes.fontMd,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: AppSizes.xs),

                // Category tag + Miễn phí vận chuyển (Live exclusive)
                Wrap(
                  spacing: AppSizes.xs,
                  runSpacing: 2,
                  children: [
                    if (isPinned)
                      _tag('Live', AppColors.liveRed),
                    _tag('Miễn Phí Vận Chuyển', AppColors.primary),
                  ],
                ),

                const SizedBox(height: AppSizes.xs),

                // Sold count
                if (product.soldCount > 0)
                  Text(
                    'Đã bán ${_formatCount(product.soldCount)}',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppSizes.fontXs,
                    ),
                  ),

                const SizedBox(height: AppSizes.xs),

                // Price row + Buy now
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatPrice(product.salePrice),
                            style: const TextStyle(
                              color: AppColors.secondary,
                              fontSize: AppSizes.fontLg,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (product.originalPrice > product.salePrice)
                            Text(
                              _formatPrice(product.originalPrice),
                              style: const TextStyle(
                                color: AppColors.textHint,
                                fontSize: AppSizes.fontXs,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Mua ngay button
                    GestureDetector(
                      onTap: onBuyNow,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.sm, vertical: AppSizes.xs),
                        decoration: BoxDecoration(
                          color: AppColors.secondary,
                          borderRadius:
                              BorderRadius.circular(AppSizes.radiusSm),
                        ),
                        child: const Text(
                          'Mua ngay',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: AppSizes.fontSm,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        border: Border.all(color: color.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  String _formatPrice(double price) {
    if (price >= 1000000) {
      final m = price / 1000000;
      return '${m % 1 == 0 ? m.toInt() : m.toStringAsFixed(1)}tr đ';
    } else if (price >= 1000) {
      final k = (price / 1000).round();
      return '$k.000đ';
    }
    return '${price.toInt()}đ';
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M+';
    if (n >= 1000) return '${(n / 1000).round()}k+';
    return n.toString();
  }
}
