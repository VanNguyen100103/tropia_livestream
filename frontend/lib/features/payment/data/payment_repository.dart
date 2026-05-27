import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';

const _tag = 'PaymentRepository';

class PaymentRepository {
  PaymentRepository._();
  static final instance = PaymentRepository._();

  get _dio => AuthService.instance.authorizedDio();

  // ── MoMo ──────────────────────────────────────────────────────────────────

  /// POST /api/payment/momo  → BE trả {pay_url, deeplink, qr_code_url}
  /// `amount` BE không đọc (lấy từ order trong DB) nhưng giữ trong signature
  /// để khớp với caller.
  Future<String> initMomo({required String orderId, required int amount}) async {
    final res = await _dio.post('/api/payment/momo', data: {
      'order_id': orderId,
    });
    final payUrl = res.data['pay_url'] as String;
    AppLogger.logInfo(_tag, 'MoMo payUrl: $payUrl');
    return payUrl;
  }

  // ── ZaloPay ───────────────────────────────────────────────────────────────

  /// POST /api/payment/zalopay  → BE trả {order_url, zp_trans_token, app_trans_id}
  Future<String> initZalopay({required String orderId, required int amount}) async {
    final res = await _dio.post('/api/payment/zalopay', data: {
      'order_id': orderId,
    });
    final orderUrl = res.data['order_url'] as String;
    AppLogger.logInfo(_tag, 'ZaloPay orderUrl: $orderUrl');
    return orderUrl;
  }

  // ── VNPay ─────────────────────────────────────────────────────────────────

  /// POST /api/payment/vnpay  → BE trả {pay_url}
  Future<String> initVnpay({required String orderId, required int amount}) async {
    final res = await _dio.post('/api/payment/vnpay', data: {
      'order_id': orderId,
    });
    final payUrl = res.data['pay_url'] as String;
    AppLogger.logInfo(_tag, 'VNPay payUrl: $payUrl');
    return payUrl;
  }
}
