// =============================================================================
// live_product_popup.dart
// =============================================================================
// Widget popup chi tiết sản phẩm khi người dùng tap vào sản phẩm trong live.
//
// Hỗ trợ cả sản phẩm đơn giản và sản phẩm có biến thể (màu sắc, size…).
//
// Giao diện (bottom sheet):
//   ┌──────────────────────────────────┐
//   │  [Ảnh lớn – thay đổi theo SKU]  │
//   │                                  │
//   │  Tên sản phẩm đầy đủ             │
//   │  ⭐⭐⭐⭐⭐ (4.8) | 2.341 đã bán │
//   │                                  │
//   │  [Variant] Màu sắc               │
//   │  ○ Trắng  ○ Đen  ○ Xanh Navy    │
//   │                                  │
//   │  [Variant] Size                  │
//   │  [35] [36] [37] [38] [40] [42✕] │
//   │                                  │
//   │  450.000đ  ~~700.000đ  [-35%]    │
//   │  Còn lại: 3 sản phẩm             │
//   │                                  │
//   │  Đặt hàng tự động: [toggle]      │
//   │                                  │
//   │  [Thêm giỏ hàng]  [Mua ngay]     │
//   └──────────────────────────────────┘
// =============================================================================

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/models/live_stream_model.dart';

class LiveProductPopup extends StatefulWidget {
  final LiveProduct product;
  final void Function(String? skuId) onBuyNow;
  final void Function(String? skuId) onAddToCart;
  final VoidCallback onClose;

  const LiveProductPopup({
    super.key,
    required this.product,
    required this.onBuyNow,
    required this.onAddToCart,
    required this.onClose,
  });

  @override
  State<LiveProductPopup> createState() => _LiveProductPopupState();
}

class _LiveProductPopupState extends State<LiveProductPopup> {
  // Map axisName → selectedOption label
  final Map<String, String> _selected = {};

  LiveProduct get product => widget.product;

  ProductSku? get _currentSku => product.hasVariants
      ? product.findSku(_selected)
      : null;

  bool get _allAxesSelected =>
      !product.hasVariants ||
      _selected.length == product.variantAxes.length;

  // Effective values — use SKU when fully selected, fall back to product
  double get _displaySalePrice =>
      _currentSku?.salePrice ?? product.salePrice;

  double get _displayOriginalPrice =>
      _currentSku?.originalPrice ?? product.originalPrice;

  int get _displayStock {
    if (!product.hasVariants) return product.stockLeft;
    if (_currentSku != null) return _currentSku!.stockLeft;
    return product.totalStock;
  }

  String? get _displayImageUrl =>
      _currentSku?.imageUrl ?? product.imageUrl;

  // Discount for the selected SKU (or product-level)
  int get _displayDiscount {
    final orig = _displayOriginalPrice;
    final sale = _displaySalePrice;
    if (orig <= 0 || sale >= orig) return 0;
    return ((orig - sale) / orig * 100).round();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusXl),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Handle bar ───────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(top: AppSizes.sm),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(AppSizes.radiusFull),
            ),
          ),

          // ── Scrollable content ───────────────────────────────────────
          Flexible(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildProductImage(context),
                  Padding(
                    padding: const EdgeInsets.all(AppSizes.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildProductName(),
                        const SizedBox(height: AppSizes.sm),
                        _buildRatingsRow(),

                        // ── Variant selectors (only if product has variants) ──
                        if (product.hasVariants) ...[
                          const SizedBox(height: AppSizes.md),
                          ...product.variantAxes.map(
                            (axis) => _buildVariantAxis(axis),
                          ),
                        ],

                        const SizedBox(height: AppSizes.md),
                        _buildPricing(),
                        const SizedBox(height: AppSizes.sm),
                        _buildStockInfo(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Action buttons (sticky bottom) ───────────────────────────
          _buildActionButtons(context),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Product image — updates when a SKU with its own image is selected
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProductImage(BuildContext context) {
    return Stack(
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: SizedBox(
            key: ValueKey(_displayImageUrl),
            height: 240,
            width: double.infinity,
            child: _displayImageUrl != null
                ? CachedNetworkImage(
                    imageUrl: _displayImageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    errorWidget: (context, url, error) => _imageFallback(),
                  )
                : _imageFallback(),
          ),
        ),

        // Discount badge
        if (_displayDiscount > 0)
          Positioned(
            top: AppSizes.md,
            left: AppSizes.md,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.sm,
                vertical: AppSizes.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.liveRed,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
              child: Text(
                '-$_displayDiscount%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppSizes.fontSm,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

        // Close button
        Positioned(
          top: AppSizes.sm,
          right: AppSizes.sm,
          child: GestureDetector(
            onTap: widget.onClose,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.overlayDark,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imageFallback() => Container(
        color: AppColors.surfaceVariant,
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: AppSizes.iconXl,
            color: AppColors.textHint,
          ),
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Product name
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProductName() {
    return Text(
      product.name,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: AppSizes.fontXl,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Ratings row
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRatingsRow() {
    return Row(
      children: [
        Row(
          children: List.generate(5, (i) {
            return Icon(
              i < 4 ? Icons.star : Icons.star_half,
              color: AppColors.gold,
              size: 16,
            );
          }),
        ),
        const SizedBox(width: AppSizes.xs),
        const Text(
          '4.8',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppSizes.fontSm,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: AppSizes.sm),
        const Text('•', style: TextStyle(color: AppColors.textHint)),
        const SizedBox(width: AppSizes.sm),
        Text(
          '${_formatNumber(product.soldCount)} ${AppStrings.productSold}',
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppSizes.fontSm,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Variant axis selector
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildVariantAxis(ProductVariantAxis axis) {
    final selectedLabel = _selected[axis.name];

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Axis label + selected value
          Row(
            children: [
              Text(
                axis.name,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppSizes.fontMd,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (selectedLabel != null) ...[
                const SizedBox(width: AppSizes.xs),
                Text(
                  ': $selectedLabel',
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: AppSizes.fontMd,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSizes.sm),

          // Option chips
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: axis.options.map((opt) {
              final isSelected = selectedLabel == opt.label;
              final isUnavailable = !opt.isAvailable;

              if (axis.type == VariantAxisType.color) {
                return _buildColorSwatch(
                  option: opt,
                  isSelected: isSelected,
                  isUnavailable: isUnavailable,
                  onTap: isUnavailable
                      ? null
                      : () => _selectOption(axis.name, opt.label),
                );
              }

              return _buildTextChip(
                label: opt.label,
                isSelected: isSelected,
                isUnavailable: isUnavailable,
                onTap: isUnavailable
                    ? null
                    : () => _selectOption(axis.name, opt.label),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _selectOption(String axisName, String label) {
    setState(() {
      if (_selected[axisName] == label) {
        // Tap again to deselect
        _selected.remove(axisName);
      } else {
        _selected[axisName] = label;
      }
    });
  }

  // ── Color swatch ─────────────────────────────────────────────────────────

  Widget _buildColorSwatch({
    required ProductVariantOption option,
    required bool isSelected,
    required bool isUnavailable,
    required VoidCallback? onTap,
  }) {
    Color swatchColor = Colors.grey.shade300;
    if (option.colorHex != null) {
      try {
        final hex = option.colorHex!.replaceAll('#', '');
        swatchColor = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {}
    }

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isUnavailable ? 0.35 : 1.0,
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: swatchColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? AppColors.secondary
                      : AppColors.divider,
                  width: isSelected ? 2.5 : 1.0,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: AppColors.secondary.withValues(alpha: 0.35),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: isUnavailable
                  ? Center(
                      child: Container(
                        width: 30,
                        height: 2,
                        color: Colors.red.withValues(alpha: 0.7),
                        transform: Matrix4.rotationZ(0.785),
                        transformAlignment: Alignment.center,
                      ),
                    )
                  : isSelected
                      ? const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 18,
                          shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                        )
                      : null,
            ),
            const SizedBox(height: 4),
            Text(
              option.label,
              style: TextStyle(
                fontSize: AppSizes.fontXs,
                color: isSelected
                    ? AppColors.secondary
                    : AppColors.textSecondary,
                fontWeight:
                    isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Text chip (size, text variants) ──────────────────────────────────────

  Widget _buildTextChip({
    required String label,
    required bool isSelected,
    required bool isUnavailable,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.secondary
              : isUnavailable
                  ? AppColors.surfaceVariant
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
            color: isSelected
                ? AppColors.secondary
                : isUnavailable
                    ? AppColors.divider
                    : AppColors.divider,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppSizes.fontSm,
                color: isSelected
                    ? Colors.white
                    : isUnavailable
                        ? AppColors.textHint
                        : AppColors.textPrimary,
                fontWeight:
                    isSelected ? FontWeight.w700 : FontWeight.normal,
                decoration:
                    isUnavailable ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Pricing — live-updates when SKU changes
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPricing() {
    final showRange = product.hasVariants &&
        product.hasPriceRange &&
        !_allAxesSelected;

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.secondaryLight.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(
          color: AppColors.secondary.withValues(alpha: 0.2),
        ),
      ),
      child: showRange
          ? Row(
              children: [
                Text(
                  '${_formatPrice(product.minSkuPrice)} – ${_formatPrice(product.maxSkuPrice)}',
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: AppSizes.fontXl,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                const Text(
                  'Chọn phân loại',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppSizes.fontXs,
                  ),
                ),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _formatPrice(_displaySalePrice),
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: AppSizes.fontXxl,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(width: AppSizes.sm),
                Text(
                  _formatPrice(_displayOriginalPrice),
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: AppSizes.fontMd,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
                const Spacer(),
                if (_displayDiscount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.sm,
                      vertical: AppSizes.xs / 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.liveRed,
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    ),
                    child: Text(
                      'Tiết kiệm ${_formatPrice(_displayOriginalPrice - _displaySalePrice)}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: AppSizes.fontXs,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Stock info — per-SKU when selected
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStockInfo() {
    final stock = _displayStock;
    final isLow = stock <= 20;

    String label;
    if (product.hasVariants && !_allAxesSelected) {
      label = 'Tổng kho: ${_formatNumber(product.totalStock)} ${AppStrings.productItems}';
    } else {
      label = '${_formatNumber(stock)} ${AppStrings.productItems}';
    }

    return Row(
      children: [
        Icon(
          isLow ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
          size: AppSizes.iconSm,
          color: isLow ? AppColors.warning : AppColors.textSecondary,
        ),
        const SizedBox(width: AppSizes.xs),
        const Text(
          '${AppStrings.productStock}: ',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppSizes.fontSm,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: isLow ? AppColors.warning : AppColors.textPrimary,
            fontSize: AppSizes.fontSm,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (isLow && _allAxesSelected) ...[
          const SizedBox(width: AppSizes.xs),
          const Text(
            '– Sắp hết!',
            style: TextStyle(
              color: AppColors.warning,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Action buttons — disabled until all axes selected for variant products
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActionButtons(BuildContext context) {
    final canBuy = _allAxesSelected && _displayStock > 0;
    final tooltipMsg = !_allAxesSelected
        ? 'Vui lòng chọn đầy đủ phân loại'
        : _displayStock == 0
            ? 'Hết hàng'
            : null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.md,
        AppSizes.md,
        AppSizes.md + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hint when no variant selected
          if (product.hasVariants && !_allAxesSelected)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSizes.sm),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 14,
                    color: AppColors.textHint,
                  ),
                  const SizedBox(width: AppSizes.xs),
                  Text(
                    tooltipMsg ?? '',
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: AppSizes.fontXs,
                    ),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              // Thêm giỏ hàng
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: canBuy
                      ? () => widget.onAddToCart(_currentSku?.skuId)
                      : null,
                  icon: const Icon(Icons.shopping_cart_outlined, size: 18),
                  label: const Text(AppStrings.productAddToCart),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              // Mua ngay
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: canBuy
                      ? () => widget.onBuyNow(_currentSku?.skuId)
                      : null,
                  icon: const Icon(Icons.bolt, size: 18),
                  label: Text(
                    _displayStock > 0 ? AppStrings.productBuyNow : 'Hết hàng',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canBuy
                        ? AppColors.secondary
                        : AppColors.surfaceVariant,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _formatPrice(double price) {
    if (price >= 1000000) {
      final m = price / 1000000;
      return '${m % 1 == 0 ? m.toInt().toString() : m.toStringAsFixed(1)} tr đ';
    } else if (price >= 1000) {
      final thousands = (price / 1000).floor();
      final remainder = ((price % 1000) / 100).floor();
      return '$thousands.${remainder}00 đ';
    }
    return '${price.toInt()}đ';
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }
}
