import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/category_model.dart';
import '../models/product_model.dart';

class ProductRepository {
  final Dio client;

  ProductRepository({required this.client});

  // --- [MỚI] 0. LẤY DANH SÁCH DANH MỤC (Cho Dropdown) ---
  Future<List<CategoryModel>> getCategories() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      // Token có thể null nếu API categories là public, nhưng cứ gửi nếu có

      final options = Options(
        headers: {
          if (appToken != null) "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      // API: api/categories (hoặc đường dẫn tương tự bên Home)
      final response = await client.get("categories", options: options);

      if (response.statusCode == 200 &&
          (response.data['Result'] == true || response.data['status'] == 200)) {
        final List list = response.data['data'] ?? [];
        return list.map((e) => CategoryModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("❌ Lỗi lấy danh mục: $e");
      return [];
    }
  }

  // --- 1. LẤY DANH SÁCH SẢN PHẨM (Giữ nguyên) ---
  Future<Map<String, dynamic>> getProducts({
    int page = 1,
    int limit = 10,
    String keyword = '',
  }) async {
    try {
      int? toInt(dynamic value) {
        if (value == null) return null;
        if (value is int) return value;
        if (value is num) return value.toInt();
        if (value is String) return int.tryParse(value);
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return {'items': [], 'total_pages': 0};

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      final response = await client.get(
        "products",
        queryParameters: {
          'page': page,
          'limit': limit,
          if (keyword.isNotEmpty) 'keyword': keyword,
        },
        options: options,
      );

      if (response.statusCode == 200 &&
          (response.data['Result'] == true ||
              response.data['result'] == true)) {
        final data = response.data['data'];
        final List list = (data is Map ? data['items'] : null) ?? [];
        final items = list.map((e) => ProductModel.fromJson(e)).toList();

        final pagination =
            (data is Map ? data['pagination'] : null) ??
            response.data['pagination'];
        final parsedTotalPages = pagination is Map
            ? toInt(
                pagination['total_pages'] ??
                    pagination['totalPages'] ??
                    pagination['total_page'] ??
                    pagination['last_page'] ??
                    pagination['pages'],
              )
            : null;

        final parsedTotal = pagination is Map
            ? toInt(pagination['total'] ?? pagination['count'])
            : null;

        final parsedLimit = pagination is Map
            ? toInt(
                pagination['limit'] ??
                    pagination['per_page'] ??
                    pagination['perPage'],
              )
            : null;

        final effectiveLimit = parsedLimit ?? limit;
        final computedTotalPages = (parsedTotal != null && effectiveLimit > 0)
            ? ((parsedTotal + effectiveLimit - 1) ~/ effectiveLimit)
            : null;

        final totalPages = parsedTotalPages ?? computedTotalPages ?? 1;

        final currentPage = pagination is Map
            ? (toInt(
                    pagination['page'] ??
                        pagination['current_page'] ??
                        pagination['currentPage'] ??
                        pagination['page_number'],
                  ) ??
                  page)
            : page;

        return {'items': items, 'total_pages': totalPages, 'page': currentPage};
      }
      return {'items': <ProductModel>[], 'total_pages': 0};
    } catch (e) {
      debugPrint("❌ Lỗi lấy sản phẩm: $e");
      return {'items': <ProductModel>[], 'total_pages': 0};
    }
  }

  // --- 2. XÓA SẢN PHẨM (Giữ nguyên) ---
  Future<bool> deleteProduct(String productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return false;

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      final response = await client.post(
        "products-delete",
        queryParameters: {'id': productId},
        options: options,
      );

      if (response.statusCode == 200) {
        return response.data['Result'] == true ||
            response.data['result'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi xóa sản phẩm: $e");
      return false;
    }
  }

  // --- 3. CẬP NHẬT SẢN PHẨM (Giữ nguyên) ---
  Future<bool> updateProduct(
    String productId,
    Map<String, dynamic> updateData,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return false;

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      final response = await client.post(
        "products-update",
        queryParameters: {'id': productId},
        data: updateData,
        options: options,
      );

      if (response.statusCode == 200) {
        return response.data['Result'] == true ||
            response.data['result'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi cập nhật sản phẩm: $e");
      return false;
    }
  }

  // --- 4. TẠO SẢN PHẨM (Giữ nguyên logic, nhưng UI sẽ truyền category_id vào createData) ---
  Future<bool> createProduct(Map<String, dynamic> createData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return false;

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      // Debug: In ra body xem có category_id chưa
      debugPrint("🚀 Tạo SP với Data: $createData");

      final response = await client.post(
        "products-create",
        data: createData,
        options: options,
      );

      if (response.statusCode == 200) {
        return response.data['Result'] == true ||
            response.data['result'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi tạo sản phẩm: $e");
      return false;
    }
  }

  Future<Map<String, dynamic>> searchProductsAuthorized({
    String? keyword,
    String? categoryId,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return {'items': [], 'total_pages': 0};

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      final response = await client.post(
        "products-search",
        data: {
          if (keyword != null && keyword.isNotEmpty) 'keyword': keyword,
          if (categoryId != null && categoryId.isNotEmpty)
            'category_id': categoryId,
          'page': page,
          'limit': limit,
        },
        options: options,
      );

      if (response.statusCode == 200 &&
          (response.data['Result'] == true ||
              response.data['result'] == true)) {
        final data = response.data['data'];
        final List list = (data is Map ? data['items'] : null) ?? [];
        final items = list.map((e) => ProductModel.fromJson(e)).toList();
        final pagination = data is Map ? data['pagination'] : null;
        final total =
            (pagination is Map ? pagination['total'] as int? : null) ??
                items.length;
        final totalPages =
            (pagination is Map ? pagination['total_pages'] as int? : null) ?? 1;
        return {'items': items, 'total_pages': totalPages, 'total': total};
      }
      return {'items': <ProductModel>[], 'total_pages': 0};
    } catch (e) {
      debugPrint("❌ Lỗi tìm kiếm sản phẩm (admin): $e");
      return {'items': <ProductModel>[], 'total_pages': 0};
    }
  }

  Future<Map<String, dynamic>?> getProductsStatusDetail(String productId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');
      if (appToken == null) return null;

      final options = Options(
        headers: {
          "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      final response = await client.get(
        "products-status-detail",
        queryParameters: {'id': productId},
        options: options,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data is Map<String, dynamic>) {
          return data['data'] is Map<String, dynamic>
              ? data['data'] as Map<String, dynamic>
              : data;
        }
      }
      return null;
    } catch (e) {
      debugPrint("❌ Lỗi lấy trạng thái sản phẩm: $e");
      return null;
    }
  }

  Future<bool> createCategory({
    required String name,
    required String icon,
    int level = 1,
    int? refCode,
    int sortOrder = 1,
    int status = 1,
    int active = 1,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token');

      final options = Options(
        headers: {
          if (appToken != null) "Authorization": "Bearer $appToken",
          "Content-Type": "application/json",
        },
      );

      final body = <String, dynamic>{
        "name": name,
        "level": level,
        "icon": icon,
        "sort_order": sortOrder,
        "status": status,
        "active": active,
        "ref_code": ?refCode,
      };

      final response = await client.post(
        "categories-create",
        data: body,
        options: options,
      );

      if (response.statusCode == 200) {
        return response.data['Result'] == true ||
            response.data['result'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi tạo danh mục: $e");
      return false;
    }
  }
}
