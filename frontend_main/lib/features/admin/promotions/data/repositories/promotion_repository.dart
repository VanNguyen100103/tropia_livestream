import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/features/admin/promotions/data/models/promotion_model.dart';

class PromotionRepository {
  final Dio client;

  PromotionRepository({required this.client});

  // 1. Lấy danh sách khuyến mãi
  Future<List<PromotionModel>> getPromotions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return [];

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      final response = await client.get("promotions", options: options);

      if (response.statusCode == 200 &&
          (response.data['Result'] == true || response.data['result'] == true)) {
        final List list = response.data['data'] ?? [];
        return list.map((e) => PromotionModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("❌ Lỗi lấy danh sách khuyến mãi: $e");
      return [];
    }
  }

  // 2. Tạo khuyến mãi mới
  Future<bool> createPromotion(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return false;

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      final response = await client.post("promotions", data: data, options: options);

      if (response.statusCode == 200) {
        return response.data['Result'] == true || response.data['result'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi tạo khuyến mãi: $e");
      return false;
    }
  }

  // 3. Cập nhật trạng thái (Pause/Active)
  Future<bool> updateStatus(String id, String status) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return false;

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      final response = await client.post(
        "promotions-status",
        queryParameters: {'id': id},
        data: {"status": status},
        options: options,
      );

      if (response.statusCode == 200) {
        return response.data['Result'] == true || response.data['result'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi cập nhật trạng thái khuyến mãi: $e");
      return false;
    }
  }
}