import 'dart:io';

import 'package:dio/dio.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/product/models/product_model.dart';

const _tag = 'ProductRepository';

class ProductRepository {
  ProductRepository._();
  static final instance = ProductRepository._();

  get _dio    => AuthService.instance.authorizedDio();
  get _public => AuthService.instance.authorizedDio();

  // ── Browse / list ─────────────────────────────────────────────────────────

  /// GET /api/products → { data, pagination: { total } }
  Future<({List<ProductModel> items, int total})> browse({
    int page      = 1,
    int limit     = 20,
    String? category,
    String? shop,
    String? search,
    String? sort,
    int? minPrice,
    int? maxPrice,
  }) async {
    final res = await _public.get('/api/products', queryParameters: {
      'page':  page,
      'limit': limit,
      if (category != null) 'category': category,
      if (shop     != null) 'shop':     shop,
      if (search   != null) 'search':   search,
      if (sort     != null) 'sort':     sort,
      if (minPrice != null) 'min_price': minPrice,
      if (maxPrice != null) 'max_price': maxPrice,
    });
    final body = res.data as Map<String, dynamic>;
    final rawList = (body['data'] as List?) ?? (body['items'] as List?) ?? [];
    final items = rawList
        .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = body['pagination'] as Map<String, dynamic>?;
    final total = (pagination?['total'] ?? body['total'] ?? 0) as num;
    return (items: items, total: total.toInt());
  }

  /// GET /api/products/:slug
  Future<ProductModel> getBySlug(String slug) async {
    final res = await _public.get('/api/products/$slug');
    return ProductModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// GET /api/products/shop/:shopId
  Future<({List<ProductModel> items, int total})> getByShop(
      String shopId, {int page = 1, int limit = 20}) async {
    final res = await _public.get('/api/products/shop/$shopId',
        queryParameters: {'page': page, 'limit': limit});
    final body = res.data as Map<String, dynamic>;
    final rawList = (body['data'] as List?) ?? (body['items'] as List?) ?? [];
    final items = rawList
        .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = body['pagination'] as Map<String, dynamic>?;
    final total = (pagination?['total'] ?? body['total'] ?? 0) as num;
    return (items: items, total: total.toInt());
  }

  /// GET /api/products/seller/list  (seller only)
  Future<({List<ProductModel> items, int total})> getSellerProducts(
      {int page = 1, int limit = 20, String? status}) async {
    final res = await _dio.get('/api/products/seller/list', queryParameters: {
      'page':  page,
      'limit': limit,
      if (status != null) 'status': status,
    });
    final body = res.data as Map<String, dynamic>;
    final rawList = (body['data'] as List?) ?? (body['items'] as List?) ?? [];
    final items = rawList
        .map((e) => ProductModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final pagination = body['pagination'] as Map<String, dynamic>?;
    final total = (pagination?['total'] ?? body['total'] ?? 0) as num;
    return (items: items, total: total.toInt());
  }

  /// GET /api/products/attributes
  Future<List<dynamic>> getAttributes() async {
    final res = await _public.get('/api/products/attributes');
    return res.data as List;
  }

  // ── Upload ────────────────────────────────────────────────────────────────

  /// POST /api/upload/temp — upload ảnh tạm, trả về URL Cloudinary
  Future<String> uploadTempImage(File imageFile) async {
    final formData = FormData.fromMap({
      'image': await MultipartFile.fromFile(
        imageFile.path,
        filename: imageFile.path.split('/').last,
      ),
    });
    final res = await _dio.post('/api/upload/temp', data: formData);
    return (res.data as Map<String, dynamic>)['url'] as String;
  }

  // ── Mutate (seller/admin) ─────────────────────────────────────────────────

  /// POST /api/products/quick-create — tạo nhanh sản phẩm trong buổi live
  Future<ProductModel> quickCreate({
    required String name,
    String? description,
    required double price,
    required int stock,
    String? imageUrl,
  }) async {
    final res = await _dio.post('/api/products/quick-create', data: {
      'name':        name,
      'description': description,
      'price':       price,
      'stock':       stock,
      if (imageUrl != null) 'imageUrl': imageUrl,
    });
    AppLogger.logInfo(_tag, 'Quick product created: ${res.data['id']}');
    return ProductModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// POST /api/products
  Future<ProductModel> create(Map<String, dynamic> body) async {
    final res = await _dio.post('/api/products', data: body);
    AppLogger.logInfo(_tag, 'Product created: ${res.data['id']}');
    return ProductModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// PATCH /api/products/:id
  Future<ProductModel> update(String id, Map<String, dynamic> body) async {
    final res = await _dio.patch('/api/products/$id', data: body);
    return ProductModel.fromJson(res.data as Map<String, dynamic>);
  }

  /// PATCH /api/products/:id/status
  Future<void> changeStatus(String id, String status) async {
    await _dio.patch('/api/products/$id/status', data: {'status': status});
  }

  /// DELETE /api/products/:id
  Future<void> delete(String id) async {
    await _dio.delete('/api/products/$id');
    AppLogger.logInfo(_tag, 'Product deleted: $id');
  }

  // ── Variants ──────────────────────────────────────────────────────────────

  /// POST /api/products/:id/variants
  Future<ProductVariant> addVariant(String productId, Map<String, dynamic> body) async {
    final res = await _dio.post('/api/products/$productId/variants', data: body);
    return ProductVariant.fromJson(res.data as Map<String, dynamic>);
  }

  /// PATCH /api/products/:id/variants/:variantId
  Future<ProductVariant> updateVariant(
      String productId, String variantId, Map<String, dynamic> body) async {
    final res = await _dio.patch('/api/products/$productId/variants/$variantId', data: body);
    return ProductVariant.fromJson(res.data as Map<String, dynamic>);
  }

  /// DELETE /api/products/:id/variants/:variantId
  Future<void> deleteVariant(String productId, String variantId) async {
    await _dio.delete('/api/products/$productId/variants/$variantId');
  }
}
