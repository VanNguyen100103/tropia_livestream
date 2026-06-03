import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart'; // Đổi đường dẫn nếu cần
import 'package:tropia_mobile_app_android/features/user/order/data/models/user_orders.dart';

abstract class OrderRemoteDataSource {
  Future<List<UserOrder>> getUserOrders(int userId);
  Future<UserOrder?> getOrderDetail(String orderId);
  Future<bool> cancelOrder(int userId, String orderId, String cancelReason);
}

class OrderRemoteDataSourceImpl implements OrderRemoteDataSource {
  final Dio _dio = DioClient().dio;

  // --- 1. LẤY DANH SÁCH ĐƠN HÀNG ---
  @override
  Future<List<UserOrder>> getUserOrders(int userId) async {
    debugPrint("----------------------------------------------------------------");
    debugPrint("🚀 [API REQUEST] getUserOrders");

    try {
      // A. Lấy Token
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('app_auth_token');

      if (token == null || token.isEmpty) {
        debugPrint("⚠️ Token trống, vui lòng đăng nhập lại.");
        return [];
      }

      // B. Header
      final options = Options(
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      // C. Endpoint & Params
      // URL mẫu: .../index.php?r=api/user-orders&user_id=40
      const String endpoint = 'user-orders'; 
      
      debugPrint("🔗 Endpoint: $endpoint | UserID: $userId");

      final response = await _dio.get(
        endpoint,
        queryParameters: {
          "user_id": userId,
        },
        options: options,
      );

      debugPrint("✅ [API RESPONSE] StatusCode: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = response.data;

        // Kiểm tra logic thành công của Server
        if (data['Result'] == true || data['status'] == 200) {
          final List<dynamic> items = data['data']['items'] ?? [];
          
          debugPrint("📦 Đã lấy được ${items.length} đơn hàng.");
          
          return items.map((json) => UserOrder.fromJson(json)).toList();
        } else {
          debugPrint("⚠️ Lỗi Server báo về: ${data['StatusMess'] ?? data['message']}");
        }
      }
      return [];

    } catch (e) {
      debugPrint("❌ [API ERROR] getUserOrders: $e");
      return [];
    } finally {
      debugPrint("----------------------------------------------------------------");
    }
  }

  // --- 2. HỦY ĐƠN HÀNG ---
  @override
  Future<bool> cancelOrder(int userId, String orderId, String cancelReason) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('app_auth_token');
      if (token == null || token.isEmpty) return false;

      final options = Options(
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      final response = await _dio.post(
        'order-cancel',
        data: {
          "user_id": userId,
          "order_id": orderId,
          "cancel_reason": cancelReason,
        },
        options: options,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return data['Result'] == true || data['status'] == 200;
      }
      return false;
    } catch (e) {
      debugPrint("❌ [API ERROR] cancelOrder: $e");
      return false;
    }
  }

  // --- 3. LẤY CHI TIẾT ĐƠN HÀNG ---
  @override
  Future<UserOrder?> getOrderDetail(String orderId) async {
    debugPrint("----------------------------------------------------------------");
    debugPrint("🚀 [API REQUEST] getOrderDetail");

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('app_auth_token');

      if (token == null) return null;

      final options = Options(
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      // URL mẫu: .../index.php?r=api/orders&id=ORD00010295
      const String endpoint = 'orders';

      debugPrint("🔗 Endpoint: $endpoint | OrderID: $orderId");

      final response = await _dio.get(
        endpoint,
        queryParameters: {
          "id": orderId,
        },
        options: options,
      );

      debugPrint("✅ [API RESPONSE] StatusCode: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = response.data;

        if (data['Result'] == true || data['status'] == 200) {
          final dynamic orderData = data['data'];
          if (orderData != null) {
            return UserOrder.fromJson(orderData);
          }
        }
      }
      return null;

    } catch (e) {
      debugPrint("❌ [API ERROR] getOrderDetail: $e");
      return null;
    } finally {
      debugPrint("----------------------------------------------------------------");
    }
  }
}