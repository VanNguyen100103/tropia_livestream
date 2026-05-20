// Regression tests: checkout flow
//
// Bảo vệ các bug đã biết:
//   1. grandTotal âm khi discount > subtotal
//   2. discountPercent sai khi originalPrice = 0
//   3. CouponModel.calcDiscount không clamp đúng
//   4. CartProvider totalCouponDiscount = platformDiscount + shopDiscount
//   5. CartItemModel.attributeLabel với edge cases
//   6. OrderModel.fromJson fallback fields
//   7. UserRole mapping từ string

import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/cart/models/cart_item_model.dart';
import 'package:tropia/features/cart/providers/cart_provider.dart';
import 'package:tropia/features/coupon/data/coupon_repository.dart';
import 'package:tropia/features/order/models/order_model.dart';
import 'package:tropia/features/user/models/user_model.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

CartItemModel _item({
  int unitPrice = 100000,
  int originalPrice = 120000,
  int quantity = 1,
  bool isSelected = true,
  String shopId = 'shop-1',
}) =>
    CartItemModel(
      id: 'i-${unitPrice}x${quantity}',
      variantId: 'v-1',
      productId: 'p-1',
      productName: 'Test',
      shopId: shopId,
      shopName: 'Shop',
      unitPrice: unitPrice,
      originalPrice: originalPrice,
      quantity: quantity,
      attributes: [],
      isSelected: isSelected,
    );

CouponModel _percentCoupon(double pct, {double? max}) => CouponModel(
      id: 'c-pct',
      code: 'PCT',
      discountType: 'percent',
      discountValue: pct,
      minOrderValue: 0,
      maxDiscount: max,
      expiresAt: DateTime(2099),
    );

CouponModel _fixedCoupon(double amount) => CouponModel(
      id: 'c-fix',
      code: 'FIX',
      discountType: 'fixed',
      discountValue: amount,
      minOrderValue: 0,
      expiresAt: DateTime(2099),
    );

void main() {
  // ── Regression 1: grandTotal không bao giờ âm ─────────────────────────────

  group('Regression: discount không làm grandTotal âm', () {
    test('CouponModel.calcDiscount clamps to orderTotal', () {
      final coupon = _fixedCoupon(999999);
      // 999999 discount trên đơn 50000 → phải clamp về 50000
      expect(coupon.calcDiscount(50000), 50000);
      // Không bao giờ trả về > orderTotal
      expect(coupon.calcDiscount(50000), lessThanOrEqualTo(50000));
    });

    test('100% percent coupon clamps to exact orderTotal', () {
      final coupon = _percentCoupon(100);
      expect(coupon.calcDiscount(200000), 200000);
    });

    test('calcDiscount always >= 0', () {
      final coupon = _fixedCoupon(999999);
      expect(coupon.calcDiscount(0), 0);
    });

    test('percent coupon on 0 orderTotal returns 0', () {
      expect(_percentCoupon(50).calcDiscount(0), 0);
    });
  });

  // ── Regression 2: discountPercent khi originalPrice = 0 ──────────────────

  group('Regression: discountPercent với originalPrice = 0', () {
    test('returns 0, not throws, when originalPrice is 0', () {
      final item = _item(unitPrice: 0, originalPrice: 0);
      expect(() => item.discountPercent, returnsNormally);
      expect(item.discountPercent, 0);
    });

    test('no discount when unitPrice equals originalPrice', () {
      final item = _item(unitPrice: 50000, originalPrice: 50000);
      expect(item.discountPercent, 0);
      expect(item.hasDiscount, isFalse);
      expect(item.saving, 0);
    });
  });

  // ── Regression 3: subtotal computation ────────────────────────────────────

  group('Regression: subtotal tính đúng cho mọi quantity', () {
    test('subtotal = unitPrice × quantity', () {
      expect(_item(unitPrice: 85000, quantity: 3).subtotal, 255000);
    });

    test('subtotal = 0 when quantity = 0', () {
      expect(_item(unitPrice: 85000, quantity: 0).subtotal, 0);
    });

    test('saving = 0 when originalPrice = unitPrice regardless of quantity', () {
      expect(_item(unitPrice: 50000, originalPrice: 50000, quantity: 10).saving, 0);
    });
  });

  // ── Regression 4: totalCouponDiscount = platform + shop ──────────────────

  group('Regression: totalCouponDiscount = platformDiscount + shopDiscount', () {
    test('with no coupons, all totals are 0', () {
      final provider = CartProvider();
      expect(provider.platformDiscount, 0);
      expect(provider.totalShopDiscount, 0);
      expect(provider.totalCouponDiscount, 0);
    });

    test('applying then removing platform coupon resets to 0', () {
      final provider = CartProvider();
      provider.applyPlatformCoupon(_percentCoupon(10));
      provider.removePlatformCoupon();
      expect(provider.platformDiscount, 0);
      expect(provider.totalCouponDiscount, provider.totalShopDiscount);
    });

    test('totalCouponDiscount always equals platform + shop sum', () {
      final provider = CartProvider();
      provider.applyPlatformCoupon(_percentCoupon(10));
      provider.applyShopCoupon('s1', _fixedCoupon(0));
      expect(
        provider.totalCouponDiscount,
        provider.platformDiscount + provider.totalShopDiscount,
      );
    });
  });

  // ── Regression 5: attributeLabel edge cases ───────────────────────────────

  group('Regression: attributeLabel edge cases', () {
    test('empty attributes → empty string (not null)', () {
      expect(_item().attributeLabel, isNotNull);
      expect(_item().attributeLabel, '');
    });

    test('single attribute has no separator', () {
      final item = CartItemModel(
        id: 'x',
        variantId: 'v',
        productId: 'p',
        productName: 'X',
        shopId: 's',
        shopName: 'S',
        unitPrice: 1,
        originalPrice: 1,
        quantity: 1,
        attributes: [const CartAttribute(typeName: 'Size', value: 'L')],
      );
      expect(item.attributeLabel, 'L');
      expect(item.attributeLabel.contains(' · '), isFalse);
    });

    test('three attributes joined correctly', () {
      final item = CartItemModel(
        id: 'x2',
        variantId: 'v',
        productId: 'p',
        productName: 'X',
        shopId: 's',
        shopName: 'S',
        unitPrice: 1,
        originalPrice: 1,
        quantity: 1,
        attributes: [
          const CartAttribute(typeName: 'Màu', value: 'Đỏ'),
          const CartAttribute(typeName: 'Size', value: 'M'),
          const CartAttribute(typeName: 'KL', value: '500g'),
        ],
      );
      expect(item.attributeLabel, 'Đỏ · M · 500g');
    });
  });

  // ── Regression 6: OrderModel fallback fields ──────────────────────────────

  group('Regression: OrderModel.fromJson fallback fields', () {
    test('final_price falls back to total_price when absent', () {
      final o = OrderModel.fromJson({
        'id': 'o1',
        'quantity': 1,
        'unit_price': 100000,
        'total_price': 100000,
        'status': 'pending',
        'buyer_name': 'A',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(o.finalPrice, o.totalPrice);
    });

    test('discount_amount defaults to 0', () {
      final o = OrderModel.fromJson({
        'id': 'o2',
        'quantity': 1,
        'unit_price': 100000,
        'total_price': 100000,
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(o.discountAmount, 0);
    });

    test('status "pending" makes isPending = true', () {
      final o = OrderModel.fromJson({
        'id': 'o3',
        'quantity': 1,
        'unit_price': 100000,
        'total_price': 100000,
        'status': 'pending',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(o.isPending, isTrue);
      expect(o.isPaid, isFalse);
      expect(o.isCancelled, isFalse);
    });

    test('status "paid" makes isPaid = true', () {
      final o = OrderModel.fromJson({
        'id': 'o4',
        'quantity': 1,
        'unit_price': 100000,
        'total_price': 100000,
        'status': 'paid',
        'created_at': '2026-01-01T00:00:00.000Z',
      });
      expect(o.isPaid, isTrue);
      expect(o.isPending, isFalse);
    });
  });

  // ── Regression 7: UserRole mapping ────────────────────────────────────────

  group('Regression: UserRole mapping không sai', () {
    test('buyer cannot host live', () {
      expect(UserRole.buyer.canHostLive, isFalse);
    });

    test('seller can host live', () {
      expect(UserRole.seller.canHostLive, isTrue);
    });

    test('fromJson role=null → buyer (không throw)', () {
      final user = UserModel.fromJson({
        'id': 'u1',
        'email': 'x@x.com',
      });
      expect(user.role, UserRole.buyer);
      expect(user.role.canHostLive, isFalse);
    });

    test('fromJson role="seller" → seller.canHostLive = true', () {
      final user = UserModel.fromJson({
        'id': 'u2',
        'name': 'Seller',
        'email': 'seller@tropia.vn',
        'role': 'seller',
      });
      expect(user.role.canHostLive, isTrue);
    });
  });

  // ── Regression 8: CartProvider live coupon case-insensitivity ─────────────

  group('Regression: live coupon lookup không phân biệt hoa thường', () {
    test('saved lowercase → found uppercase', () {
      final provider = CartProvider();
      provider.markLiveCouponSaved('sale20');
      expect(provider.isLiveCouponSaved('SALE20'), isTrue);
    });

    test('saved mixed-case → found any case', () {
      final provider = CartProvider();
      provider.markLiveCouponSaved('WeLcOmE10');
      expect(provider.isLiveCouponSaved('welcome10'), isTrue);
      expect(provider.isLiveCouponSaved('WELCOME10'), isTrue);
    });

    test('duplicate marks do not grow set', () {
      final provider = CartProvider();
      for (var i = 0; i < 10; i++) {
        provider.markLiveCouponSaved('SAME');
      }
      expect(provider.savedLiveCouponCodes.length, 1);
    });
  });

  // ── Regression 9: CartSummary fromJson numeric types ─────────────────────

  group('Regression: CartSummary.fromJson với kiểu số khác nhau', () {
    test('parses int values', () {
      final s = CartSummary.fromJson({'totalItems': 2, 'totalPrice': 100000, 'totalSaving': 0});
      expect(s.totalPrice, 100000);
    });

    test('parses double values (server trả double)', () {
      final s = CartSummary.fromJson(
          {'totalItems': 3.0, 'totalPrice': 150000.0, 'totalSaving': 5000.0});
      expect(s.totalItems, 3);
      expect(s.totalPrice, 150000);
    });
  });

  // ── Regression 10: maxDiscount cap ───────────────────────────────────────

  group('Regression: maxDiscount cap hoạt động đúng', () {
    test('percent with maxDiscount cap applied', () {
      // 20% of 500000 = 100000, maxDiscount=75000 → result=75000
      final coupon = _percentCoupon(20, max: 75000);
      expect(coupon.calcDiscount(500000), 75000);
    });

    test('percent without maxDiscount — full discount applied', () {
      final coupon = _percentCoupon(15);
      expect(coupon.calcDiscount(200000), 30000);
    });

    test('fixed with maxDiscount cap', () {
      // fixed 100000, maxDiscount 60000 → result=60000
      final coupon = CouponModel(
        id: 'c',
        code: 'C',
        discountType: 'fixed',
        discountValue: 100000,
        minOrderValue: 0,
        maxDiscount: 60000,
        expiresAt: DateTime(2099),
      );
      expect(coupon.calcDiscount(300000), 60000);
    });
  });
}
