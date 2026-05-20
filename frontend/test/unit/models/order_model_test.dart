import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/order/models/order_model.dart';

// ── Helper ────────────────────────────────────────────────────────────────────

Map<String, dynamic> _baseJson() => {
      'id': 'order-001',
      'session_id': 'sess-001',
      'product_id': 'prod-001',
      'product_name': 'Gạo ST25 1kg',
      'quantity': 2,
      'unit_price': 85000,
      'total_price': 170000,
      'final_price': 150000,
      'discount_amount': 20000,
      'status': 'pending',
      'buyer_name': 'Ngân Văn',
      'created_at': '2026-05-15T10:30:00.000Z',
    };

void main() {
  // ── Status getters ────────────────────────────────────────────────────────

  group('OrderModel.isPending', () {
    test('true when status is "pending"', () {
      expect(OrderModel.fromJson(_baseJson()).isPending, isTrue);
    });

    test('false when status is "paid"', () {
      expect(OrderModel.fromJson({..._baseJson(), 'status': 'paid'}).isPending, isFalse);
    });

    test('false when status is "cancelled"', () {
      expect(
          OrderModel.fromJson({..._baseJson(), 'status': 'cancelled'}).isPending, isFalse);
    });
  });

  group('OrderModel.isPaid', () {
    test('true when status is "paid"', () {
      expect(
          OrderModel.fromJson({..._baseJson(), 'status': 'paid'}).isPaid, isTrue);
    });

    test('false when status is "pending"', () {
      expect(OrderModel.fromJson(_baseJson()).isPaid, isFalse);
    });

    test('false when status is "cancelled"', () {
      expect(
          OrderModel.fromJson({..._baseJson(), 'status': 'cancelled'}).isPaid, isFalse);
    });
  });

  group('OrderModel.isCancelled', () {
    test('true when status is "cancelled"', () {
      expect(
          OrderModel.fromJson({..._baseJson(), 'status': 'cancelled'}).isCancelled,
          isTrue);
    });

    test('false when status is "pending"', () {
      expect(OrderModel.fromJson(_baseJson()).isCancelled, isFalse);
    });

    test('false when status is "paid"', () {
      expect(
          OrderModel.fromJson({..._baseJson(), 'status': 'paid'}).isCancelled, isFalse);
    });
  });

  // ── fromJson ──────────────────────────────────────────────────────────────

  group('OrderModel.fromJson', () {
    test('parses all required fields', () {
      final o = OrderModel.fromJson(_baseJson());
      expect(o.id, 'order-001');
      expect(o.sessionId, 'sess-001');
      expect(o.productId, 'prod-001');
      expect(o.productName, 'Gạo ST25 1kg');
      expect(o.quantity, 2);
      expect(o.unitPrice, 85000);
      expect(o.totalPrice, 170000);
      expect(o.finalPrice, 150000);
      expect(o.discountAmount, 20000);
      expect(o.status, 'pending');
      expect(o.buyerName, 'Ngân Văn');
    });

    test('parses createdAt as DateTime', () {
      final o = OrderModel.fromJson(_baseJson());
      expect(o.createdAt, isA<DateTime>());
      expect(o.createdAt.year, 2026);
      expect(o.createdAt.month, 5);
      expect(o.createdAt.day, 15);
    });

    test('falls back to total_price when final_price is absent', () {
      final json = _baseJson()..remove('final_price');
      expect(OrderModel.fromJson(json).finalPrice, 170000);
    });

    test('discountAmount defaults to 0 when absent', () {
      final json = _baseJson()..remove('discount_amount');
      expect(OrderModel.fromJson(json).discountAmount, 0);
    });

    test('status defaults to "pending" when absent', () {
      final json = _baseJson()..remove('status');
      final o = OrderModel.fromJson(json);
      expect(o.status, 'pending');
      expect(o.isPending, isTrue);
    });

    test('sessionId defaults to empty string when absent', () {
      final json = _baseJson()..remove('session_id');
      expect(OrderModel.fromJson(json).sessionId, '');
    });

    test('productId defaults to empty string when absent', () {
      final json = _baseJson()..remove('product_id');
      expect(OrderModel.fromJson(json).productId, '');
    });

    test('productThumbnail is null when absent', () {
      expect(OrderModel.fromJson(_baseJson()).productThumbnail, isNull);
    });

    test('parses productThumbnail when present', () {
      final o = OrderModel.fromJson(
          {..._baseJson(), 'product_thumbnail': 'https://cdn.tropia.vn/rice.jpg'});
      expect(o.productThumbnail, 'https://cdn.tropia.vn/rice.jpg');
    });

    test('couponCode is null when absent', () {
      expect(OrderModel.fromJson(_baseJson()).couponCode, isNull);
    });

    test('parses couponCode when present', () {
      final o = OrderModel.fromJson({..._baseJson(), 'coupon_code': 'SALE20'});
      expect(o.couponCode, 'SALE20');
    });

    test('buyerName defaults to empty string when absent', () {
      final json = _baseJson()..remove('buyer_name');
      expect(OrderModel.fromJson(json).buyerName, '');
    });
  });
}
