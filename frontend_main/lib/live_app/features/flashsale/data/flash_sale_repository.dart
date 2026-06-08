// =============================================================================
// flash_sale_repository.dart
// =============================================================================
// Gọi /api/flash-sales của Go backend. Đọc "active" là public; tạo/sửa/xoá là
// admin (token gắn tự động qua AuthService.authorizedDio).
// =============================================================================

import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/flashsale/models/flash_sale_model.dart';

/// 1 dòng sản phẩm gửi lên backend khi tạo/cập nhật flash sale.
class FlashSaleProductInput {
  final String productId;
  final int flashPrice;
  final int? stockLimit;
  const FlashSaleProductInput({
    required this.productId,
    required this.flashPrice,
    this.stockLimit,
  });

  Map<String, dynamic> toJson() => {
    'product_id': productId,
    'flash_price': flashPrice,
    if (stockLimit != null) 'stock_limit': stockLimit,
  };
}

class FlashSaleRepository {
  FlashSaleRepository._();
  static final instance = FlashSaleRepository._();

  get _dio => AuthService.instance.authorizedDio();

  List<FlashSale> _parseList(dynamic data) {
    final list =
        (data is Map ? data['flash_sales'] : data) as List? ?? const [];
    return list
        .whereType<Map>()
        .map((e) => FlashSale.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// GET /api/flash-sales/active — các đợt đang chạy (public).
  Future<List<FlashSale>> listActive() async {
    final res = await _dio.get('/api/flash-sales/active');
    return _parseList(res.data);
  }

  /// GET /api/flash-sales?all=true — toàn bộ đợt (admin, kể cả tắt/đã qua).
  Future<List<FlashSale>> listAll() async {
    final res = await _dio.get(
      '/api/flash-sales',
      queryParameters: {'all': 'true'},
    );
    return _parseList(res.data);
  }

  /// POST /api/flash-sales — tạo đợt (admin).
  Future<FlashSale> create({
    required String name,
    required DateTime startsAt,
    required DateTime endsAt,
    List<FlashSaleProductInput> products = const [],
  }) async {
    final res = await _dio.post(
      '/api/flash-sales',
      data: {
        'name': name,
        'starts_at': startsAt.toUtc().toIso8601String(),
        'ends_at': endsAt.toUtc().toIso8601String(),
        'products': products.map((p) => p.toJson()).toList(),
      },
    );
    return FlashSale.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// PATCH /api/flash-sales/:id — sửa tên/khung giờ/bật-tắt (admin).
  Future<FlashSale> update(
    String id, {
    String? name,
    DateTime? startsAt,
    DateTime? endsAt,
    bool? isActive,
  }) async {
    final res = await _dio.patch(
      '/api/flash-sales/$id',
      data: {
        if (name != null) 'name': name,
        if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
        if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
        if (isActive != null) 'is_active': isActive,
      },
    );
    return FlashSale.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// PUT /api/flash-sales/:id/products — thay toàn bộ danh sách sản phẩm (admin).
  Future<FlashSale> setProducts(
    String id,
    List<FlashSaleProductInput> products,
  ) async {
    final res = await _dio.put(
      '/api/flash-sales/$id/products',
      data: {'products': products.map((p) => p.toJson()).toList()},
    );
    return FlashSale.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// DELETE /api/flash-sales/:id (admin).
  Future<void> delete(String id) async {
    await _dio.delete('/api/flash-sales/$id');
  }
}
