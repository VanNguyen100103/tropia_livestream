import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/address_model.dart';

class AddressRepository {
  final Dio client;

  AddressRepository({required this.client});

  // --- 1. LẤY DANH SÁCH ĐỊA CHỈ ---
  Future<List<AddressModel>> getUserAddresses(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      final options = Options(headers: {"Authorization": "Bearer $appToken"});

      final response = await client.get(
        "user-addresses",
        queryParameters: {'user_id': userId},
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        final List list = response.data['data'] ?? [];
        return list.map((e) => AddressModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Lỗi lấy danh sách địa chỉ: $e");
      return [];
    }
  }

 Future<String> addUserAddress(int userId, AddressModel newAddress) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      final Map<String, dynamic> body = newAddress.toJson();
      body['user_id'] = userId;

      debugPrint("🚀 POST Body: $body");

      final response = await client.post(
        "user-addresses",
        data: body,
        options: options,
      );

      if (response.statusCode == 200 && (response.data['Result'] == true || response.data['status'] == 200)) {
        return "SUCCESS";
      }
      
      // Trường hợp 200 nhưng server báo lỗi logic
      return response.data['message'] ?? response.data['StatusMess'] ?? "Lỗi không xác định";

    } catch (e) {
      debugPrint("❌ Lỗi thêm địa chỉ: $e");
      
      // --- BẮT LỖI TỪ SERVER (400, 422, 500...) ---
      if (e is DioException && e.response != null) {
        final data = e.response?.data;
        if (data is Map<String, dynamic>) {
          // Ưu tiên 1: Lấy lỗi trong object "errors" (Ví dụ: phone không hợp lệ)
          if (data['errors'] != null && data['errors'] is Map) {
             Map errors = data['errors'];
             if (errors.isNotEmpty) {
               // Lấy value của lỗi đầu tiên tìm thấy (VD: "Số điện thoại không hợp lệ...")
               return errors.values.first.toString();
             }
          }
          // Ưu tiên 2: Lấy message chung
          if (data['message'] != null) return data['message'];
          if (data['StatusMess'] != null) return data['StatusMess'];
        }
      }
      
      return "Lỗi kết nối hoặc hệ thống";
    }   
  }

  Future<bool> deleteUserAddress(int addressId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      // Gọi API DELETE: user/addresses-delete
      // Body: {"address_id": 11}
      final response = await client.delete(
        "user/addresses-delete",
        data: {"address_id": addressId},
        options: options,
      );

      // Check kết quả trả về
      if (response.statusCode == 200 && response.data['Result'] == true) {
        debugPrint("✅ Xóa địa chỉ thành công: ID $addressId");
        return true;
      }
      
      debugPrint("⚠️ Xóa thất bại: ${response.data}");
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi xóa địa chỉ: $e");
      return false;
    }
  }
}