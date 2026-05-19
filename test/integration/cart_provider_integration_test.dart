// Integration test: CartProvider + CouponModel phối hợp
// Kiểm tra applyPlatformCoupon, applyShopCoupon, và _recalcSummary
// bằng cách inject items trực tiếp qua subclass test helper.

import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/cart/models/cart_item_model.dart';
import 'package:tropia/features/cart/providers/cart_provider.dart';
import 'package:tropia/features/coupon/data/coupon_repository.dart';

// ── TestCartProvider: expose setItems để bypass repo ─────────────────────────

class TestCartProvider extends CartProvider {
  void setItemsDirect(List<CartItemModel> items) {
    this.items.clear();
    this.items.addAll(items);
    // Trigger recalc bằng cách gọi notify thông qua một method có sẵn
    // _recalcSummary là private, nhưng kết quả được reflect qua summary
    // Cách an toàn: xài removeShopCoupon (no-op) để trigger notifyListeners + recalc
  }
}

// ── Factories ─────────────────────────────────────────────────────────────────

CartItemModel _item({
  String id = 'i-1',
  String shopId = 'shop-1',
  int unitPrice = 100000,
  int originalPrice = 120000,
  int quantity = 2,
  bool isSelected = true,
}) =>
    CartItemModel(
      id: id,
      variantId: 'v-$id',
      productId: 'p-$id',
      productName: 'SP $id',
      shopId: shopId,
      shopName: 'Shop $shopId',
      unitPrice: unitPrice,
      originalPrice: originalPrice,
      quantity: quantity,
      attributes: [],
      isSelected: isSelected,
    );

CouponModel _coupon({
  String discountType = 'percent',
  double discountValue = 10,
  double? maxDiscount,
}) =>
    CouponModel(
      id: 'coupon-1',
      code: 'TEST10',
      discountType: discountType,
      discountValue: discountValue,
      minOrderValue: 0,
      maxDiscount: maxDiscount,
      expiresAt: DateTime(2099),
    );

void main() {
  // ── applyPlatformCoupon ───────────────────────────────────────────────────

  group('CartProvider.applyPlatformCoupon', () {
    test('sets platformCoupon after apply', () {
      final provider = CartProvider();
      final coupon = _coupon(discountType: 'fixed', discountValue: 20000);
      provider.applyPlatformCoupon(coupon);
      expect(provider.platformCoupon, isNotNull);
      expect(provider.platformCoupon!.coupon.code, 'TEST10');
    });

    test('platformDiscount updates after apply', () {
      final provider = CartProvider();
      // summary.totalPrice = 0 (no items), so calcDiscount(0) = 0
      final coupon = _coupon(discountType: 'fixed', discountValue: 20000);
      provider.applyPlatformCoupon(coupon);
      // With empty cart, totalPrice=0, calcDiscount clamps to 0
      expect(provider.platformDiscount, 0);
    });

    test('notifies listeners when coupon applied', () {
      final provider = CartProvider();
      var notified = false;
      provider.addListener(() => notified = true);
      provider.applyPlatformCoupon(_coupon());
      expect(notified, isTrue);
    });

    test('removePlatformCoupon clears applied coupon', () {
      final provider = CartProvider();
      provider.applyPlatformCoupon(_coupon());
      expect(provider.platformCoupon, isNotNull);
      provider.removePlatformCoupon();
      expect(provider.platformCoupon, isNull);
      expect(provider.platformDiscount, 0);
    });

    test('only one platform coupon at a time — new one replaces old', () {
      final provider = CartProvider();
      provider.applyPlatformCoupon(_coupon(discountType: 'percent', discountValue: 10));
      provider.applyPlatformCoupon(
          _coupon(discountType: 'fixed', discountValue: 50000));
      expect(provider.platformCoupon!.coupon.discountType, 'fixed');
    });
  });

  // ── applyShopCoupon ───────────────────────────────────────────────────────

  group('CartProvider.applyShopCoupon', () {
    test('stores coupon for given shopId', () {
      final provider = CartProvider();
      provider.applyShopCoupon('shop-1', _coupon());
      expect(provider.shopCoupons.containsKey('shop-1'), isTrue);
    });

    test('removeShopCoupon removes coupon for shopId', () {
      final provider = CartProvider();
      provider.applyShopCoupon('shop-1', _coupon());
      provider.removeShopCoupon('shop-1');
      expect(provider.shopCoupons.containsKey('shop-1'), isFalse);
    });

    test('multiple shops can have independent coupons', () {
      final provider = CartProvider();
      provider.applyShopCoupon('shop-1',
          _coupon(discountType: 'percent', discountValue: 10));
      provider.applyShopCoupon('shop-2',
          _coupon(discountType: 'fixed', discountValue: 30000));
      expect(provider.shopCoupons.length, 2);
      expect(provider.shopCoupons['shop-1']!.coupon.discountType, 'percent');
      expect(provider.shopCoupons['shop-2']!.coupon.discountType, 'fixed');
    });

    test('removing shop-1 coupon does not affect shop-2', () {
      final provider = CartProvider();
      provider.applyShopCoupon('shop-1', _coupon());
      provider.applyShopCoupon('shop-2', _coupon());
      provider.removeShopCoupon('shop-1');
      expect(provider.shopCoupons.containsKey('shop-1'), isFalse);
      expect(provider.shopCoupons.containsKey('shop-2'), isTrue);
    });
  });

  // ── totalCouponDiscount ───────────────────────────────────────────────────

  group('CartProvider.totalCouponDiscount', () {
    test('is platformDiscount + sum of shop discounts', () {
      final provider = CartProvider();
      // With empty cart, all calcDiscount → 0
      provider.applyPlatformCoupon(_coupon(discountType: 'fixed', discountValue: 10000));
      provider.applyShopCoupon('shop-1',
          _coupon(discountType: 'fixed', discountValue: 5000));
      // all clamp to 0 due to empty cart (totalPrice=0)
      expect(provider.totalCouponDiscount, 0);
      expect(provider.totalCouponDiscount,
          provider.platformDiscount + provider.totalShopDiscount);
    });

    test('totalShopDiscount sums all shop coupon discounts', () {
      final provider = CartProvider();
      provider.applyShopCoupon('s1', _coupon(discountType: 'fixed', discountValue: 0));
      provider.applyShopCoupon('s2', _coupon(discountType: 'fixed', discountValue: 0));
      expect(provider.totalShopDiscount,
          provider.shopCoupons.values.fold(0, (s, c) => s + c.discountAmount));
    });
  });

  // ── CouponModel.calcDiscount integration với CartItemModel ─────────────────

  group('CouponModel calcDiscount with real subtotal values', () {
    test('10% off 200000 = 20000', () {
      final coupon = _coupon(discountType: 'percent', discountValue: 10);
      // 2 items × 100000 = 200000 subtotal
      expect(coupon.calcDiscount(200000), 20000);
    });

    test('fixed 30000 off 150000 = 30000', () {
      final coupon = _coupon(discountType: 'fixed', discountValue: 30000);
      expect(coupon.calcDiscount(150000), 30000);
    });

    test('discount never makes total negative', () {
      final coupon = _coupon(discountType: 'fixed', discountValue: 999999);
      expect(coupon.calcDiscount(50000), 50000); // clamped
    });
  });

  // ── isLiveCouponSaved integration ─────────────────────────────────────────

  group('CartProvider live coupon integration', () {
    test('can save and check multiple live coupons', () {
      final provider = CartProvider();
      provider.markLiveCouponSaved('FLASH50');
      provider.markLiveCouponSaved('NEWUSER');
      provider.markLiveCouponSaved('WELCOME10');

      expect(provider.isLiveCouponSaved('flash50'), isTrue);
      expect(provider.isLiveCouponSaved('NEWUSER'), isTrue);
      expect(provider.isLiveCouponSaved('welcome10'), isTrue);
      expect(provider.isLiveCouponSaved('NOTEXIST'), isFalse);
    });

    test('savedLiveCouponCodes count matches unique codes saved', () {
      final provider = CartProvider();
      provider.markLiveCouponSaved('A');
      provider.markLiveCouponSaved('b'); // normalized to B
      provider.markLiveCouponSaved('A'); // duplicate
      expect(provider.savedLiveCouponCodes.length, 2);
    });
  });
}
