import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_model.dart';
import '../models/user_address_model.dart';
// --- MỚI: Import StoreModel ---
import '../models/store_model.dart';

abstract class CartRemoteDataSource {
  Future<CartModel?> getCart(int userId);
  Future<int?> addToCart(
    int userId,
    String productId,
    int quantity, {
    int? optionId,
  });
  Future<List<UserAddressModel>> getUserAddresses(int userId);
  Future<Map<String, dynamic>?> checkout(Map<String, dynamic> orderBody);
  
  // --- MỚI: Hàm lấy danh sách cửa hàng ---
  Future<List<StoreModel>> getListStores();
}

class CartRemoteDataSourceImpl implements CartRemoteDataSource {
  final Dio client;

  CartRemoteDataSourceImpl({required this.client});

  // --- 1. LẤY GIỎ HÀNG ---
  @override
  Future<CartModel?> getCart(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      if (appToken.isEmpty) {
        debugPrint("Chưa có App Token (Cần gọi authenticateApp trước)");
        return null;
      }

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
        },
      );

      final response = await client.get(
        "cart",
        queryParameters: {
          'user_id': userId,
        },
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        final data = response.data['data'];
        return CartModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint("Lỗi lấy giỏ hàng: $e");
      return null;
    }
  }

  // --- 2. THÊM VÀO GIỎ HÀNG ---
  @override
  Future<int?> addToCart(
    int userId,
    String productId,
    int quantity, {
    int? optionId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      if (appToken.isEmpty) return null;

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      final body = {
        "user_id": userId.toString(),
        "product_id": productId,
        "quantity": quantity,
        "option_id": ?optionId,
      };

      final response = await client.post(
        "cart-add",
        data: body,
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        return response.data['data'] != null && response.data['data']['total_items'] != null
            ? response.data['data']['total_items']
            : 1;
      }
      return null;
    } catch (e) {
      debugPrint("Lỗi thêm vào giỏ: $e");
      return null;
    }
  }

  // --- 3. LẤY DANH SÁCH ĐỊA CHỈ ---
  @override
  Future<List<UserAddressModel>> getUserAddresses(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      if (appToken.isEmpty) return [];

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
        },
      );

      final response = await client.get(
        "user-addresses",
        queryParameters: {
          'user_id': userId,
        },
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        final List<dynamic> dataList = response.data['data'];
        return dataList.map((json) => UserAddressModel.fromJson(json)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Lỗi lấy danh sách địa chỉ: $e");
      return [];
    }
  }

  // --- 4. CHECKOUT ---
  @override
  Future<Map<String, dynamic>?> checkout(Map<String, dynamic> orderBody) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      if (appToken.isEmpty) {
        debugPrint("Thiếu App Token khi Checkout");
        return null;
      }

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      debugPrint("🚀 [API REQUEST] order-checkout");
      debugPrint("📦 BODY: $orderBody");

      final response = await client.post(
        "order-checkout",
        data: orderBody,
        options: options,
      );

      if (response.statusCode == 200) {
        return response.data; 
      }
      return null;
    } catch (e) {
      debugPrint("❌ Lỗi Checkout: $e");
      if (e is DioException && e.response != null) {
        return e.response?.data;
      }
      return null;
    }
  }

  // --- 5. (MỚI) LẤY DANH SÁCH STORE ---
  @override
  Future<List<StoreModel>> getListStores() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';

      // Tùy chọn: Nếu API /store là public thì không cần token, 
      // nhưng thường App vẫn gửi kèm để verify.
      final options = Options(
        headers: {
          if (appToken.isNotEmpty) "Authorization": "Bearer $appToken",
        },
      );

      // Gọi API /store
      // Lưu ý: Nếu base URL chưa có 'store', hãy dùng 'store'. 
      // Nếu API trả về JSON mẫu bạn gửi: { "status": "success", "data": [...] }
      final response = await client.get(
        "store", // Endpoint
        options: options,
      );

      if (response.statusCode == 200) {
        // Kiểm tra theo cấu trúc JSON bạn gửi
        if (response.data['status'] == 'success' || response.data['data'] != null) {
           final List<dynamic> data = response.data['data'];
           return data.map((e) => StoreModel.fromJson(e)).toList();
        }
      }
      return [];
    } catch (e) {
      debugPrint("Lỗi lấy danh sách store: $e");
      return [];
    }
  }
}