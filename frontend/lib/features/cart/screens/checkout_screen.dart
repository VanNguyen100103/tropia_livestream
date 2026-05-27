// =============================================================================
// checkout_screen.dart – Màn hình thanh toán Tropia
// =============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/cart/models/cart_item_model.dart';
import 'package:tropia/features/cart/providers/cart_provider.dart';
import 'package:tropia/features/order/data/order_repository.dart';
import 'package:tropia/features/order/models/order_model.dart';
import 'package:tropia/features/payment/data/payment_repository.dart';

const _tag = 'CheckoutScreen';

// ── Entry point ───────────────────────────────────────────────────────────────

class CheckoutScreen extends StatefulWidget {
  final List<CartItemModel> items;

  /// Chỉ truyền khi mua trực tiếp từ màn live (không qua giỏ hàng thường)
  final String? liveSessionId;

  const CheckoutScreen({
    super.key,
    required this.items,
    this.liveSessionId,
  });

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum _FulfillmentMode { delivery, pickup }

class _CheckoutScreenState extends State<CheckoutScreen>
    with SingleTickerProviderStateMixin {

  // ── Tabs ──────────────────────────────────────────────────────────────────
  late final TabController _tabCtrl;
  _FulfillmentMode _mode = _FulfillmentMode.delivery;

  // ── Address ───────────────────────────────────────────────────────────────
  _Address _selectedAddress = const _Address(
    name: '', phone: '', address: 'Vui lòng thêm địa chỉ giao hàng',
  );

  // ── Delivery time ─────────────────────────────────────────────────────────
  late DateTime _deliveryDate;
  String _deliverySlot = '16:00-17:00';

  // ── Payment method ────────────────────────────────────────────────────────
  _PayMethod _payMethod = _PayMethod.cod;

  // ── Note ─────────────────────────────────────────────────────────────────
  final _noteCtrl = TextEditingController();

  // ── Shipping ──────────────────────────────────────────────────────────────
  static const int _shippingFee = 0;

  bool _placing = false;

  // ── Computed ──────────────────────────────────────────────────────────────
  int get _subtotal =>
      widget.items.fold(0, (s, i) => s + i.unitPrice * i.quantity);

  // Discount lấy từ CartProvider (đã áp từ màn giỏ hàng)
  int get _couponDiscount =>
      context.read<CartProvider>().totalCouponDiscount;

  int get _total =>
      (_subtotal + _shippingFee - _couponDiscount).clamp(0, 999999999);

  int get _totalItems =>
      widget.items.fold(0, (s, i) => s + i.quantity);

  @override
  void initState() {
    super.initState();
    _deliveryDate = DateTime.now().add(const Duration(days: 1));
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() {
          _mode = _tabCtrl.index == 0
              ? _FulfillmentMode.delivery
              : _FulfillmentMode.pickup;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ── Place order ───────────────────────────────────────────────────────────

  Future<void> _placeOrder() async {
    if (_placing) return;
    if (_selectedAddress.phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng thêm địa chỉ giao hàng')),
      );
      return;
    }

    setState(() => _placing = true);
    try {
      final cart = context.read<CartProvider>();
      // Gom tất cả voucher đang áp (platform + shop) để BE validate và sum
      // discount đồng nhất với FE. Trước đây chỉ gửi platformCoupon → shop
      // voucher bị mất, MoMo charge full subtotal trong khi FE show đã giảm.
      final couponCodes = <String>[
        if (cart.platformCoupon != null) cart.platformCoupon!.coupon.code,
        for (final applied in cart.shopCoupons.values) applied.coupon.code,
      ];
      final note = _noteCtrl.text.trim();

      // Tab "Nhận tại cửa hàng" không có địa chỉ giao — gửi null để
      // backend lưu NULL vào shipping_* và email biên lai bỏ qua block
      // địa chỉ. Tab "Giao hàng" thì gửi snapshot từ _selectedAddress.
      final bool isDelivery = _mode == _FulfillmentMode.delivery;
      final String? shipName    = isDelivery ? _selectedAddress.name    : null;
      final String? shipPhone   = isDelivery ? _selectedAddress.phone   : null;
      final String? shipAddress = isDelivery ? _selectedAddress.address : null;

      // Gọi endpoint /api/orders/checkout (hỗ trợ cả live và cart thường)
      final result = await OrderRepository.instance.checkout(
        items: widget.items.map((item) => CheckoutItem(
          cartItemId:  item.id,
          variantId:   item.variantId,
          quantity:    item.quantity,
          unitPrice:   item.unitPrice,
          productName: item.productName,
          sessionId:   widget.liveSessionId,
        )).toList(),
        couponCodes:     couponCodes,
        discountAmount:  cart.totalCouponDiscount,
        paymentMethod:   _payMethod.name,
        note:            note.isEmpty ? null : note,
        shippingName:    shipName,
        shippingPhone:   shipPhone,
        shippingAddress: shipAddress,
      );

      final orders = result.orders;

      // Online payment: KHÔNG xoá items lúc tạo đơn. Backend cũng giữ
      // cart_items lại cho đến khi gateway IPN/callback xác nhận paid
      // (MarkPaid sẽ xoá). Nếu thanh toán fail/cancel/đóng app → giỏ
      // còn nguyên, buyer có thể thử lại.
      if (_payMethod != _PayMethod.cod && orders.isNotEmpty) {
        await _initiateOnlinePayment(orders.first);
        return;
      }

      // COD → đơn đã commit ngay → xoá items khỏi giỏ (mirror backend).
      for (final item in widget.items) {
        await cart.removeItem(item.id);
      }
      cart.removePlatformCoupon();

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => _OrderSuccessScreen(
              orders: orders,
              total: result.grandTotal,
            ),
          ),
        );
      }

      AppLogger.logUserEvent(
        action: 'order_placed',
        context: _tag,
        metadata: {
          'count': orders.length,
          'total': result.grandTotal,
          'couponDiscount': result.couponDiscount,
        },
      );
    } catch (e, st) {
      AppLogger.logError(_tag, 'placeOrder failed', e, st);
      if (!mounted) return;
      final msg = _explainCheckoutError(e);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  /// Dịch lỗi checkout sang tiếng Việt thân thiện và tự gỡ voucher hỏng.
  ///
  /// Backend [ApplyCoupon] trả 422 `VALIDATION_ERROR` với
  /// `details = {coupon_code, reason}` cho mọi lỗi voucher (limit_reached,
  /// expired, inactive, already_used, min_order, not_found). Khi gặp lỗi
  /// voucher, ta vừa show thông báo cụ thể vừa gỡ luôn voucher đang áp khỏi
  /// CartProvider để lần checkout sau không lặp lại lỗi.
  String _explainCheckoutError(Object err) {
    if (err is! DioException) return 'Đặt hàng thất bại: $err';
    final data = err.response?.data;
    if (data is! Map) return 'Đặt hàng thất bại, vui lòng thử lại';

    final details = data['details'];
    if (details is Map && details['coupon_code'] is String) {
      final code = details['coupon_code'] as String;
      final reason = details['reason'] as String? ?? '';
      _unapplyCoupon(code);
      switch (reason) {
        case 'limit_reached':
          return 'Mã giảm giá $code đã hết lượt sử dụng. Voucher đã được gỡ khỏi đơn — vui lòng đặt lại.';
        case 'expired':
          return 'Mã giảm giá $code đã hết hạn. Voucher đã được gỡ khỏi đơn — vui lòng đặt lại.';
        case 'inactive':
          return 'Mã giảm giá $code đã ngừng áp dụng. Voucher đã được gỡ khỏi đơn — vui lòng đặt lại.';
        case 'already_used':
          return 'Bạn đã sử dụng mã $code trước đó. Voucher đã được gỡ khỏi đơn — vui lòng đặt lại.';
        case 'min_order':
          return 'Đơn chưa đạt giá trị tối thiểu để dùng mã $code. Voucher đã được gỡ khỏi đơn.';
        case 'not_found':
          return 'Mã giảm giá $code không tồn tại. Voucher đã được gỡ khỏi đơn.';
      }
    }

    final raw = (data['error'] ?? data['message']) as String?;
    return raw != null && raw.isNotEmpty
        ? 'Đặt hàng thất bại: $raw'
        : 'Đặt hàng thất bại, vui lòng thử lại';
  }

  void _unapplyCoupon(String code) {
    final cart = context.read<CartProvider>();
    if (cart.platformCoupon?.coupon.code == code) {
      cart.removePlatformCoupon();
      return;
    }
    for (final entry in cart.shopCoupons.entries) {
      if (entry.value.coupon.code == code) {
        cart.removeShopCoupon(entry.key);
        return;
      }
    }
  }

  Future<void> _initiateOnlinePayment(OrderModel order) async {
    try {
      final String payUrl;
      switch (_payMethod) {
        case _PayMethod.momo:
          payUrl = await PaymentRepository.instance
              .initMomo(orderId: order.id, amount: _total);
        case _PayMethod.zalopay:
          payUrl = await PaymentRepository.instance
              .initZalopay(orderId: order.id, amount: _total);
        case _PayMethod.vnpay:
          payUrl = await PaymentRepository.instance
              .initVnpay(orderId: order.id, amount: _total);
        case _PayMethod.cod:
          return;
      }
      final uri = Uri.parse(payUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Không thể mở trang thanh toán');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể khởi tạo thanh toán: $e')),
        );
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Rebuild khi CartProvider thay đổi (coupon discount cập nhật)
    return Consumer<CartProvider>(
      builder: (context, cart, _) {
        final couponDiscount = cart.totalCouponDiscount;
        final appliedCode    = cart.platformCoupon?.coupon.code;
        final total = (_subtotal + _shippingFee - couponDiscount)
            .clamp(0, 999999999);
        final totalItems = _totalItems;
        final estimatedPoints = (total / 1000).floor();

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: _buildAppBar(),
          body: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              _buildTabBar(),
              const SizedBox(height: 8),
              if (_mode == _FulfillmentMode.delivery) ...[
                _buildAddressCard(),
                const SizedBox(height: 8),
                _buildStoreDeliveryCard(),
              ] else ...[
                _buildPickupCard(),
              ],
              const SizedBox(height: 8),
              _buildItemsCard(),
              const SizedBox(height: 8),
              if (estimatedPoints > 0) ...[
                _buildPointsCard(estimatedPoints),
                const SizedBox(height: 8),
              ],
              _buildPaymentCard(),
              const SizedBox(height: 8),
              _buildNoteCard(),
              const SizedBox(height: 8),
              // Hiển thị coupon đã áp từ giỏ hàng (nếu có)
              if (appliedCode != null) ...[
                _buildAppliedCouponCard(appliedCode, couponDiscount),
                const SizedBox(height: 8),
              ],
              _buildOrderSummaryCard(
                subtotal: _subtotal,
                couponDiscount: couponDiscount,
                total: total,
              ),
            ],
          ),
          bottomNavigationBar: _buildOrderButton(
            totalItems: totalItems,
            total: total,
          ),
        );
      },
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: const Text(
        'Đặt hàng',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
      centerTitle: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: AppColors.surface,
      child: TabBar(
        controller: _tabCtrl,
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorWeight: 3,
        labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: 'Giao hàng'),
          Tab(text: 'Nhận tại cửa hàng'),
        ],
      ),
    );
  }

  // ── Address card ──────────────────────────────────────────────────────────

  Widget _buildAddressCard() {
    final addr = _selectedAddress;
    return _SectionCard(
      child: InkWell(
        onTap: _showAddressDialog,
        borderRadius: BorderRadius.circular(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.location_on,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    addr.address.isEmpty
                        ? 'Thêm địa chỉ giao hàng'
                        : addr.address,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: addr.address.isEmpty
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (addr.name.isNotEmpty || addr.phone.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      [addr.name, addr.phone]
                          .where((s) => s.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'Thay đổi',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddressDialog() {
    final nameCtrl  = TextEditingController(text: _selectedAddress.name);
    final phoneCtrl = TextEditingController(text: _selectedAddress.phone);
    final addrCtrl  = TextEditingController(
        text: _selectedAddress.address == 'Vui lòng thêm địa chỉ giao hàng'
            ? ''
            : _selectedAddress.address);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Địa chỉ giao hàng'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Họ tên')),
            const SizedBox(height: 8),
            TextField(controller: phoneCtrl,
                decoration:
                    const InputDecoration(labelText: 'Số điện thoại'),
                keyboardType: TextInputType.phone),
            const SizedBox(height: 8),
            TextField(controller: addrCtrl,
                decoration: const InputDecoration(labelText: 'Địa chỉ'),
                maxLines: 2),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _selectedAddress = _Address(
                  name:    nameCtrl.text.trim(),
                  phone:   phoneCtrl.text.trim(),
                  address: addrCtrl.text.trim().isEmpty
                      ? 'Vui lòng thêm địa chỉ giao hàng'
                      : addrCtrl.text.trim(),
                );
              });
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Lưu'),
          ),
        ],
      ),
    );
  }

  // ── Store + delivery time ─────────────────────────────────────────────────

  Widget _buildStoreDeliveryCard() {
    final d = _deliveryDate;
    final dayStr =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.storefront,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.items.isNotEmpty
                        ? widget.items.first.shopName
                        : 'Tropia Fresh Market',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Text('Giao hàng tận nơi',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickDeliveryTime,
            borderRadius: BorderRadius.circular(8),
            child: Row(children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.calendar_today,
                    color: AppColors.primary, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Thời gian giao hàng',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                    Text(
                      '$dayStr | $_deliverySlot',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textHint),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDeliveryTime() async {
    const slots = [
      '08:00-09:00', '10:00-11:00',
      '14:00-15:00', '16:00-17:00', '18:00-19:00',
    ];
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Chọn khung giờ',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.divider),
            ...slots.map((slot) => ListTile(
                  title: Text(slot),
                  trailing: _deliverySlot == slot
                      ? const Icon(Icons.check_circle,
                          color: AppColors.primary, size: 20)
                      : null,
                  onTap: () {
                    setState(() => _deliverySlot = slot);
                    Navigator.pop(ctx);
                  },
                )),
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
    );
  }

  // ── Pickup card ───────────────────────────────────────────────────────────

  Widget _buildPickupCard() {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.storefront,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.items.isNotEmpty
                        ? widget.items.first.shopName
                        : 'Tropia Fresh Market',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Text('Nhận tại cửa hàng',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Text('Thay đổi',
                style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 12),
          Row(children: [
            const Icon(Icons.location_on_outlined,
                color: AppColors.textSecondary, size: 16),
            const SizedBox(width: 6),
            const Expanded(
              child: Text('148 Đ. Trường Lưu, Thủ Đức, TP.HCM',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.access_time,
                color: AppColors.textSecondary, size: 16),
            const SizedBox(width: 6),
            const Text('Mở cửa: 07:00 – 21:00',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textSecondary)),
          ]),
        ],
      ),
    );
  }

  // ── Items card ────────────────────────────────────────────────────────────

  Widget _buildItemsCard() {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Tropia',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text(
              widget.items.isNotEmpty
                  ? widget.items.first.shopName
                  : 'Shop',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ]),
          const SizedBox(height: 12),
          ...widget.items.map((item) => _CheckoutItemRow(item: item)),
        ],
      ),
    );
  }

  // ── Points card ───────────────────────────────────────────────────────────

  Widget _buildPointsCard(int points) {
    return _SectionCard(
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: const BoxDecoration(
              color: AppColors.secondary, shape: BoxShape.circle),
          child: const Center(
            child: Text('T',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Dự kiến cộng $points điểm',
            style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500),
          ),
        ),
        const Icon(Icons.info_outline, size: 16, color: AppColors.textHint),
      ]),
    );
  }

  // ── Payment card ──────────────────────────────────────────────────────────

  Widget _buildPaymentCard() {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Phương thức thanh toán',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 10),
          ..._PayMethod.values.map((m) => _CompactPayTile(
                method: m,
                selected: _payMethod == m,
                onTap: () => setState(() => _payMethod = m),
              )),
        ],
      ),
    );
  }

  // ── Note card ─────────────────────────────────────────────────────────────

  Widget _buildNoteCard() {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ghi chú đơn hàng',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          TextField(
            controller: _noteCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              hintText: 'Để lại lời nhắn cho shop (tuỳ chọn)',
              hintStyle: const TextStyle(
                  color: AppColors.textHint, fontSize: 13),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Applied coupon card (đọc từ CartProvider) ─────────────────────────────

  Widget _buildAppliedCouponCard(String code, int discount) {
    return _SectionCard(
      child: Row(children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.confirmation_number_outlined,
              color: AppColors.primary, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mã: $code',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              if (discount > 0)
                Text('Giảm ${_fmtPrice(discount)}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.primary)),
            ],
          ),
        ),
        const Icon(Icons.check_circle, color: AppColors.primary, size: 18),
      ]),
    );
  }

  // ── Order summary card ────────────────────────────────────────────────────

  Widget _buildOrderSummaryCard({
    required int subtotal,
    required int couponDiscount,
    required int total,
  }) {
    return _SectionCard(
      child: Column(children: [
        _SummaryRow('Tổng tiền hàng', subtotal),
        _SummaryRow(
          _mode == _FulfillmentMode.delivery
              ? 'Phí vận chuyển'
              : 'Nhận tại cửa hàng',
          _shippingFee,
          zeroLabel: 'Miễn phí',
        ),
        if (couponDiscount > 0)
          _SummaryRow('Giảm giá voucher', -couponDiscount,
              color: AppColors.primary),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: AppColors.divider),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Tổng thanh toán',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            Text(_fmtPrice(total),
                style: const TextStyle(
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
          ],
        ),
      ]),
    );
  }

  // ── Order button ──────────────────────────────────────────────────────────

  Widget _buildOrderButton({required int totalItems, required int total}) {
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomPad),
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
      child: ElevatedButton(
        onPressed: _placing ? null : _placeOrder,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.secondary,
          disabledBackgroundColor: AppColors.divider,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
        child: _placing
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$totalItems',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.shopping_cart,
                      size: 18, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Đặt hàng  ${_fmtPrice(total)}',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ],
              ),
      ),
    );
  }

  String _fmtPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf}đ';
  }
}

// =============================================================================
// Helper data classes
// =============================================================================

class _Address {
  final String name;
  final String phone;
  final String address;
  final bool isDefault;

  const _Address({
    required this.name,
    required this.phone,
    required this.address,
    this.isDefault = false,
  });
}

enum _PayMethod { cod, momo, zalopay, vnpay }

// =============================================================================
// Sub-widgets
// =============================================================================

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
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
      child: child,
    );
  }
}

class _CheckoutItemRow extends StatelessWidget {
  const _CheckoutItemRow({required this.item});
  final CartItemModel item;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.imageUrl != null
                ? Image.network(
                    item.imageUrl!,
                    width: 72, height: 72, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _placeholder(),
                  )
                : _placeholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                    height: 1.3,
                  ),
                ),
                if (item.attributes.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.attributes.map((a) => a.value).join(', '),
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _fmt(item.unitPrice),
                      style: const TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 14),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.divider),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'SL: ${item.quantity}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500),
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

  Widget _placeholder() => Container(
        width: 72, height: 72,
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.image_outlined,
            color: AppColors.textHint, size: 28),
      );

  String _fmt(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf}đ';
  }
}

class _CompactPayTile extends StatelessWidget {
  const _CompactPayTile({
    required this.method,
    required this.selected,
    required this.onTap,
  });
  final _PayMethod method;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryContainer
              : AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(children: [
          Icon(_icon, size: 22, color: _color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textPrimary,
                  ),
                ),
                if (_subtitle != null)
                  Text(_subtitle!,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            width: 20, height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? AppColors.primary : AppColors.textHint,
                width: selected ? 6 : 2,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  IconData get _icon {
    switch (method) {
      case _PayMethod.cod:     return Icons.money;
      case _PayMethod.momo:    return Icons.account_balance_wallet;
      case _PayMethod.zalopay: return Icons.payment;
      case _PayMethod.vnpay:   return Icons.credit_card;
    }
  }

  Color get _color {
    switch (method) {
      case _PayMethod.cod:     return Colors.green;
      case _PayMethod.momo:    return const Color(0xFFAE2070);
      case _PayMethod.zalopay: return const Color(0xFF0068FF);
      case _PayMethod.vnpay:   return const Color(0xFF005BAA);
    }
  }

  String get _label {
    switch (method) {
      case _PayMethod.cod:     return 'Tiền mặt COD';
      case _PayMethod.momo:    return 'Ví MoMo';
      case _PayMethod.zalopay: return 'ZaloPay';
      case _PayMethod.vnpay:   return 'VNPay';
    }
  }

  String? get _subtitle {
    switch (method) {
      case _PayMethod.cod:     return 'Thanh toán khi nhận hàng';
      case _PayMethod.momo:    return null;
      case _PayMethod.zalopay: return null;
      case _PayMethod.vnpay:   return null;
    }
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow(this.label, this.amount, {this.color, this.zeroLabel});
  final String label;
  final int amount;
  final Color? color;
  final String? zeroLabel;

  @override
  Widget build(BuildContext context) {
    final isNeg = amount < 0;
    final display = isNeg ? _fmt(-amount) : _fmt(amount);
    final valueText = amount == 0 && zeroLabel != null
        ? zeroLabel!
        : (isNeg ? '-$display' : display);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          Text(
            valueText,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: amount == 0 && zeroLabel != null
                  ? AppColors.primary
                  : (color ?? AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf}đ';
  }
}

// =============================================================================
// Order success screen
// =============================================================================

class _OrderSuccessScreen extends StatelessWidget {
  const _OrderSuccessScreen({required this.orders, required this.total});
  final List<OrderModel> orders;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88, height: 88,
                decoration: const BoxDecoration(
                    color: AppColors.primaryContainer,
                    shape: BoxShape.circle),
                child: const Icon(Icons.check_circle,
                    color: AppColors.primary, size: 52),
              ),
              const SizedBox(height: 24),
              const Text('Đặt hàng thành công!',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('${orders.length} đơn hàng đã được tạo',
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 4),
              Text(_fmtPrice(total),
                  style: const TextStyle(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w700,
                      fontSize: 20)),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Về trang chủ',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  side: const BorderSide(color: AppColors.divider),
                ),
                child: const Text('Xem đơn hàng'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmtPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf}đ';
  }
}
