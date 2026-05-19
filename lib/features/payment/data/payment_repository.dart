import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';

const _tag = 'PaymentRepository';

class PaymentRepository {
  PaymentRepository._();
  static final instance = PaymentRepository._();

  get _dio => AuthService.instance.authorizedDio();

  // ── MoMo ──────────────────────────────────────────────────────────────────

  /// POST /api/payment/momo  → trả về { payUrl }
  Future<String> initMomo({required String orderId, required int amount}) async {
    final res = await _dio.post('/api/payment/momo', data: {
      'orderId': orderId,
      'amount':  amount,
    });
    final payUrl = res.data['payUrl'] as String;
    AppLogger.logInfo(_tag, 'MoMo payUrl: $payUrl');
    return payUrl;
  }

  /// POST /api/payment/momo/check
  Future<Map<String, dynamic>> checkMomo(String orderId) async {
    final res = await _dio.post('/api/payment/momo/check', data: {'orderId': orderId});
    return res.data as Map<String, dynamic>;
  }

  // ── ZaloPay ───────────────────────────────────────────────────────────────

  /// POST /api/payment/zalopay  → trả về { orderUrl }
  Future<String> initZalopay({required String orderId, required int amount}) async {
    final res = await _dio.post('/api/payment/zalopay', data: {
      'orderId': orderId,
      'amount':  amount,
    });
    final orderUrl = res.data['orderUrl'] as String;
    AppLogger.logInfo(_tag, 'ZaloPay orderUrl: $orderUrl');
    return orderUrl;
  }

  /// POST /api/payment/zalopay/check
  Future<Map<String, dynamic>> checkZalopay(String appTransId) async {
    final res = await _dio.post('/api/payment/zalopay/check', data: {'appTransId': appTransId});
    return res.data as Map<String, dynamic>;
  }

  // ── VNPay ─────────────────────────────────────────────────────────────────

  /// POST /api/payment/vnpay  → trả về { payUrl }
  Future<String> initVnpay({required String orderId, required int amount}) async {
    final res = await _dio.post('/api/payment/vnpay', data: {
      'orderId': orderId,
      'amount':  amount,
    });
    final payUrl = res.data['payUrl'] as String;
    AppLogger.logInfo(_tag, 'VNPay payUrl: $payUrl');
    return payUrl;
  }
}
