import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/features/admin/promotions/data/models/banner_model.dart';

class BannerRepository {
  final Dio client;

  BannerRepository({required this.client});

  // 1. Lấy danh sách Banner
  Future<List<BannerModel>> getBanners() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      // Nếu API yêu cầu token thì giữ dòng này, không thì có thể bỏ
      
      final options = Options(headers: {
        "Authorization": "Bearer $appToken", 
        "Content-Type": "application/json"
      });

      // Gọi API: index.php?r=api/banners
      // Lưu ý: Nếu Dio base url chưa có, bạn cần điền đủ path
      final response = await client.get(
        "banners", // Hoặc "api/banners" tùy config base URL của bạn
        options: options,
      );

      // Check điều kiện thành công dựa trên ảnh JSON: Result: true
      if (response.statusCode == 200 && response.data['Result'] == true) {
        final List listData = response.data['data'] ?? [];
        
        return listData.map((e) => BannerModel.fromJson(e)).toList();
      }
      
      return [];
    } catch (e) {
      debugPrint("❌ Lỗi lấy danh sách banner: $e");
      return [];
    }
  }

  // 2. Tạo Banner mới
  Future<bool> createBanner(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return false;

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      // Gọi API: index.php?r=api/banners/create
      final response = await client.post(
        "banners/create", // Hoặc api/banners/create tùy config
        data: data,
        options: options,
      );

      if (response.statusCode == 200) {
        // API của bạn trả về Result: true
        return response.data['Result'] == true || response.data['result'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi tạo banner: $e");
      return false;
    }
  }
}