import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/cart/providers/cart_provider.dart';

void main() {
  late CartProvider provider;

  setUp(() {
    provider = CartProvider();
  });

  tearDown(() {
    provider.dispose();
  });

  // ── Initial state ─────────────────────────────────────────────────────────

  group('CartProvider — initial state', () {
    test('isEmpty is true', () {
      expect(provider.isEmpty, isTrue);
    });

    test('totalCount is 0', () {
      expect(provider.totalCount, 0);
    });

    test('status is CartStatus.idle', () {
      expect(provider.status, CartStatus.idle);
    });

    test('platformCoupon is null', () {
      expect(provider.platformCoupon, isNull);
    });

    test('platformDiscount is 0', () {
      expect(provider.platformDiscount, 0);
    });

    test('totalCouponDiscount is 0', () {
      expect(provider.totalCouponDiscount, 0);
    });

    test('shopCoupons is empty', () {
      expect(provider.shopCoupons, isEmpty);
    });

    test('allSelected is false when no items', () {
      // allSelected requires items.isNotEmpty — empty cart always false
      expect(provider.allSelected, isFalse);
    });

    test('savedLiveCouponCodes is empty', () {
      expect(provider.savedLiveCouponCodes, isEmpty);
    });

    test('items list is empty', () {
      expect(provider.items, isEmpty);
    });

    test('itemsByShop is empty map', () {
      expect(provider.itemsByShop, isEmpty);
    });
  });

  // ── markLiveCouponSaved / isLiveCouponSaved ───────────────────────────────

  group('CartProvider — live coupon tracking', () {
    test('isLiveCouponSaved returns false for unknown code', () {
      expect(provider.isLiveCouponSaved('TROPIA10'), isFalse);
    });

    test('isLiveCouponSaved returns true after marking', () {
      provider.markLiveCouponSaved('TROPIA10');
      expect(provider.isLiveCouponSaved('TROPIA10'), isTrue);
    });

    test('lookup is case-insensitive — saved lowercase, found uppercase', () {
      provider.markLiveCouponSaved('sale20');
      expect(provider.isLiveCouponSaved('SALE20'), isTrue);
    });

    test('lookup is case-insensitive — saved uppercase, found lowercase', () {
      provider.markLiveCouponSaved('FRESH50');
      expect(provider.isLiveCouponSaved('fresh50'), isTrue);
    });

    test('saved code is stored as uppercase internally', () {
      provider.markLiveCouponSaved('lowercase');
      expect(provider.savedLiveCouponCodes.contains('LOWERCASE'), isTrue);
    });

    test('marking same code twice does not duplicate', () {
      provider.markLiveCouponSaved('DEAL');
      provider.markLiveCouponSaved('DEAL');
      expect(provider.savedLiveCouponCodes.length, 1);
    });

    test('multiple distinct codes are all tracked', () {
      provider.markLiveCouponSaved('CODE1');
      provider.markLiveCouponSaved('CODE2');
      provider.markLiveCouponSaved('CODE3');
      expect(provider.savedLiveCouponCodes.length, 3);
      expect(provider.isLiveCouponSaved('CODE1'), isTrue);
      expect(provider.isLiveCouponSaved('CODE2'), isTrue);
      expect(provider.isLiveCouponSaved('CODE3'), isTrue);
    });

    test('savedLiveCouponCodes set is unmodifiable', () {
      provider.markLiveCouponSaved('ABC');
      expect(
        () => provider.savedLiveCouponCodes.add('XYZ'),
        throwsUnsupportedError,
      );
    });
  });

  // ── removePlatformCoupon ──────────────────────────────────────────────────

  group('CartProvider — removePlatformCoupon', () {
    test('safe to call when platformCoupon is already null', () {
      expect(() => provider.removePlatformCoupon(), returnsNormally);
      expect(provider.platformCoupon, isNull);
    });

    test('platformDiscount remains 0 after removing null coupon', () {
      provider.removePlatformCoupon();
      expect(provider.platformDiscount, 0);
    });

    test('totalCouponDiscount remains 0 after removing null coupon', () {
      provider.removePlatformCoupon();
      expect(provider.totalCouponDiscount, 0);
    });

    test('notifies listeners on removePlatformCoupon', () {
      var notified = false;
      provider.addListener(() => notified = true);
      provider.removePlatformCoupon();
      expect(notified, isTrue);
    });
  });

  // ── removeShopCoupon ──────────────────────────────────────────────────────

  group('CartProvider — removeShopCoupon', () {
    test('safe to call for a shopId with no coupon applied', () {
      expect(() => provider.removeShopCoupon('shop-001'), returnsNormally);
    });

    test('shopCoupons stays empty after removing non-existent shop coupon', () {
      provider.removeShopCoupon('shop-001');
      expect(provider.shopCoupons, isEmpty);
    });

    test('notifies listeners on removeShopCoupon', () {
      var notified = false;
      provider.addListener(() => notified = true);
      provider.removeShopCoupon('shop-001');
      expect(notified, isTrue);
    });
  });

  // ── summary getter consistency ────────────────────────────────────────────

  group('CartProvider — summary getter', () {
    test('summary.totalItems starts at 0', () {
      expect(provider.summary.totalItems, 0);
    });

    test('summary.totalPrice starts at 0', () {
      expect(provider.summary.totalPrice, 0);
    });

    test('summary.totalSaving starts at 0', () {
      expect(provider.summary.totalSaving, 0);
    });
  });
}
