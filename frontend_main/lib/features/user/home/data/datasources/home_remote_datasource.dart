// lib/features/user/home/data/datasources/home_remote_datasource.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 1. Thêm import này
import 'package:tropia_mobile_app_android/features/user/home/data/models/banner_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/featured_category_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/flash_sale_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/product_detail_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/product_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/ready_to_cook_model.dart';
import '../../../../../core/constants/api_constants.dart';
import '../models/category_model.dart';
import '../models/search_products_result.dart';

abstract class HomeRemoteDataSource {
  Future<SearchProductsResult> searchProductsWithMeta({
    String? keyword,
    String? categoryId,
    int page,
    int limit,
    String? id,
  });
  Future<List<CategoryModel>> getCategories();
  Future<List<FlashSaleModel>> getFlashSales();
  Future<FlashSaleModel?> getFlashSale();
  Future<List<ReadyToCookModel>> getReadyToCook();
  Future<List<FeaturedCategoryModel>> getFeaturedCategories();
  Future<ProductDetailModel?> getProductDetail({required String id});
  Future<List<ProductModel>> searchProducts({
    String? keyword,
    String? categoryId,
    int page,
    int limit,
    String? id,
  });
  Future<List<BannerModel>> getBanners();
  Future<Map<String, dynamic>> getDailyMarket();
}

class HomeRemoteDataSourceImpl implements HomeRemoteDataSource {
    @override
    Future<SearchProductsResult> searchProductsWithMeta({
      String? keyword,
      String? categoryId,
      int page = 1,
      int limit = 10,
      String? id,
    }) async {
      try {
        final options = await _optionsWithAppToken();
        final Map<String, dynamic> queryParams = {};
        if (id != null && id.isNotEmpty) queryParams['id'] = id;
        if (keyword != null && keyword.isNotEmpty) queryParams['keyword'] = keyword;
        if (categoryId != null && categoryId.isNotEmpty) queryParams['category_id'] = categoryId;
        if (page > 0) queryParams['page'] = page;
        if (limit > 0) queryParams['limit'] = limit;

        // Có keyword → dùng api/search (trả về hỗn hợp category+product)
        // Không có keyword → dùng api/products (list thông thường)
        final endpoint = (keyword != null && keyword.isNotEmpty)
            ? ApiConstants.search
            : ApiConstants.products;

        final response = await client.get(endpoint, queryParameters: queryParams, options: options);

        if (response.statusCode == 200) {
          final data = response.data;
          final dataObject = (data is Map<String, dynamic>) ? data['data'] : null;
          if (dataObject is! Map<String, dynamic>) return SearchProductsResult(products: [], total: 0);

          final rawItems = (dataObject['items'] as List?) ?? [];

          // api/search trả về mixed list — lọc chỉ lấy item_type == "product"
          final productItems = rawItems.where((item) {
            if (item is! Map) return false;
            final type = item['item_type']?.toString();
            return type == null || type == 'product';
          }).toList();

          final products = productItems.map(_parseProduct).toList();

          // api/search dùng total_results/total_pages ở dataObject level
          // api/products dùng pagination.total trong dataObject
          int total = (dataObject['total_results'] as num?)?.toInt() ?? 0;
          if (total == 0) {
            final pagination = dataObject['pagination'];
            total = (pagination is Map ? pagination['total'] as num? : null)?.toInt() ?? products.length;
          }

          return SearchProductsResult(products: products, total: total);
        }
        return SearchProductsResult(products: [], total: 0);
      } catch (e) {
        return SearchProductsResult(products: [], total: 0);
      }
    }
  final Dio client;
  HomeRemoteDataSourceImpl({required this.client});

  Future<Options?> _optionsWithAppToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('app_auth_token');
    if (token == null || token.isEmpty) return null;
    return Options(headers: {'Authorization': 'Bearer $token'});
  }

  @override
  Future<List<FlashSaleModel>> getFlashSales() async {
    try {
      final options = await _optionsWithAppToken();
      final response = await client.get(
        ApiConstants.flashSale,
        options: options,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return [];

      final dataObject = data['data'];

      // New response shape: { Result: true, status: 200, data: { flash_sales: [] } }
      final flashSalesRaw = (dataObject is Map<String, dynamic>)
          ? (dataObject['flash_sales'] as List?)
          : null;

      if (flashSalesRaw != null) {
        return flashSalesRaw
            .whereType<Map>()
            .map((e) => FlashSaleModel.fromJson(e.cast<String, dynamic>()))
            .toList();
      }

      // Fallback old response shape: { status: 200, data: { ...single flash sale... } }
      if (data['status'] == 200 && dataObject is Map<String, dynamic>) {
        return [FlashSaleModel.fromJson(dataObject)];
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  FlashSaleModel? _selectFlashSale(List<FlashSaleModel> sales) {
    if (sales.isEmpty) return null;

    final now = DateTime.now();

    final activeSales = sales.where((s) {
      final start = s.startTime;
      final end = s.endTime;
      if (start == null || end == null) return false;
      if (s.active == 2 || s.active == 3) return false;
      final inWindow = !now.isBefore(start) && now.isBefore(end);
      if (!inWindow) return false;

      // Prefer backend active flag/label when present.
      if (s.active != null) return s.active == 1;
      if (s.activeLabel != null) {
        return s.activeLabel!.toLowerCase().contains('active');
      }
      return true;
    }).toList();

    if (activeSales.isNotEmpty) {
      activeSales.sort((a, b) {
        final aEnd = a.endTime ?? DateTime(9999);
        final bEnd = b.endTime ?? DateTime(9999);
        return aEnd.compareTo(bEnd);
      });
      return activeSales.first;
    }

    final upcomingSales = sales.where((s) {
      final start = s.startTime;
      if (start == null) return false;
      if (s.active == 2 || s.active == 3) return false;
      return start.isAfter(now);
    }).toList();

    if (upcomingSales.isEmpty) return null;
    upcomingSales.sort((a, b) {
      final aStart = a.startTime ?? DateTime(9999);
      final bStart = b.startTime ?? DateTime(9999);
      return aStart.compareTo(bStart);
    });
    return upcomingSales.first;
  }

  @override
  Future<List<CategoryModel>> getCategories() async {
    try {
      final options = await _optionsWithAppToken();
      final response = await client.get(
        ApiConstants.categories,
        options: options,
      );
      if (response.data['status'] == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => CategoryModel.fromJson(e))
            .toList();
      } else {
        return [];
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<FlashSaleModel?> getFlashSale() async {
    try {
      final options = await _optionsWithAppToken();
      final response = await client.get(
        ApiConstants.flashSale,
        options: options,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return null;

      // New response shape: { Result: true, status: 200, data: { flash_sales: [] } }
      final dataObject = data['data'];
      final flashSalesRaw = (dataObject is Map<String, dynamic>)
          ? (dataObject['flash_sales'] as List?)
          : null;

      if (flashSalesRaw != null) {
        final sales = flashSalesRaw
            .whereType<Map>()
            .map((e) => FlashSaleModel.fromJson(e.cast<String, dynamic>()))
            .toList();
        return _selectFlashSale(sales);
      }

      // Fallback old response shape: { status: 200, data: { ...single flash sale... } }
      if (data['status'] == 200 && dataObject is Map<String, dynamic>) {
        return FlashSaleModel.fromJson(dataObject);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<List<ReadyToCookModel>> getReadyToCook() async {
    try {
      final options = await _optionsWithAppToken();
      final response = await client.get(
        ApiConstants.readyToCook,
        options: options,
      );
      if (response.data['status'] == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => ReadyToCookModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<FeaturedCategoryModel>> getFeaturedCategories() async {
    try {
      final options = await _optionsWithAppToken();
      final response = await client.get(
        ApiConstants.featuredCategories,
        options: options,
      );
      if (response.data['status'] == 200 && response.data['data'] != null) {
        return (response.data['data'] as List)
            .map((e) => FeaturedCategoryModel.fromJson(e))
            .toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<ProductDetailModel?> getProductDetail({required String id}) async {
    try {
      final options = await _optionsWithAppToken();
      final response = await client.get(
        ApiConstants.products,
        queryParameters: {'id': id},
        options: options,
      );

      final data = response.data;
      if (data is! Map<String, dynamic>) return null;

      final dataObject = data['data'];
      if (dataObject is! Map<String, dynamic>) return null;

      final items = dataObject['items'];
      if (items is! List) return null;
      if (items.isEmpty) return null;

      final first = items.first;
      if (first is! Map) return null;
      return ProductDetailModel.fromJson(first.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  // --- 3. LOGIC SEARCH ---
  @override
  Future<List<ProductModel>> searchProducts({
    String? keyword,
    String? categoryId,
    int page = 1,
    int limit = 10,
    String? id,
  }) async {
    try {
      final options = await _optionsWithAppToken();
      final Map<String, dynamic> queryParams = {};
      if (id != null && id.isNotEmpty) queryParams['id'] = id;
      if (keyword != null && keyword.isNotEmpty) queryParams['keyword'] = keyword;
      if (categoryId != null && categoryId.isNotEmpty) queryParams['category_id'] = categoryId;
      if (page > 0) queryParams['page'] = page;
      if (limit > 0) queryParams['limit'] = limit;

      // Có keyword → api/search (mixed category+product, filter item_type == "product")
      // Không có keyword → api/products
      final endpoint = (keyword != null && keyword.isNotEmpty)
          ? ApiConstants.search
          : ApiConstants.products;

      final response = await client.get(endpoint, queryParameters: queryParams, options: options);

      if (kDebugMode) debugPrint("Search URL: ${response.realUri}");

      if (response.statusCode == 200) {
        final data = response.data;
        final dataObject = (data is Map<String, dynamic>) ? data['data'] : null;

        if (dataObject is List) {
          return dataObject.map(_parseProduct).toList();
        }

        if (dataObject is Map<String, dynamic>) {
          final rawItems = (dataObject['items'] as List?) ?? [];
          // api/search trả về mixed category+product — chỉ lấy item_type == "product"
          return rawItems.where((item) {
            if (item is! Map) return false;
            final type = item['item_type']?.toString();
            return type == null || type == 'product';
          }).map(_parseProduct).toList();
        }
      }
      return [];
    } catch (e) {
      if (kDebugMode) debugPrint("Lỗi Search API: $e");
      return [];
    }
  }

  ProductModel _parseProduct(dynamic item) {
    if (item is Map) {
      return ProductModel.fromJson(item.cast<String, dynamic>());
    }
    return ProductModel(
      id: '', name: '', originalPrice: 0, salePrice: 0,
      image: '', discount: '', sold: 0, stock: 0,
    );
  }
  // ---------------------------

  @override
  Future<List<BannerModel>> getBanners() async {
    try {
      final options = await _optionsWithAppToken();
      final response = await client.get(ApiConstants.banners, options: options);
      if (response.statusCode == 200 && response.data['Result'] == true) {
        final list = response.data['data'] as List? ?? [];
        return list.map((e) => BannerModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      return [];
    }
  }

  @override
  Future<Map<String, dynamic>> getDailyMarket() async {
    try {
      final options = await _optionsWithAppToken();
      final response = await client.get(
        ApiConstants.dailyMarket,
        options: options,
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) return {};
      final dataObject = data['data'];
      if (dataObject is! Map<String, dynamic>) return {};

      final rawItems = dataObject['products'] as List? ?? dataObject['items'] as List? ?? [];
      final products = rawItems.where((item) {
        if (item is! Map) return false;
        final v = item['parent_product_id'];
        if (v == null) return true;
        final s = v.toString().trim();
        return s.isEmpty || s == '0';
      }).map(_parseProduct).toList();

      return {
        'title': dataObject['title']?.toString() ?? 'ĐI CHỢ MỖI NGÀY',
        'subtitle': dataObject['subtitle']?.toString() ?? '',
        'products': products,
      };
    } catch (e) {
      return {};
    }
  }
}
