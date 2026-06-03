import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/points_preview_model.dart';

class CheckoutRemoteDataSource {
  final Dio client;

  CheckoutRemoteDataSource({required this.client});

  Future<PointsPreviewModel?> getPointsPreview({
    required int userId,
    required int orderAmount,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('app_auth_token') ?? '';

      final response = await client.get(
        'checkout/points-preview',
        queryParameters: {
          'user_id': userId,
          'order_amount': orderAmount,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return PointsPreviewModel.fromJson(
          response.data as Map<String, dynamic>,
        );
      }
    } catch (e) {
      debugPrint('Lỗi points-preview: $e');
    }

    return null;
  }
}
