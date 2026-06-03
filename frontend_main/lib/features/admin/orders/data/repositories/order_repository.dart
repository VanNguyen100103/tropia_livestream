import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/features/admin/dashboard/data/models/order_model.dart';
import 'package:tropia_mobile_app_android/features/admin/orders/data/models/order_detail_model.dart'; 

class OrderRepository {
  final Dio client;

  OrderRepository({required this.client});

  Future<List<OrderModel>> getAllOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');

      if (appToken == null) return [];

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      // Gọi API lấy danh sách đơn hàng
      final response = await client.get(
        "orders", 
        options: options,
      );

      if (response.statusCode == 200) {
        final isSuccess = (response.data['Result'] == true) || (response.data['result'] == true);
        
        if (isSuccess && response.data['data'] != null && response.data['data']['items'] != null) {
          final List list = response.data['data']['items'];
          // Parse toàn bộ danh sách
          return list.map((e) => OrderModel.fromJson(e)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint("❌ Lỗi lấy danh sách Orders: $e");
      return [];
    }
  }

  Future<OrderDetailModel?> getOrderDetail(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');

      if (appToken == null) return null;

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      // Gọi API: orders&id=... (Dùng queryParameters để Dio tự nối chuỗi)
      final response = await client.get(
        "orders",
        queryParameters: {'id': orderId}, 
        options: options,
      );

      if (response.statusCode == 200 && (response.data['Result'] == true || response.data['result'] == true)) {
        return OrderDetailModel.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      debugPrint("❌ Lỗi lấy chi tiết đơn: $e");
      return null;
    }
  }

  // 2. Cập nhật trạng thái đơn hàng
  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');

      if (appToken == null) return false;

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      final body = {
        "id": orderId,
        "status": newStatus
      };

      final response = await client.post(
        "orders-status",
        data: body,
        options: options,
      );

      if (response.statusCode == 200) {
         // Check cả Result viết hoa và thường cho chắc
         return response.data['Result'] == true || response.data['result'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi cập nhật trạng thái: $e");
      return false;
    }
  }
}