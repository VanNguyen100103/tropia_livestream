import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/payment_info_model.dart';

abstract class PaymentRemoteDataSource {
  Future<PaymentInfoModel?> createPayment({
    required String orderId,
    required num amount,
    required String orderInfo,
    required String extraData,
  });

  Future<Map<String, dynamic>?> checkPaymentStatus({
    required String orderId,
    String? requestId,
  });
}

class PaymentRemoteDataSourceImpl implements PaymentRemoteDataSource {
  final Dio client;

  PaymentRemoteDataSourceImpl({required this.client});

  @override
  Future<PaymentInfoModel?> createPayment({
    required String orderId,
    required num amount,
    required String orderInfo,
    required String extraData,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      final options = Options(
        headers: {
          if (appToken.isNotEmpty) 'Authorization': 'Bearer $appToken',
          'Content-Type': 'application/json',
        },
      );

      debugPrint('🚀 [API REQUEST] payment/create');
      debugPrint('🧾 order_id=$orderId amount=$amount');

      final response = await client.post(
        'payment/create',
        data: {
          'order_id': orderId,
          'amount': amount,
          'order_info': orderInfo,
          'extra_data': extraData,
        },
        options: options,
      );

      if (response.statusCode == 200) {
        final raw = response.data;
        if (raw is Map) {
          final map = raw.cast<String, dynamic>();

          // payment/create trên BE có thể trả data ở root hoặc lồng trong key 'data'
          final dynamic nested = map['data'];
          final Map<String, dynamic> payload = (nested is Map)
              ? nested.cast<String, dynamic>()
              : map;

          final info = PaymentInfoModel.fromJson(payload);
          if (info.isValid) return info;

          final msg =
              (map['StatusMess'] ?? map['message'] ?? payload['message'] ?? '')
                  .toString();
          debugPrint(
            '⚠️ payment/create parse fail. message=$msg keys=${payload.keys.toList()}',
          );
        } else {
          debugPrint('⚠️ payment/create unexpected response: $raw');
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ Lỗi payment/create: $e');
      if (e is DioException && e.response?.data is Map) {
        debugPrint('❌ payment/create response: ${e.response?.data}');
      }
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> checkPaymentStatus({
    required String orderId,
    String? requestId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      final options = Options(
        headers: {if (appToken.isNotEmpty) 'Authorization': 'Bearer $appToken'},
      );

      debugPrint('🚀 [API REQUEST] payment/status');
      debugPrint('🧾 order_id=$orderId request_id=${requestId ?? ''}');

      final response = await client.get(
        'payment/status',
        queryParameters: {
          'order_id': orderId,
          if (requestId != null && requestId.isNotEmpty)
            'request_id': requestId,
        },
        options: options,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map) return data.cast<String, dynamic>();
      }
      return null;
    } catch (e) {
      debugPrint('❌ Lỗi payment/status: $e');
      if (e is DioException && e.response?.data is Map) {
        return (e.response?.data as Map).cast<String, dynamic>();
      }
      return null;
    }
  }
}
