import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/cart/models/cart_item_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/cart/providers/cart_provider.dart';
import 'package:tropia_mobile_app_android/live_app/features/cart/screens/checkout_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/coupon/data/coupon_repository.dart';

const _tag = 'CartScreen';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CartProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(context),
      body: Consumer<CartProvider>(
        builder: (context, cart, _) {
          if (cart.status == CartStatus.loading && cart.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (cart.isEmpty) return const _EmptyCart();
          return _CartBody(cart: cart);
        },
      ),
      bottomNavigationBar: Consumer<CartProvider>(
        builder: (_, cart, __) {
          if (cart.isEmpty) return const SizedBox.shrink();
          return _CheckoutBar(cart: cart);
        },
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      title: Consumer<CartProvider>(
        builder: (_, cart, __) => Text(
          'Giỏ hàng${cart.totalCount > 0 ? ' (${cart.totalCount})' : ''}',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
      actions: [
        Consumer<CartProvider>(
          builder: (_, cart, __) {
            if (cart.items.isEmpty) return const SizedBox.shrink();
            final hasSelected = cart.items.any((i) => i.isSelected);
            return TextButton(
              onPressed: hasSelected
                  ? () => _confirmRemoveSelected(context, cart)
                  : null,
              child: Text(
                'Xoá',
                style: TextStyle(
                  color: hasSelected
                      ? AppColors.secondary
                      : AppColors.textHint,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.chat_bubble_outline,
              color: AppColors.textPrimary, size: 22),
          onPressed: () {
            AppLogger.logUserEvent(
                action: 'cart_chat_tapped', context: _tag, metadata: {});
          },
        ),
      ],
    );
  }

  Future<void> _confirmRemoveSelected(
      BuildContext context, CartProvider cart) async {
    final count = cart.items.where((i) => i.isSelected).length;
    if (count == 0) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Xoá sản phẩm?'),
        content: Text('Xoá $count sản phẩm đã chọn khỏi giỏ hàng?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Huỷ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá',
                style: TextStyle(color: AppColors.secondary)),
          ),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      await context.read<CartProvider>().removeSelected();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BODY
// ─────────────────────────────────────────────────────────────────────────────

class _CartBody extends StatelessWidget {
  const _CartBody({required this.cart});
  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    final shops = cart.itemsByShop;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 16),
      children: [
        _GlobalVoucherRow(cart: cart),
        const SizedBox(height: 8),
        for (final entry in shops.entries)
          _ShopGroup(shopId: entry.key, items: entry.value, cart: cart),
        const SizedBox(height: 8),
        _CoinsRow(),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLOBAL VOUCHER ROW
// ─────────────────────────────────────────────────────────────────────────────

class _GlobalVoucherRow extends StatelessWidget {
  const _GlobalVoucherRow({required this.cart});
  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    final applied = cart.platformCoupon;
    return InkWell(
      onTap: () => _openSheet(context),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.confirmation_number_outlined,
                  color: AppColors.secondary, size: 18),
            ),
            const SizedBox(width: 10),
            const Text(
              'Tropia Voucher',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (applied != null)
              Text(
                'Đã giảm ${_fmtDiscount(applied.discountAmount)}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              const Text(
                'Chọn hoặc nhập mã',
                style: TextStyle(color: AppColors.textHint, fontSize: 13),
              ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlatformVoucherSheet(
        cart: cart,
        onSelected: (coupon) {
          context.read<CartProvider>().applyPlatformCoupon(coupon);
          AppLogger.logUserEvent(
            action: 'platform_voucher_selected',
            context: _tag,
            metadata: {'code': coupon.code},
          );
        },
        onRemoved: () => context.read<CartProvider>().removePlatformCoupon(),
      ),
    );
  }

  String _fmtDiscount(int n) {
    if (n >= 1000) {
      final k = (n / 1000).floor();
      return '${k}kđ';
    }
    return '${n}đ';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PLATFORM VOUCHER SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _PlatformVoucherSheet extends StatefulWidget {
  const _PlatformVoucherSheet({
    required this.cart,
    required this.onSelected,
    required this.onRemoved,
  });
  final CartProvider cart;
  final void Function(CouponModel) onSelected;
  final VoidCallback onRemoved;

  @override
  State<_PlatformVoucherSheet> createState() => _PlatformVoucherSheetState();
}

class _PlatformVoucherSheetState extends State<_PlatformVoucherSheet> {
  List<CouponModel> _coupons = [];
  bool _loading = true;
  String? _selectedCode;
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.cart.platformCoupon?.coupon.code;
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await CouponRepository.instance.getAvailable();
      if (mounted) setState(() { _coupons = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Tropia Voucher',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Nhập mã voucher',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: AppColors.textHint),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide:
                              const BorderSide(color: AppColors.divider),
                        ),
                      ),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _applyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    child: const Text('Áp dụng',
                        style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _coupons.isEmpty
                      ? const Center(
                          child: Text(
                            'Chưa có voucher nào',
                            style: TextStyle(
                                color: AppColors.textHint, fontSize: 14),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _coupons.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: AppColors.divider),
                          itemBuilder: (_, i) => _CouponTile(
                            coupon: _coupons[i],
                            isSelected: _selectedCode == _coupons[i].code,
                            onTap: () => _select(_coupons[i]),
                          ),
                        ),
            ),
            if (_selectedCode != null)
              _ConfirmBar(
                label: 'Xác nhận',
                onTap: () {
                  final c =
                      _coupons.where((x) => x.code == _selectedCode).firstOrNull;
                  if (c != null) widget.onSelected(c);
                  Navigator.pop(context);
                },
              ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  void _select(CouponModel coupon) {
    setState(() =>
        _selectedCode = _selectedCode == coupon.code ? null : coupon.code);
  }

  void _applyCode() {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;
    final match = _coupons.where((c) => c.code == code).firstOrNull;
    if (match != null) {
      widget.onSelected(match);
      Navigator.pop(context);
    } else {
      _validateAndApplyCode(code);
    }
  }

  Future<void> _validateAndApplyCode(String code) async {
    final subtotal = widget.cart.summary.totalPrice;
    try {
      final result = await CouponRepository.instance
          .validate(code: code, orderTotal: subtotal);
      final discount = (result['discountAmount'] as num?)?.toInt() ?? 0;
      final couponId = result['couponId'] as String? ?? '';
      final discountType = result['discountType'] as String? ?? 'fixed';
      final discountValue =
          (result['discountValue'] as num?)?.toDouble() ?? discount.toDouble();
      final fake = CouponModel(
        id: couponId,
        code: code,
        discountType: discountType,
        discountValue: discountValue,
        minOrderValue: 0,
        expiresAt: DateTime.now().add(const Duration(days: 1)),
      );
      if (mounted) {
        widget.onSelected(fake);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: AppColors.secondary,
          ),
        );
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHOP VOUCHER SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ShopVoucherSheet extends StatefulWidget {
  const _ShopVoucherSheet({
    required this.shopId,
    required this.shopName,
    required this.cart,
    required this.onSelected,
    required this.onRemoved,
  });
  final String shopId;
  final String shopName;
  final CartProvider cart;
  final void Function(CouponModel) onSelected;
  final VoidCallback onRemoved;

  @override
  State<_ShopVoucherSheet> createState() => _ShopVoucherSheetState();
}

class _ShopVoucherSheetState extends State<_ShopVoucherSheet> {
  List<CouponModel> _coupons = [];
  bool _loading = true;
  String? _selectedCode;

  @override
  void initState() {
    super.initState();
    _selectedCode = widget.cart.shopCoupons[widget.shopId]?.coupon.code;
    _load();
  }

  Future<void> _load() async {
    try {
      final list =
          await CouponRepository.instance.getShopCoupons(widget.shopId);
      if (mounted) setState(() { _coupons = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      builder: (_, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                'Voucher của ${widget.shopName}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary),
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _coupons.isEmpty
                      ? const Center(
                          child: Text(
                            'Shop chưa có voucher nào',
                            style: TextStyle(
                                color: AppColors.textHint, fontSize: 14),
                          ),
                        )
                      : ListView.separated(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _coupons.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, color: AppColors.divider),
                          itemBuilder: (_, i) => _CouponTile(
                            coupon: _coupons[i],
                            isSelected: _selectedCode == _coupons[i].code,
                            onTap: () => setState(() =>
                                _selectedCode = _selectedCode == _coupons[i].code
                                    ? null
                                    : _coupons[i].code),
                          ),
                        ),
            ),
            if (widget.cart.shopCoupons.containsKey(widget.shopId) &&
                _selectedCode == null)
              TextButton(
                onPressed: () {
                  widget.onRemoved();
                  Navigator.pop(context);
                },
                child: const Text(
                  'Bỏ voucher đã chọn',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            if (_selectedCode != null)
              _ConfirmBar(
                label: 'Xác nhận',
                onTap: () {
                  final c =
                      _coupons.where((x) => x.code == _selectedCode).firstOrNull;
                  if (c != null) widget.onSelected(c);
                  Navigator.pop(context);
                },
              ),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COUPON TILE
// ─────────────────────────────────────────────────────────────────────────────

class _CouponTile extends StatelessWidget {
  const _CouponTile({
    required this.coupon,
    required this.isSelected,
    required this.onTap,
  });
  final CouponModel coupon;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.confirmation_number,
                  color: AppColors.secondary, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    coupon.discountLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Mã: ${coupon.code}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (coupon.minOrderValue > 0)
                    Text(
                      'Đơn tối thiểu ${_fmt(coupon.minOrderValue)}',
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textHint),
                    ),
                ],
              ),
            ),
            Radio<String>(
              value: coupon.code,
              groupValue: isSelected ? coupon.code : null,
              onChanged: (_) => onTap(),
              activeColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf}đ';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CONFIRM BAR
// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COINS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _CoinsRow extends StatefulWidget {
  @override
  State<_CoinsRow> createState() => _CoinsRowState();
}

class _CoinsRowState extends State<_CoinsRow> {
  bool _useCoins = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: const BoxDecoration(
              color: AppColors.secondary,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text(
                'T',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tropia Xu',
                  style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600),
                ),
                Text(
                  _useCoins
                      ? 'Bạn đang dùng xu để giảm giá'
                      : 'Bạn chưa chọn sản phẩm',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textHint),
                ),
              ],
            ),
          ),
          Switch(
            value: _useCoins,
            onChanged: (v) => setState(() => _useCoins = v),
            activeThumbColor: AppColors.primary,
            activeTrackColor: AppColors.primaryContainer,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHOP GROUP
// ─────────────────────────────────────────────────────────────────────────────

class _ShopGroup extends StatelessWidget {
  const _ShopGroup({
    required this.shopId,
    required this.items,
    required this.cart,
  });
  final String shopId;
  final List<CartItemModel> items;
  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    final allShopSelected = items.every((i) => i.isSelected);
    final shopName = items.first.shopName;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Shop header ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 12, 6),
            child: Row(
              children: [
                Checkbox(
                  value: allShopSelected,
                  onChanged: (_) =>
                      _toggleShop(cart, items, allShopSelected),
                  activeColor: AppColors.primary,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                _ShopBadge(shopName: shopName),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    shopName.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Icon(Icons.chevron_right,
                    size: 16, color: AppColors.textSecondary),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.divider),

          // ── Items ────────────────────────────────────────────────────────
          ...items.map((item) => _CartItemTile(item: item, cart: cart)),

          const Divider(height: 1, color: AppColors.divider),

          // ── Gift row ─────────────────────────────────────────────────────
          _GiftRow(),

          const Divider(height: 1, color: AppColors.divider),

          // ── Shop voucher row ──────────────────────────────────────────────
          _ShopVoucherRow(shopId: shopId, shopName: shopName, cart: cart),
        ],
      ),
    );
  }

  void _toggleShop(
      CartProvider cart, List<CartItemModel> items, bool allSelected) {
    final newVal = !allSelected;
    for (final item in items) {
      if (item.isSelected != newVal) {
        cart.toggleSelected(item.id);
      }
    }
  }
}

class _ShopBadge extends StatelessWidget {
  const _ShopBadge({required this.shopName});
  final String shopName;

  @override
  Widget build(BuildContext context) {
    final isMall = shopName.toLowerCase().contains('official') ||
        shopName.toLowerCase().contains('mall');
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: isMall ? const Color(0xFFEE4D2D) : AppColors.primary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isMall ? 'Mall' : 'Yêu thích',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GIFT ROW
// ─────────────────────────────────────────────────────────────────────────────

class _GiftRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.card_giftcard,
                color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Mua tối thiểu 390kđ để nhận quà',
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHOP VOUCHER ROW
// ─────────────────────────────────────────────────────────────────────────────

class _ShopVoucherRow extends StatefulWidget {
  const _ShopVoucherRow({
    required this.shopId,
    required this.shopName,
    required this.cart,
  });
  final String shopId;
  final String shopName;
  final CartProvider cart;

  @override
  State<_ShopVoucherRow> createState() => _ShopVoucherRowState();
}

class _ShopVoucherRowState extends State<_ShopVoucherRow> {
  List<CouponModel>? _shopCoupons;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  Future<void> _loadCoupons() async {
    try {
      final list =
          await CouponRepository.instance.getShopCoupons(widget.shopId);
      if (mounted) setState(() => _shopCoupons = list);
    } catch (_) {
      if (mounted) setState(() => _shopCoupons = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final applied = widget.cart.shopCoupons[widget.shopId];

    String label;
    Color labelColor;

    if (applied != null) {
      label = 'Đã giảm ${_fmtDiscount(applied.discountAmount)}';
      labelColor = AppColors.secondary;
    } else if (_shopCoupons != null && _shopCoupons!.isNotEmpty) {
      final maxVal = _shopCoupons!
          .map((c) => c.discountValue)
          .reduce((a, b) => a > b ? a : b);
      final firstType = _shopCoupons!.first.discountType;
      label = firstType == 'percent'
          ? 'Voucher giảm đến ${maxVal.toInt()}%'
          : 'Voucher giảm đến ${_fmtDiscount(maxVal.toInt())}';
      labelColor = AppColors.secondary;
    } else if (_shopCoupons == null) {
      label = 'Đang tải voucher...';
      labelColor = AppColors.textHint;
    } else {
      label = 'Chọn voucher shop';
      labelColor = AppColors.textHint;
    }

    return InkWell(
      onTap: _shopCoupons != null ? () => _openSheet(context) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.confirmation_number_outlined,
                color: AppColors.secondary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 13,
                    color: labelColor,
                    fontWeight: applied != null
                        ? FontWeight.w600
                        : FontWeight.normal),
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  void _openSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShopVoucherSheet(
        shopId: widget.shopId,
        shopName: widget.shopName,
        cart: widget.cart,
        onSelected: (coupon) {
          context.read<CartProvider>().applyShopCoupon(widget.shopId, coupon);
          AppLogger.logUserEvent(
            action: 'shop_voucher_selected',
            context: _tag,
            metadata: {'shopId': widget.shopId, 'code': coupon.code},
          );
        },
        onRemoved: () =>
            context.read<CartProvider>().removeShopCoupon(widget.shopId),
      ),
    );
  }

  String _fmtDiscount(int n) {
    if (n >= 1000) {
      final k = (n / 1000).floor();
      return '${k}kđ';
    }
    return '${n}đ';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CART ITEM TILE
// ─────────────────────────────────────────────────────────────────────────────

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.item, required this.cart});
  final CartItemModel item;
  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: const BoxDecoration(
          color: AppColors.secondary,
          borderRadius: BorderRadius.only(
            topRight: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: Colors.white, size: 24),
            SizedBox(height: 4),
            Text('Xoá', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        await cart.removeItem(item.id);
        return false;
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: item.isSelected,
              onChanged: (_) => cart.toggleSelected(item.id),
              activeColor: AppColors.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: item.imageUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.imageUrl!,
                      width: 88,
                      height: 88,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _imgPlaceholder(),
                      errorWidget: (_, __, ___) => _imgPlaceholder(),
                    )
                  : _imgPlaceholder(),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        color: AppColors.textPrimary,
                        height: 1.3,
                        fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 5),
                  if (item.attributeLabel.isNotEmpty)
                    _VariantChip(label: item.attributeLabel),
                  const SizedBox(height: 5),
                  if (item.hasDiscount) _VoucherTags(hasDiscount: true),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _fmt(item.unitPrice),
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary,
                              ),
                            ),
                            if (item.hasDiscount)
                              Row(
                                children: [
                                  Text(
                                    _fmt(item.originalPrice),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.textHint,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  _DiscountBadge(
                                      percent: item.discountPercent),
                                ],
                              ),
                          ],
                        ),
                      ),
                      _QuantityStepper(item: item, cart: cart),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imgPlaceholder() => Container(
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image_outlined,
            color: AppColors.textHint, size: 32),
      );

  String _fmt(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '$bufđ';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VARIANT CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _VariantChip extends StatelessWidget {
  const _VariantChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Đổi phân loại (tính năng sắp ra mắt)'),
              duration: Duration(seconds: 1)),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.divider),
          borderRadius: BorderRadius.circular(6),
          color: AppColors.background,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down,
                size: 14, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// VOUCHER TAGS
// ─────────────────────────────────────────────────────────────────────────────

class _VoucherTags extends StatelessWidget {
  const _VoucherTags({required this.hasDiscount});
  final bool hasDiscount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (hasDiscount) _tag('VOUCHER', AppColors.secondary),
        if (hasDiscount) const SizedBox(width: 4),
        _tag('FREESHIP', const Color(0xFF1BA462)),
      ],
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DISCOUNT BADGE
// ─────────────────────────────────────────────────────────────────────────────

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.percent});
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        '-$percent%',
        style: const TextStyle(
          fontSize: 11,
          color: AppColors.secondary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUANTITY STEPPER
// ─────────────────────────────────────────────────────────────────────────────

class _QuantityStepper extends StatelessWidget {
  const _QuantityStepper({required this.item, required this.cart});
  final CartItemModel item;
  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepBtn(
          icon: item.quantity > 1 ? Icons.remove : Icons.delete_outline,
          onTap: item.quantity > 1
              ? () => cart.updateQuantity(item.id, item.quantity - 1)
              : () => cart.removeItem(item.id),
          isDestructive: item.quantity == 1,
        ),
        Container(
          constraints: const BoxConstraints(minWidth: 36),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: const BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: AppColors.divider),
            ),
          ),
          child: Text(
            '${item.quantity}',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        _StepBtn(
          icon: Icons.add,
          onTap: () => cart.updateQuantity(item.id, item.quantity + 1),
        ),
      ],
    );
  }
}

class _StepBtn extends StatelessWidget {
  const _StepBtn({
    required this.icon,
    required this.onTap,
    this.isDestructive = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool isDestructive;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon,
              size: 16,
              color: isDestructive
                  ? AppColors.secondary
                  : AppColors.textPrimary),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// CHECKOUT BAR
// ─────────────────────────────────────────────────────────────────────────────

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.cart});
  final CartProvider cart;

  @override
  Widget build(BuildContext context) {
    final s = cart.summary;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final couponDiscount = cart.totalCouponDiscount;

    return Container(
      padding: EdgeInsets.fromLTRB(4, 10, 12, 10 + bottomPad),
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Checkbox(
            value: cart.allSelected,
            onChanged: (_) => cart.toggleSelectAll(),
            activeColor: AppColors.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          GestureDetector(
            onTap: () => cart.toggleSelectAll(),
            child: const Text(
              'Tất cả',
              style: TextStyle(
                  fontSize: 13, color: AppColors.textPrimary),
            ),
          ),
          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _fmt(s.totalPrice),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary,
                  ),
                ),
                if (s.totalSaving > 0)
                  Text(
                    'Tiết kiệm ${_fmt(s.totalSaving)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.primaryLight),
                  ),
                if (couponDiscount > 0)
                  Text(
                    'Đã giảm ${_fmt(couponDiscount)}',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.secondary),
                  ),
              ],
            ),
          ),

          const SizedBox(width: 10),

          ElevatedButton(
            onPressed: s.totalItems > 0 ? () => _onCheckout(context) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.divider,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            child: Text(
              'Mua hàng (${s.totalItems})',
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _onCheckout(BuildContext context) {
    final selectedItems = cart.items.where((i) => i.isSelected).toList();
    if (selectedItems.isEmpty) return;
    AppLogger.logUserEvent(
      action: 'checkout_tapped',
      context: _tag,
      metadata: {'totalItems': selectedItems.length},
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(items: selectedItems),
      ),
    ).then((_) {
      // Reload after returning from checkout so the cart reflects what
      // the backend actually has — for online payments (MoMo / VNPay /
      // ZaloPay) the pay URL opens in a new tab, the user comes back
      // here, and MarkPaid (server-side) has already deleted the
      // checked-out cart_items. Without this refresh the local
      // CartProvider keeps the stale items and the user sees a paid
      // cart that should be empty.
      if (context.mounted) {
        context.read<CartProvider>().load();
      }
    });
  }

  String _fmt(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '$bufđ';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY CART
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shopping_cart_outlined,
                size: 50, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text(
            'Giỏ hàng trống',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Thêm sản phẩm yêu thích vào giỏ nhé!',
            style: TextStyle(color: AppColors.textHint, fontSize: 14),
          ),
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(
                  horizontal: 36, vertical: 13),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Mua sắm ngay',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ],
      ),
    );
  }
}
