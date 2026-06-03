import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/models/cart_model.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/models/user_address_model.dart';
// --- MỚI: IMPORT MODEL STORE ---
import 'package:tropia_mobile_app_android/features/user/cart/data/models/store_model.dart';
import '../../domain/repositories/cart_repository.dart';

class CartRepositoryImpl implements CartRepository {
  final CartRemoteDataSource remoteDataSource;
  final Dio _dio = DioClient().dio;

  CartRepositoryImpl({required this.remoteDataSource});

  // --- 1. LẤY GIỎ HÀNG ---
  @override
  Future<CartModel?> getCart(int userId) async {
    try {
      return await remoteDataSource.getCart(userId);
    } catch (e) {
      debugPrint("❌ Lỗi getCart: $e");
      return null;
    }
  }

  // --- 2. THÊM VÀO GIỎ HÀNG ---
  @override
  Future<String> addToCart(
    int userId,
    String productId,
    int quantity, {
    int? optionId,
  }) async {
    debugPrint("----------------------------------------------------------------");
    debugPrint("🚀 [API REQUEST] addToCart");

    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('app_auth_token');

      if (token == null || token.isEmpty) {
        return "Vui lòng đăng nhập lại (Thiếu Token)";
      }

      final options = Options(
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      const String endpoint = 'cart-add';

      debugPrint("🔗 URL: ${_dio.options.baseUrl}$endpoint");
      final payload = {
        "user_id": userId.toString(),
        "product_id": productId,
        "quantity": quantity,
        "option_id": ?optionId,
      };
      debugPrint("📦 DATA: $payload");

      final response = await _dio.post(
        endpoint,
        data: payload,
        options: options,
      );

      debugPrint("✅ [API RESPONSE] StatusCode: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['Result'] == true || data['status'] == 200 || data['success'] == true) {
          debugPrint("🎉 THÊM GIỎ HÀNG THÀNH CÔNG!");
          return "SUCCESS"; 
        } 
        
        String errorMsg = data['StatusMess'] ?? data['message'] ?? "Lỗi không xác định từ Server";
        debugPrint("⚠️ Server báo lỗi: $errorMsg");
        return errorMsg; 
      }
      
      return "Lỗi kết nối: ${response.statusCode}";

    } catch (e) {
      debugPrint("❌ [API ERROR]: $e");
      if (e is DioException && e.response != null) {
        final data = e.response?.data;
        if (data is Map) {
             return data['StatusMess'] ?? data['message'] ?? "Lỗi hệ thống: ${e.message}";
        }
      }
      return "Lỗi hệ thống: $e";
    } finally {
      debugPrint("----------------------------------------------------------------");
    }
  }

  // --- 3. CẬP NHẬT GIỎ HÀNG ---
  @override
  Future<bool> updateCart(
    int userId,
    String productId,
    int quantity, {
    int? optionId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? token = prefs.getString('app_auth_token');
      if (token == null) return false;

      final options = Options(
        headers: {
          "Authorization": "Bearer $token",
          "Content-Type": "application/json",
        },
      );

      final response = await _dio.post(
        'cart-update',
        data: {
          "user_id": userId.toString(),
          "product_id": productId,
          "quantity": quantity,
          "option_id": ?optionId,
        },
        options: options,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['Result'] == true || data['status'] == 200) return true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi updateCart: $e");
      return false;
    }
  }

  // --- 4. LẤY ĐỊA CHỈ USER ---
  @override
  Future<List<UserAddressModel>> getUserAddresses(int userId) async {
    try {
      return await remoteDataSource.getUserAddresses(userId);
    } catch (e) {
      debugPrint("❌ Lỗi getUserAddresses: $e");
      return [];
    }
  }


  @override
  Future<List<StoreModel>> getListStores() async {
    try {
      // Gọi xuống DataSource mà chúng ta đã viết lúc nãy
      return await remoteDataSource.getListStores();
    } catch (e) {
      debugPrint("❌ Lỗi getListStores: $e");
      return [];
    }
  }
}