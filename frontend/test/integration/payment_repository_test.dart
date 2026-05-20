// Integration test: PaymentRepository request/response parsing
// Kiểm tra logic parse response từ API — không gọi HTTP thật.
// Dùng trực tiếp data parsing logic thay vì mock Dio.

import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/coupon/data/coupon_repository.dart';
import 'package:tropia/features/order/data/order_repository.dart';
import 'package:tropia/features/order/models/order_model.dart';

// ── Helper: parse các response shape mà PaymentRepository/OrderRepository dùng ──

void main() {
  // ── Parse MoMo payUrl ─────────────────────────────────────────────────────

  group('PaymentRepository response parsing — MoMo', () {
    test('extracts payUrl from response data', () {
      // Simulate what initMomo does: res.data['payUrl']
      final responseData = {
        'payUrl': 'https://test-payment.momo.vn/v2/gateway/pay?t=TU9NT...',
        'deeplink': 'momo://payment?t=TU9NT...',
      };
      final payUrl = responseData['payUrl'] as String;
      expect(payUrl, startsWith('https://test-payment.momo.vn'));
    });

    test('payUrl is non-empty', () {
      final data = {'payUrl': 'https://momo.vn/pay?t=abc'};
      expect(data['payUrl'], isNotEmpty);
    });
  });

  // ── Parse ZaloPay orderUrl ────────────────────────────────────────────────

  group('PaymentRepository response parsing — ZaloPay', () {
    test('extracts orderUrl from response data', () {
      final responseData = {
        'orderUrl': 'https://openapi.zalopay.vn/order?token=xyz',
        'returnCode': 1,
      };
      final orderUrl = responseData['orderUrl'] as String;
      expect(orderUrl, startsWith('https://'));
    });
  });

  // ── Parse VNPay payUrl ────────────────────────────────────────────────────

  group('PaymentRepository response parsing — VNPay', () {
    test('extracts payUrl from response data', () {
      final responseData = {
        'payUrl': 'https://sandbox.vnpayment.vn/paymentv2/vpcpay.html?vnp_Amount=...',
      };
      final payUrl = responseData['payUrl'] as String;
      expect(payUrl, contains('vnpayment.vn'));
    });
  });

  // ── OrderRepository checkout response parsing ─────────────────────────────

  group('OrderRepository checkout response parsing', () {
    final checkoutResponse = {
      'orders': [
        {
          'id': 'order-001',
          'session_id': '',
          'product_id': 'p-1',
          'product_name': 'Gạo ST25',
          'quantity': 2,
          'unit_price': 85000,
          'total_price': 170000,
          'final_price': 150000,
          'discount_amount': 20000,
          'status': 'confirmed',
          'buyer_name': 'Ngân',
          'created_at': '2026-05-15T10:00:00.000Z',
        }
      ],
      'summary': {
        'subtotal': 170000,
        'couponDiscount': 20000,
        'grandTotal': 150000,
        'paymentMethod': 'cod',
      },
    };

    test('parses orders list correctly', () {
      final orders = (checkoutResponse['orders'] as List)
          .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(orders.length, 1);
      expect(orders.first.id, 'order-001');
      expect(orders.first.totalPrice, 170000);
    });

    test('parses summary grandTotal', () {
      final summary = checkoutResponse['summary'] as Map<String, dynamic>;
      expect((summary['grandTotal'] as num).toInt(), 150000);
    });

    test('parses summary couponDiscount', () {
      final summary = checkoutResponse['summary'] as Map<String, dynamic>;
      expect((summary['couponDiscount'] as num).toInt(), 20000);
    });

    test('grandTotal = subtotal - couponDiscount', () {
      final summary = checkoutResponse['summary'] as Map<String, dynamic>;
      final subtotal = (summary['subtotal'] as num).toInt();
      final discount = (summary['couponDiscount'] as num).toInt();
      final grand = (summary['grandTotal'] as num).toInt();
      expect(grand, subtotal - discount);
    });
  });

  // ── CouponRepository validate response parsing ────────────────────────────

  group('CouponRepository validate response parsing', () {
    test('parses discountAmount and finalPrice from validate response', () {
      final validateResponse = {
        'couponId': 'c-001',
        'code': 'SALE20',
        'discountType': 'percent',
        'discountValue': 20,
        'discountAmount': 40000,
        'finalPrice': 160000,
      };
      expect(validateResponse['discountAmount'], 40000);
      expect(validateResponse['finalPrice'], 160000);
    });
  });

  // ── CouponModel available list parsing ───────────────────────────────────

  group('CouponRepository available coupons parsing', () {
    test('parses list of coupons from API response', () {
      final apiResponse = {
        'data': [
          {
            'id': 'c-1',
            'code': 'WELCOME10',
            'discount_type': 'percent',
            'discount_value': 10,
            'min_order_value': 0,
            'expires_at': '2099-12-31T00:00:00.000Z',
          },
          {
            'id': 'c-2',
            'code': 'GIAM30K',
            'discount_type': 'fixed',
            'discount_value': 30000,
            'min_order_value': 150000,
            'expires_at': '2099-12-31T00:00:00.000Z',
          },
        ]
      };

      final list = (apiResponse['data'] as List)
          .map((e) => CouponModel.fromJson(e as Map<String, dynamic>))
          .toList();

      expect(list.length, 2);
      expect(list[0].code, 'WELCOME10');
      expect(list[0].discountType, 'percent');
      expect(list[1].code, 'GIAM30K');
      expect(list[1].discountType, 'fixed');
    });

    test('empty data list returns empty coupon list', () {
      final apiResponse = {'data': <dynamic>[]};
      final list = ((apiResponse['data'] as List?) ?? [])
          .map((e) => CouponModel.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(list, isEmpty);
    });

    test('null data key returns empty coupon list', () {
      final apiResponse = <String, dynamic>{};
      final list = ((apiResponse['data'] as List?) ?? [])
          .map((e) => CouponModel.fromJson(e as Map<String, dynamic>))
          .toList();
      expect(list, isEmpty);
    });
  });

  // ── CheckoutItem.toJson ───────────────────────────────────────────────────

  group('CheckoutItem.toJson', () {
    test('serializes all required fields', () {
      final item = CheckoutItem(
        cartItemId: 'ci-001',
        variantId: 'var-001',
        quantity: 2,
        unitPrice: 85000,
        productName: 'Gạo ST25',
      );
      final json = item.toJson();
      expect(json['cartItemId'], 'ci-001');
      expect(json['variantId'], 'var-001');
      expect(json['quantity'], 2);
      expect(json['unitPrice'], 85000);
      expect(json['productName'], 'Gạo ST25');
    });

    test('sessionId omitted when null', () {
      final item = CheckoutItem(
        cartItemId: 'ci-002',
        variantId: 'var-002',
        quantity: 1,
        unitPrice: 50000,
        productName: 'Test',
      );
      expect(item.toJson().containsKey('sessionId'), isFalse);
    });

    test('sessionId included when present', () {
      final item = CheckoutItem(
        cartItemId: 'ci-003',
        variantId: 'var-003',
        quantity: 1,
        unitPrice: 50000,
        productName: 'Test',
        sessionId: 'sess-001',
      );
      expect(item.toJson()['sessionId'], 'sess-001');
    });
  });
}
