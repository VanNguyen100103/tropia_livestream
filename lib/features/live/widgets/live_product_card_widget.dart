// =============================================================================
// live_product_card_widget.dart
// =============================================================================
// Widget thẻ sản phẩm hiển thị ở cạnh trái màn hình khi xem livestream.
//
// Giao diện (dạng dọc, ~130px rộng):
//   ┌───────────────┐
//   │  [-40%]       │  ← badge giảm giá (góc trên trái)
//   │  [Ảnh SP]     │
//   │  Tên SP       │  ← 2 dòng, truncate
//   │  450K  ~~700K │  ← giá sale + giá gốc gạch
//   │  [Mua ngay]   │  ← nút CTA cam
//   │  [🔄 Auto]    │  ← toggle đặt hàng tự động
//   └───────────────┘
//
// SỬ DỤNG:
//   LiveProductCardWidget(
//     product: myProduct,
//     streamId: 'stream_001',
//     onTap: () => provider.showProductPopup(streamId, product.id),
//     onBuyNow: () => provider.buyNow(streamId, product.id),
//     onAutoOrderToggle: (val) => provider.toggleAutoOrder(streamId, product.id),
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';

class LiveProductCardWidget extends StatelessWidget {
  final LiveProduct product;
  final String streamId;

  /// Tap vào card – mở popup chi tiết sản phẩm
  final VoidCallback onTap;

  /// Tap nút "Mua ngay"
  final VoidCallback onBuyNow;

  const LiveProductCardWidget({
    super.key,
    required this.product,
    required this.streamId,
    required this.onTap,
    required this.onBuyNow,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: AppSizes.productCardWidth,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Product image + discount badge ───────────────────────────
            _buildImageSection(),

            // ── Product info ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(AppSizes.xs + 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProductName(),
                  const SizedBox(height: AppSizes.xs),
                  _buildPricing(),
                  const SizedBox(height: AppSizes.xs),
                  _buildBuyNowButton(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Image section
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildImageSection() {
    return Stack(
      children: [
        // Product image
        SizedBox(
          width: double.infinity,
          height: 100,
          child: CachedNetworkImage(
            imageUrl: product.imageUrl,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              color: AppColors.surfaceVariant,
              child: const Center(
                child: Icon(
                  Icons.image_outlined,
                  color: AppColors.textHint,
                ),
              ),
            ),
            errorWidget: (context, url, error) => Container(
              color: AppColors.surfaceVariant,
              child: const Center(
                child: Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textHint,
                ),
              ),
            ),
          ),
        ),

        // Discount badge
        if (product.discountPercent > 0)
          Positioned(
            top: AppSizes.xs,
            left: AppSizes.xs,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.xs,
                vertical: 2,
              ),
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

        // Variant badge
        if (product.hasVariants)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black.withValues(alpha: 0.55),
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: const Text(
                'Nhiều mẫu',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        // Stock warning (ít hàng, only for non-variant products)
        else if (product.stockLeft <= 20)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.red.withValues(alpha: 0.8),
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                'Còn ${product.stockLeft} sp',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Product name
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProductName() {
    return Text(
      product.name,
      style: const TextStyle(
        fontSize: AppSizes.fontXs,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
        height: 1.3,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pricing
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPricing() {
    if (product.hasVariants && product.hasPriceRange) {
      return Text(
        'Từ ${_formatPrice(product.minSkuPrice)}',
        style: const TextStyle(
          color: AppColors.secondary,
          fontSize: AppSizes.fontSm,
          fontWeight: FontWeight.w700,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatPrice(product.salePrice),
          style: const TextStyle(
            color: AppColors.secondary,
            fontSize: AppSizes.fontSm,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(
          _formatPrice(product.originalPrice),
          style: const TextStyle(
            color: AppColors.textHint,
            fontSize: 9,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Buy now button
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBuyNowButton() {
    // Variant products require popup to select options first
    final isVariant = product.hasVariants;
    return SizedBox(
      width: double.infinity,
      height: 26,
      child: ElevatedButton(
        onPressed: isVariant ? onTap : onBuyNow,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.secondary,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          ),
          textStyle: const TextStyle(
            fontSize: AppSizes.fontXs,
            fontWeight: FontWeight.w700,
          ),
        ),
        child: Text(isVariant ? 'Chọn mẫu' : AppStrings.liveBuyNow),
      ),
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Định dạng giá VND: 450000 → "450K" hoặc "1.5tr"
  String _formatPrice(double price) {
    if (price >= 1000000) {
      final m = price / 1000000;
      return '${m % 1 == 0 ? m.toInt() : m.toStringAsFixed(1)}tr';
    } else if (price >= 1000) {
      return '${(price / 1000).toInt()}K';
    }
    return '${price.toInt()}đ';
  }
}
