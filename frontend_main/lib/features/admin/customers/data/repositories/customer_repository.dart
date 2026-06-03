import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/customer_model.dart';

class CustomerRepository {
  final Dio client;

  CustomerRepository({required this.client});

  // 1. Lấy danh sách khách hàng
  Future<List<CustomerModel>> getCustomers() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');

      if (appToken == null) return [];

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      final response = await client.get(
        "customers", 
        options: options,
      );

      if (response.statusCode == 200) {
        final isSuccess = (response.data['Result'] == true) || (response.data['result'] == true);
        
        if (isSuccess && response.data['data'] != null && response.data['data']['items'] != null) {
          final List list = response.data['data']['items'];
          return list.map((e) => CustomerModel.fromJson(e)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint("❌ Lỗi lấy danh sách khách hàng: $e");
      return [];
    }
  }

  // 2. Cập nhật trạng thái (Block/Active)
  Future<bool> updateCustomerStatus(String customerId, String newStatus) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');

      if (appToken == null) return false;

      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json"
      });

      // Body gửi đi
      final body = {
        "status": newStatus
      };

      // Gọi API: /customers-status?id=...
      final response = await client.post(
        "customers-status",
        queryParameters: {'id': customerId}, // Dio sẽ tự nối ?id=...
        data: body,
        options: options,
      );

      if (response.statusCode == 200) {
         return response.data['Result'] == true || response.data['result'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi cập nhật trạng thái khách hàng: $e");
      return false;
    }
  }
}