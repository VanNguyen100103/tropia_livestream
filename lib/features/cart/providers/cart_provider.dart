import 'package:flutter/foundation.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/cart/data/cart_repository.dart';
import 'package:tropia/features/cart/models/cart_item_model.dart';
import 'package:tropia/features/coupon/data/coupon_repository.dart';

const _tag = 'CartProvider';

enum CartStatus { idle, loading, error }

/// Coupon đã áp dụng (platform hoặc shop)
class AppliedCoupon {
  final CouponModel coupon;
  final int discountAmount;

  const AppliedCoupon({required this.coupon, required this.discountAmount});
}

class CartProvider extends ChangeNotifier {
  final _repo = CartRepository.instance;

  List<CartItemModel> _items = [];
  CartSummary _summary = const CartSummary(totalItems: 0, totalPrice: 0, totalSaving: 0);
  CartStatus _status = CartStatus.idle;
  String? _error;

  // ── Coupon state ─────────────────────────────────────────────────────────
  AppliedCoupon? _platformCoupon;
  final Map<String, AppliedCoupon> _shopCoupons = {}; // shopId → applied

  // Các coupon code đã lưu từ live — persist qua nhiều lần vào/ra live screen
  final Set<String> _savedLiveCouponCodes = {};
  Set<String> get savedLiveCouponCodes => Set.unmodifiable(_savedLiveCouponCodes);

  void markLiveCouponSaved(String code) {
    _savedLiveCouponCodes.add(code.toUpperCase());
  }

  bool isLiveCouponSaved(String code) =>
      _savedLiveCouponCodes.contains(code.toUpperCase());

  AppliedCoupon? get platformCoupon => _platformCoupon;
  Map<String, AppliedCoupon> get shopCoupons => Map.unmodifiable(_shopCoupons);

  int get platformDiscount  => _platformCoupon?.discountAmount ?? 0;
  int get totalShopDiscount => _shopCoupons.values.fold(0, (s, c) => s + c.discountAmount);
  int get totalCouponDiscount => platformDiscount + totalShopDiscount;

  List<CartItemModel> get items   => _items;
  CartSummary         get summary => _summary;
  CartStatus          get status  => _status;
  String?             get error   => _error;

  int get totalCount => _items.fold(0, (s, i) => s + i.quantity);
  bool get isEmpty   => _items.isEmpty;

  Map<String, List<CartItemModel>> get itemsByShop {
    final map = <String, List<CartItemModel>>{};
    for (final item in _items) {
      map.putIfAbsent(item.shopId, () => []).add(item);
    }
    return map;
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> load() async {
    _status = CartStatus.loading;
    _error  = null;
    notifyListeners();
    try {
      final result = await _repo.getCart();
      _items   = result.items;
      _recalcSummary();
      _status  = CartStatus.idle;
    } catch (e) {
      _error  = e.toString();
      _status = CartStatus.error;
      AppLogger.logError(_tag, 'load failed', e, null);
    }
    notifyListeners();
  }

  // ── Add ───────────────────────────────────────────────────────────────────

  Future<void> addItem(String variantId, {int quantity = 1}) async {
    try {
      final item = await _repo.addItem(variantId: variantId, quantity: quantity);
      final idx = _items.indexWhere((i) => i.variantId == variantId);
      if (idx >= 0) {
        _items[idx] = item;
      } else {
        _items.insert(0, item);
      }
      _recalcSummary();
      notifyListeners();
    } catch (e) {
      AppLogger.logError(_tag, 'addItem failed', e, null);
      rethrow;
    }
  }

  // ── Quantity ──────────────────────────────────────────────────────────────

  Future<void> updateQuantity(String itemId, int quantity) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx < 0) return;
    final prev = _items[idx].quantity;
    _items[idx].quantity = quantity;
    _recalcSummary();
    notifyListeners();
    try {
      await _repo.updateQuantity(itemId, quantity);
    } catch (e) {
      _items[idx].quantity = prev;
      _recalcSummary();
      notifyListeners();
      AppLogger.logError(_tag, 'updateQuantity failed', e, null);
    }
  }

  // ── Select ────────────────────────────────────────────────────────────────

  Future<void> toggleSelected(String itemId) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx < 0) return;
    final newVal = !_items[idx].isSelected;
    _items[idx].isSelected = newVal;
    _recalcSummary();
    notifyListeners();
    try {
      await _repo.updateSelected(itemId, isSelected: newVal);
    } catch (e) {
      _items[idx].isSelected = !newVal;
      _recalcSummary();
      notifyListeners();
      AppLogger.logError(_tag, 'toggleSelected failed', e, null);
    }
  }

  Future<void> toggleSelectAll() async {
    final allSelected = _items.every((i) => i.isSelected);
    final newVal = !allSelected;
    for (final i in _items) { i.isSelected = newVal; }
    _recalcSummary();
    notifyListeners();
    try {
      await _repo.selectAll(isSelected: newVal);
    } catch (e) {
      for (final i in _items) { i.isSelected = !newVal; }
      _recalcSummary();
      notifyListeners();
      AppLogger.logError(_tag, 'selectAll failed', e, null);
    }
  }

  bool get allSelected => _items.isNotEmpty && _items.every((i) => i.isSelected);

  // ── Remove ────────────────────────────────────────────────────────────────

  Future<void> removeItem(String itemId) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx < 0) return;
    final removed = _items.removeAt(idx);
    _recalcSummary();
    notifyListeners();
    try {
      await _repo.removeItem(itemId);
    } catch (e) {
      _items.insert(idx, removed);
      _recalcSummary();
      notifyListeners();
      AppLogger.logError(_tag, 'removeItem failed', e, null);
    }
  }

  Future<void> removeSelected() async {
    final kept    = _items.where((i) => !i.isSelected).toList();
    final removed = _items.where((i) => i.isSelected).toList();
    _items = kept;
    _recalcSummary();
    notifyListeners();
    try {
      await _repo.removeSelected();
    } catch (e) {
      _items = [...removed, ...kept];
      _recalcSummary();
      notifyListeners();
      AppLogger.logError(_tag, 'removeSelected failed', e, null);
    }
  }

  // ── Coupon actions ────────────────────────────────────────────────────────

  /// Áp dụng platform coupon. Tính discount dựa trên subtotal selected.
  void applyPlatformCoupon(CouponModel coupon) {
    final subtotal = _summary.totalPrice;
    _platformCoupon = AppliedCoupon(
      coupon: coupon,
      discountAmount: coupon.calcDiscount(subtotal),
    );
    _recalcSummary();
    notifyListeners();
    AppLogger.logUserEvent(
      action: 'platform_coupon_applied',
      context: _tag,
      metadata: {'code': coupon.code, 'discount': _platformCoupon!.discountAmount},
    );
  }

  void removePlatformCoupon() {
    _platformCoupon = null;
    _recalcSummary();
    notifyListeners();
  }

  /// Áp dụng coupon cho shop. Tính discount dựa trên subtotal của shop đó.
  void applyShopCoupon(String shopId, CouponModel coupon) {
    final shopSubtotal = _items
        .where((i) => i.shopId == shopId && i.isSelected)
        .fold(0, (s, i) => s + i.subtotal);
    _shopCoupons[shopId] = AppliedCoupon(
      coupon: coupon,
      discountAmount: coupon.calcDiscount(shopSubtotal),
    );
    _recalcSummary();
    notifyListeners();
    AppLogger.logUserEvent(
      action: 'shop_coupon_applied',
      context: _tag,
      metadata: {'shopId': shopId, 'code': coupon.code},
    );
  }

  void removeShopCoupon(String shopId) {
    _shopCoupons.remove(shopId);
    _recalcSummary();
    notifyListeners();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _recalcSummary() {
    final selected = _items.where((i) => i.isSelected);
    final rawPrice  = selected.fold(0, (s, i) => s + i.subtotal);
    final rawSaving = selected.fold(0, (s, i) => s + i.saving);
    final couponSaving = totalCouponDiscount;
    _summary = CartSummary(
      totalItems:  selected.fold(0, (s, i) => s + i.quantity),
      totalPrice:  (rawPrice - couponSaving).clamp(0, rawPrice),
      totalSaving: rawSaving + couponSaving,
    );
  }
}
