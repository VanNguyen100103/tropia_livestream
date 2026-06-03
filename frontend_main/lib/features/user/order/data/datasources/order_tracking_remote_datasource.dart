/// Order Tracking Remote Data Source
/// Handles API communication for real-time order tracking
library;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/models/order_tracking_model.dart';

class OrderTrackingRemoteDataSource {
  final Dio dio;

  OrderTrackingRemoteDataSource({required this.dio});

  String _normalizeOrderId(String orderId) {
    final digits = orderId.replaceAll(RegExp(r'\D'), '');
    return digits.isNotEmpty ? digits : orderId;
  }

  /// Fetch order tracking information
  /// GET order-tracking?order_id={orderId}
  Future<OrderTrackingModel?> getOrderTracking(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('app_auth_token');

      if (token == null || token.isEmpty) {
        return null;
      }

      final normalizedOrderId = _normalizeOrderId(orderId);

      final response = await dio.get(
        'order-tracking',
        queryParameters: {'order_id': normalizedOrderId},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200) {
        final data = response.data;
        
        // Check if response is successful
        if ((data['Result'] == true || data['status'] == 200) && data['data'] != null) {
          return OrderTrackingModel.fromJson(response.data);
        }
      }

      return null;
    } on DioException catch (e) {
      debugPrint('Order tracking API error: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('Order tracking parse error: $e');
      return null;
    }
  }
}
