// =============================================================================
// video_add_to_cart_sheet.dart
// =============================================================================
// Bottom-sheet "Thêm vào giỏ" mở từ thẻ sản phẩm trong feed Video.
//   - Tải chi tiết sản phẩm (kèm biến thể) theo slug
//   - Cho chọn biến thể + số lượng
//   - Gọi THẲNG API giỏ Go: CartRepository.addItem(variantId, quantity)
//
// CHỦ Ý: chỉ đụng giỏ của live_app (/api/cart/items). KHÔNG liên quan tới giỏ
// của app chính (lib/features/user/cart). Trả về true qua Navigator.pop khi
// thêm thành công để màn gọi hiển thị snackbar.
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'package:tropia_mobile_app_android/live_app/core/config/app_config.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/cart/data/cart_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/coupon/data/coupon_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/product/data/product_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/product/models/product_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';

/// Mở sheet chọn biến thể + thêm vào giỏ. Trả về true nếu đã thêm thành công.
/// [shopId] + [shopHasVoucher]: nếu shop có voucher, sheet sẽ tải và hiển thị
/// voucher của shop để khách áp ở bước thanh toán ("Mua với Voucher").
Future<bool> showVideoAddToCartSheet(
  BuildContext context, {
  required VideoProduct product,
  String? shopId,
  bool shopHasVoucher = false,
}) async {
  final added = await showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(AppSizes.radiusLg),
      ),
    ),
    builder: (_) => _VideoAddToCartSheet(
      product: product,
      shopId: shopId,
      shopHasVoucher: shopHasVoucher,
    ),
  );
  return added ?? false;
}

class _VideoAddToCartSheet extends StatefulWidget {
  final VideoProduct product;
  final String? shopId;
  final bool shopHasVoucher;
  const _VideoAddToCartSheet({
    required this.product,
    this.shopId,
    this.shopHasVoucher = false,
  });

  @override
  State<_VideoAddToCartSheet> createState() => _VideoAddToCartSheetState();
}

class _VideoAddToCartSheetState extends State<_VideoAddToCartSheet> {
  ProductModel? _product;
  bool _loading = true;
  String? _error;

  int _variantIndex = 0;
  int _quantity = 1;
  bool _submitting = false;

  // Voucher của shop (chỉ tải khi shop có voucher). Hiển thị để khách áp ở
  // bước thanh toán — không tự áp tại đây (checkout đã hỗ trợ voucher shop).
  List<CouponModel> _vouchers = [];

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.shopHasVoucher && (widget.shopId?.isNotEmpty ?? false)) {
      _loadVouchers();
    }
  }

  Future<void> _loadVouchers() async {
    try {
      final list = await CouponRepository.instance.getShopCoupons(
        widget.shopId!,
      );
      if (mounted) setState(() => _vouchers = list);
    } catch (_) {
      // Voucher chỉ là phần phụ — lỗi tải thì bỏ qua, không chặn add-to-cart.
    }
  }

  Future<void> _load() async {
    try {
      final p = await ProductRepository.instance.getBySlug(widget.product.slug);
      if (!mounted) return;
      setState(() {
        _product = p;
        _loading = false;
        // Chọn sẵn biến thể còn hàng đầu tiên (nếu có).
        final firstInStock = p.variants.indexWhere((v) => v.stock > 0);
        _variantIndex = firstInStock >= 0 ? firstInStock : 0;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = AuthService.errorMessage(e);
        _loading = false;
      });
    }
  }

  ProductVariant? get _selected {
    final p = _product;
    if (p == null || p.variants.isEmpty) return null;
    if (_variantIndex < 0 || _variantIndex >= p.variants.length) return null;
    return p.variants[_variantIndex];
  }

  int get _selectedStock => _selected?.stock ?? 0;

  void _setQuantity(int delta) {
    final max = _selectedStock;
    setState(() {
      _quantity = (_quantity + delta).clamp(1, max <= 0 ? 1 : max);
    });
  }

  Future<void> _addToCart() async {
    final variant = _selected;
    if (variant == null || _submitting) return;
    setState(() => _submitting = true);
    try {
      await CartRepository.instance.addItem(
        variantId: variant.id,
        quantity: _quantity,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(AuthService.errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: AnimatedSize(
        duration: const Duration(milliseconds: 150),
        child: _loading
            ? const SizedBox(
                height: 220,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
            : _error != null
            ? _buildError()
            : _buildLoaded(),
      ),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AppColors.textHint, size: 40),
          const SizedBox(height: AppSizes.sm),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSizes.md),
          TextButton(
            onPressed: () {
              setState(() {
                _loading = true;
                _error = null;
              });
              _load();
            },
            child: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }

  Widget _buildLoaded() {
    final p = _product!;
    final variant = _selected;
    final price = variant?.price ?? widget.product.displayPrice;
    final img = (variant != null && variant.images.isNotEmpty)
        ? _resolveImg(variant.images.first)
        : widget.product.image;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header: ảnh + giá + nút đóng ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.md,
            AppSizes.md,
            AppSizes.sm,
            AppSizes.sm,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: img != null
                      ? CachedNetworkImage(
                          imageUrl: img,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _imgFallback(),
                        )
                      : _imgFallback(),
                ),
              ),
              const SizedBox(width: AppSizes.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppSizes.fontSm,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _fmtVnd(price),
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppSizes.fontLg,
                      ),
                    ),
                    if (variant != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        'Kho: ${variant.stock}',
                        style: const TextStyle(
                          fontSize: AppSizes.fontXs,
                          color: AppColors.textHint,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context, false),
                icon: const Icon(Icons.close),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // ── Chọn biến thể ────────────────────────────────────────────────────
        if (p.variants.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.md,
              AppSizes.sm,
              AppSizes.md,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phân loại',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppSizes.fontMd,
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                Wrap(
                  spacing: AppSizes.sm,
                  runSpacing: AppSizes.sm,
                  children: [
                    for (var i = 0; i < p.variants.length; i++)
                      _VariantChip(
                        label: p.variants[i].name,
                        selected: i == _variantIndex,
                        disabled: p.variants[i].stock <= 0,
                        onTap: () => setState(() {
                          _variantIndex = i;
                          _quantity = 1;
                        }),
                      ),
                  ],
                ),
              ],
            ),
          ),

        // ── Số lượng ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSizes.md,
            AppSizes.md,
            AppSizes.md,
            AppSizes.sm,
          ),
          child: Row(
            children: [
              const Text(
                'Số lượng',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: AppSizes.fontMd,
                ),
              ),
              const Spacer(),
              _QtyButton(
                icon: Icons.remove,
                onTap: _quantity > 1 ? () => _setQuantity(-1) : null,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                child: Text(
                  '$_quantity',
                  style: const TextStyle(
                    fontSize: AppSizes.fontLg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _QtyButton(
                icon: Icons.add,
                onTap: _quantity < _selectedStock
                    ? () => _setQuantity(1)
                    : null,
              ),
            ],
          ),
        ),

        // ── Voucher của shop ─────────────────────────────────────────────────
        if (_vouchers.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.md,
              AppSizes.sm,
              AppSizes.md,
              0,
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.local_offer,
                  size: 16,
                  color: AppColors.secondary,
                ),
                const SizedBox(width: 4),
                const Text(
                  'Voucher của Shop',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppSizes.fontMd,
                  ),
                ),
                const Spacer(),
                Text(
                  'Áp ở bước thanh toán',
                  style: TextStyle(
                    fontSize: AppSizes.fontXs,
                    color: AppColors.textHint,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.md,
                vertical: AppSizes.xs,
              ),
              itemCount: _vouchers.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSizes.sm),
              itemBuilder: (_, i) => _VoucherChip(coupon: _vouchers[i]),
            ),
          ),
        ],

        // ── Nút thêm ─────────────────────────────────────────────────────────
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSizes.md,
            AppSizes.sm,
            AppSizes.md,
            AppSizes.md + MediaQuery.of(context).padding.bottom,
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_selectedStock <= 0 || _submitting)
                  ? null
                  : _addToCart,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.textHint,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
              ),
              child: _submitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.4,
                      ),
                    )
                  : Text(
                      _selectedStock <= 0
                          ? 'Hết hàng'
                          : AppStrings.productAddToCart,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: AppSizes.fontMd,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _imgFallback() => Container(
    color: AppColors.surfaceVariant,
    child: const Icon(
      Icons.image_outlined,
      color: AppColors.textHint,
      size: 26,
    ),
  );
}

class _VariantChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onTap;

  const _VariantChip({
    required this.label,
    required this.selected,
    required this.disabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? AppColors.textHint
        : selected
        ? AppColors.secondary
        : AppColors.textSecondary;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.secondary.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          border: Border.all(color: color, width: selected ? 1.4 : 1),
        ),
        child: Text(
          disabled ? '$label (hết)' : label,
          style: TextStyle(
            color: color,
            fontSize: AppSizes.fontSm,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            decoration: disabled ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _QtyButton({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          border: Border.all(
            color: enabled ? AppColors.divider : AppColors.surfaceVariant,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? AppColors.textPrimary : AppColors.textHint,
        ),
      ),
    );
  }
}

/// Chip 1 voucher của shop (chỉ hiển thị; khách áp ở bước thanh toán).
class _VoucherChip extends StatelessWidget {
  final CouponModel coupon;
  const _VoucherChip({required this.coupon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.4)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            coupon.discountLabel,
            style: const TextStyle(
              color: AppColors.secondary,
              fontWeight: FontWeight.w700,
              fontSize: AppSizes.fontSm,
            ),
          ),
          Text(
            coupon.minOrderValue > 0
                ? 'Đơn từ ${_fmtVnd(coupon.minOrderValue)} • ${coupon.code}'
                : coupon.code,
            style: const TextStyle(
              fontSize: AppSizes.fontXs,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Định dạng giá VND có dấu chấm phân nhóm: 75000 → "75.000đ".
String _fmtVnd(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  buf.write('đ');
  return buf.toString();
}

/// Ghép host cho URL ảnh biến thể (chỉ trả http/https hợp lệ).
String? _resolveImg(String raw) {
  if (raw.isEmpty) return null;
  final u = AppConfig.resolveBackendUrl(raw);
  return (u.startsWith('http://') || u.startsWith('https://')) ? u : null;
}
