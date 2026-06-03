import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/features/admin/dashboard/data/models/chart_data_model.dart';
import 'package:tropia_mobile_app_android/features/admin/dashboard/data/models/order_model.dart';
import '../models/dashboard_stats_model.dart';

class DashboardRepository {
  final Dio client;

  DashboardRepository({required this.client});

  Future<DashboardStatsModel?> getDashboardStats() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // [QUAN TRỌNG] Lấy đúng key 'app_auth_token' mà AppAuthRepository đã lưu
      final appToken = prefs.getString('app_auth_token');

      // In ra 10 ký tự đầu để kiểm tra xem có lấy được token không
      debugPrint(
        "🔍 Dashboard Repo Token: ${appToken != null ? "${appToken.substring(0, 10)}..." : "NULL"}",
      );

      if (appToken == null || appToken.isEmpty) {
        debugPrint(
          "❌ LỖI: Chưa có Token Admin. Đang chờ DashboardScreen gọi authenticateApp()...",
        );
        return null;
      }

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      // Gọi API
      final response = await client.get("dashboard-stats", options: options);

      debugPrint("✅ API Dashboard Status: ${response.statusCode}");

      if (response.statusCode == 200) {
        // Kiểm tra linh hoạt cả 'Result' (viết hoa) và 'result' (viết thường)
        final bool isSuccess =
            (response.data['Result'] == true) ||
            (response.data['result'] == true);

        if (isSuccess && response.data['data'] != null) {
          debugPrint("✅ Parse dữ liệu Dashboard thành công");
          return DashboardStatsModel.fromJson(response.data['data']);
        } else {
          debugPrint("⚠️ API trả về lỗi logic: ${response.data['message']}");
        }
      }
      return null;
    } catch (e) {
      if (e is DioException) {
        // In lỗi chi tiết từ Server nếu có (401, 403, 500...)
        debugPrint(
          "❌ DIO ERROR: ${e.response?.statusCode} - ${e.response?.statusMessage}",
        );
      } else {
        debugPrint("❌ Lỗi ngoại lệ Dashboard: $e");
      }
      return null;
    }
  }

  Future<List<ChartDataModel>> getRevenueChartData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');

      if (appToken == null) return [];

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      final response = await client.get(
        "dashboard-chart-revenue", 
        options: options,
      );

      if (response.statusCode == 200) {
        final isSuccess = (response.data['Result'] == true) || (response.data['result'] == true);
        if (isSuccess && response.data['data'] != null) {
          final List list = response.data['data'];
          return list.map((e) => ChartDataModel.fromJson(e)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint("❌ Lỗi lấy Chart Data: $e");
      return [];
    }
  }

  Future<List<OrderModel>> getRecentOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');

      if (appToken == null) return [];

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      final response = await client.get(
        "orders", // Endpoint
        options: options,
      );

      if (response.statusCode == 200) {
        final isSuccess = (response.data['Result'] == true) || (response.data['result'] == true);
        
        if (isSuccess && response.data['data'] != null && response.data['data']['items'] != null) {
          final List list = response.data['data']['items'];
          
          // Parse JSON sang Model
          final allOrders = list.map((e) => OrderModel.fromJson(e)).toList();
          
          // Chỉ lấy 5 đơn mới nhất
          return allOrders.take(5).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint("❌ Lỗi lấy Recent Orders: $e");
      return [];
    }
  }
}
