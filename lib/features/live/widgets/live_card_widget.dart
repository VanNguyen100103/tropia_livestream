import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';

// Shopee-style full-width live card:
//   Row 1: avatar (ring đỏ nếu live) + tên + verified + viewer count + nút Theo dõi
//   Row 2: ranking badge (nếu có)
//   Thumbnail 16:9 full-width với LIVE badge + featured product overlay

class LiveCardWidget extends StatelessWidget {
  final LiveStream stream;
  final VoidCallback onTap;
  final VoidCallback? onFollowTap;

  const LiveCardWidget({super.key, required this.stream, required this.onTap, this.onFollowTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildThumbnail(),
            const SizedBox(height: AppSizes.xs),
          ],
        ),
      ),
    );
  }

  // ── Header row: avatar + info + follow button ─────────────────────────────

  Widget _buildHeader() {
    final isLive = stream.status == StreamStatus.live;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.xs),
      child: Row(
        children: [
          // Avatar với ring đỏ khi live
          _buildAvatar(isLive),
          const SizedBox(width: AppSizes.sm),

          // Tên + viewer count
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        stream.sellerName,
                        style: const TextStyle(
                          fontSize: AppSizes.fontMd,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (stream.isVerified) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.verified, size: 14, color: AppColors.primary),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.remove_red_eye_outlined, size: 12, color: AppColors.textHint),
                    const SizedBox(width: 3),
                    Text(
                      stream.viewerCountFormatted,
                      style: const TextStyle(fontSize: AppSizes.fontXs, color: AppColors.textHint),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                      ),
                      child: Text(
                        stream.category,
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 9,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: AppSizes.sm),

          // Nút Theo dõi
          GestureDetector(
            onTap: onFollowTap,
            child: _buildFollowButton(isLive),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isLive) {
    const avatarSize = 44.0;
    const ringSize = 50.0;
    const borderSize = 2.0;

    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ring đỏ gradient khi live
          if (isLive)
            Container(
              width: ringSize,
              height: ringSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.liveRed, Color(0xFFFF6B35)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          // Viền trắng cách ly
          Container(
            width: avatarSize + borderSize * 2,
            height: avatarSize + borderSize * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLive ? Colors.white : Colors.transparent,
            ),
          ),
          // Avatar
          ClipOval(
            child: CachedNetworkImage(
              imageUrl: stream.sellerAvatarUrl,
              width: avatarSize,
              height: avatarSize,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: avatarSize,
                height: avatarSize,
                color: AppColors.primaryContainer,
                child: const Icon(Icons.storefront, color: AppColors.primary, size: 22),
              ),
            ),
          ),
          // Badge LIVE dưới avatar
          if (isLive)
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.liveRed,
                  borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFollowButton(bool isLive) {
    final following = stream.isFollowing;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 6),
      decoration: BoxDecoration(
        color: following
            ? AppColors.surfaceVariant
            : (isLive ? AppColors.liveRed : AppColors.primary),
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        border: following ? Border.all(color: AppColors.divider) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            following ? Icons.check : Icons.add,
            color: following ? AppColors.textSecondary : Colors.white,
            size: 14,
          ),
          const SizedBox(width: 2),
          Text(
            following ? 'Đang theo' : 'Theo dõi',
            style: TextStyle(
              color: following ? AppColors.textSecondary : Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── Thumbnail 16:9 full-width ─────────────────────────────────────────────

  Widget _buildThumbnail() {
    final featured = stream.products.isNotEmpty ? stream.products.first : null;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Ảnh/video thumbnail
          CachedNetworkImage(
            imageUrl: stream.thumbnailUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => _buildShimmer(),
            errorWidget: (_, __, ___) => _buildGradientFallback(),
          ),

          // Gradient overlay dưới
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 60,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
          ),

          // LIVE / VIDEO badge góc trên trái
          Positioned(
            top: AppSizes.xs,
            left: AppSizes.sm,
            child: _buildStatusBadge(),
          ),

          // Ranking badge nếu có — góc trên phải
          if (stream.featuredBadge != null)
            Positioned(
              top: AppSizes.xs,
              right: AppSizes.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: Text(
                  stream.featuredBadge!,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // Title ở dưới thumbnail
          Positioned(
            bottom: AppSizes.xs,
            left: AppSizes.sm,
            right: AppSizes.sm,
            child: Text(
              stream.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppSizes.fontSm,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),

          // Featured product — góc dưới trái (giống Shopee)
          if (featured != null)
            Positioned(
              left: AppSizes.sm,
              bottom: 28,
              child: _FeaturedProductBadge(product: featured),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final isLive = stream.status == StreamStatus.live;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 3),
      decoration: BoxDecoration(
        color: isLive ? AppColors.liveRed : AppColors.textSecondary,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 3),
          ],
          Text(
            isLive ? 'LIVE' : 'VIDEO',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: const ColoredBox(color: Colors.white),
    );
  }

  Widget _buildGradientFallback() {
    final colors = stream.gradientColors;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_parseColor(colors.first), _parseColor(colors.last)],
        ),
      ),
      child: Center(
        child: Icon(Icons.live_tv, color: Colors.white.withValues(alpha: 0.7), size: AppSizes.iconXl),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Featured product badge — góc dưới trái thumbnail
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedProductBadge extends StatelessWidget {
  final LiveProduct product;
  const _FeaturedProductBadge({required this.product});

  @override
  Widget build(BuildContext context) {
    final hasDiscount = product.discountPercent > 0;

    return Container(
      width: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSizes.radiusSm)),
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl,
                  width: 110, height: 58, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 110, height: 58,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.image_outlined, color: AppColors.textHint, size: 20),
                  ),
                ),
              ),
              if (hasDiscount)
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: const BoxDecoration(
                      color: AppColors.liveRed,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(AppSizes.radiusSm),
                        bottomLeft: Radius.circular(AppSizes.radiusSm),
                      ),
                    ),
                    child: Text('-${product.discountPercent}%',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
            child: Text(
              _formatPrice(product.salePrice.toInt()),
              style: const TextStyle(color: AppColors.secondary, fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: const BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppSizes.radiusSm)),
            ),
            child: const Text('Mua ngay',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()}đ';
  }
}
