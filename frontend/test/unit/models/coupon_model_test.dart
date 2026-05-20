import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/coupon/data/coupon_repository.dart';

// ── Helper ────────────────────────────────────────────────────────────────────

CouponModel _makeCoupon({
  String discountType = 'percent',
  double discountValue = 20,
  int minOrderValue = 0,
  double? maxDiscount,
}) =>
    CouponModel(
      id: 'c-1',
      code: 'SALE20',
      discountType: discountType,
      discountValue: discountValue,
      minOrderValue: minOrderValue,
      maxDiscount: maxDiscount,
      expiresAt: DateTime(2099, 12, 31),
    );

void main() {
  // ── calcDiscount — percent ────────────────────────────────────────────────

  group('CouponModel.calcDiscount — percent', () {
    test('20% off 100000 = 20000', () {
      expect(_makeCoupon(discountType: 'percent', discountValue: 20).calcDiscount(100000), 20000);
    });

    test('10% off 208000 = 20800', () {
      expect(_makeCoupon(discountType: 'percent', discountValue: 10).calcDiscount(208000), 20800);
    });

    test('caps at maxDiscount when computed > cap', () {
      final coupon = _makeCoupon(
          discountType: 'percent', discountValue: 50, maxDiscount: 30000);
      // 50% of 100000 = 50000 → capped at 30000
      expect(coupon.calcDiscount(100000), 30000);
    });

    test('does not cap when computed < maxDiscount', () {
      final coupon = _makeCoupon(
          discountType: 'percent', discountValue: 10, maxDiscount: 50000);
      // 10% of 100000 = 10000 < 50000
      expect(coupon.calcDiscount(100000), 10000);
    });

    test('returns 0 for zero orderTotal', () {
      expect(_makeCoupon(discountType: 'percent', discountValue: 20).calcDiscount(0), 0);
    });

    test('clamps 100% discount to orderTotal (cannot exceed order)', () {
      expect(_makeCoupon(discountType: 'percent', discountValue: 100).calcDiscount(50000), 50000);
    });

    test('result is never negative', () {
      final result = _makeCoupon(discountType: 'percent', discountValue: 20).calcDiscount(0);
      expect(result, greaterThanOrEqualTo(0));
    });
  });

  // ── calcDiscount — fixed ──────────────────────────────────────────────────

  group('CouponModel.calcDiscount — fixed', () {
    test('50000 off 200000 = 50000', () {
      expect(
          _makeCoupon(discountType: 'fixed', discountValue: 50000).calcDiscount(200000), 50000);
    });

    test('clamps to orderTotal when fixed > order', () {
      expect(
          _makeCoupon(discountType: 'fixed', discountValue: 200000).calcDiscount(50000), 50000);
    });

    test('respects maxDiscount cap for fixed type', () {
      final coupon = _makeCoupon(
          discountType: 'fixed', discountValue: 80000, maxDiscount: 60000);
      expect(coupon.calcDiscount(200000), 60000);
    });

    test('returns 0 for zero orderTotal', () {
      expect(
          _makeCoupon(discountType: 'fixed', discountValue: 50000).calcDiscount(0), 0);
    });

    test('result is never negative', () {
      final result =
          _makeCoupon(discountType: 'fixed', discountValue: 50000).calcDiscount(0);
      expect(result, greaterThanOrEqualTo(0));
    });
  });

  // ── discountLabel ─────────────────────────────────────────────────────────

  group('CouponModel.discountLabel', () {
    test('percent label: "Giảm 20%"', () {
      expect(
          _makeCoupon(discountType: 'percent', discountValue: 20).discountLabel, 'Giảm 20%');
    });

    test('percent label: "Giảm 50%"', () {
      expect(
          _makeCoupon(discountType: 'percent', discountValue: 50).discountLabel, 'Giảm 50%');
    });

    test('fixed label starts with "Giảm"', () {
      expect(_makeCoupon(discountType: 'fixed', discountValue: 50000).discountLabel,
          startsWith('Giảm'));
    });

    test('fixed label contains "đ" suffix', () {
      expect(_makeCoupon(discountType: 'fixed', discountValue: 50000).discountLabel,
          contains('đ'));
    });
  });

  // ── CouponModel.fromJson ──────────────────────────────────────────────────

  group('CouponModel.fromJson', () {
    final baseJson = {
      'id': 'c-json',
      'code': 'FRESH15',
      'discount_type': 'percent',
      'discount_value': 15,
      'min_order_value': 100000,
      'max_discount': 75000.0,
      'expires_at': '2099-12-31T00:00:00.000Z',
    };

    test('parses all fields', () {
      final c = CouponModel.fromJson(baseJson);
      expect(c.id, 'c-json');
      expect(c.code, 'FRESH15');
      expect(c.discountType, 'percent');
      expect(c.discountValue, 15.0);
      expect(c.minOrderValue, 100000);
      expect(c.maxDiscount, 75000.0);
      expect(c.expiresAt.year, 2099);
    });

    test('minOrderValue defaults to 0 when absent', () {
      final c = CouponModel.fromJson({
        'id': 'c-2',
        'code': 'NOMIN',
        'discount_type': 'fixed',
        'discount_value': 20000,
        'expires_at': '2099-01-01T00:00:00.000Z',
      });
      expect(c.minOrderValue, 0);
    });

    test('maxDiscount is null when absent', () {
      final c = CouponModel.fromJson({
        'id': 'c-3',
        'code': 'NOMAX',
        'discount_type': 'percent',
        'discount_value': 5,
        'expires_at': '2099-01-01T00:00:00.000Z',
      });
      expect(c.maxDiscount, isNull);
    });

    test('parses discount_value from int json to double', () {
      final c = CouponModel.fromJson({...baseJson, 'discount_value': 25});
      expect(c.discountValue, 25.0);
    });

    test('fixed coupon calcDiscount works after fromJson', () {
      final c = CouponModel.fromJson({
        'id': 'c-4',
        'code': 'GIAM30K',
        'discount_type': 'fixed',
        'discount_value': 30000,
        'expires_at': '2099-01-01T00:00:00.000Z',
      });
      expect(c.calcDiscount(150000), 30000);
    });
  });
}
