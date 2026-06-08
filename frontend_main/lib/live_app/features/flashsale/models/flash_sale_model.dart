// =============================================================================
// flash_sale_model.dart
// =============================================================================
// Model cho Flash Sale (Shopee "Flash Sale") — khớp JSON từ Go backend
// internal/flashsale/model.go.
// =============================================================================

import 'package:tropia_mobile_app_android/live_app/core/config/app_config.dart';

String? _img(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final u = AppConfig.resolveBackendUrl(raw);
  return (u.startsWith('http://') || u.startsWith('https://')) ? u : null;
}

class FlashSaleProduct {
  final String productId;
  final String name;
  final String slug;
  final String? imageUrl;
  final int basePrice;
  final int flashPrice;
  final int? stockLimit;
  final int soldCount;
  final int sortOrder;

  const FlashSaleProduct({
    required this.productId,
    required this.name,
    required this.slug,
    this.imageUrl,
    this.basePrice = 0,
    this.flashPrice = 0,
    this.stockLimit,
    this.soldCount = 0,
    this.sortOrder = 0,
  });

  String? get image => _img(imageUrl);

  int get discountPercent => (basePrice > 0 && flashPrice < basePrice)
      ? (((basePrice - flashPrice) / basePrice) * 100).round()
      : 0;

  factory FlashSaleProduct.fromJson(Map<String, dynamic> j) => FlashSaleProduct(
    productId: j['product_id'] as String? ?? '',
    name: j['name'] as String? ?? '',
    slug: j['slug'] as String? ?? '',
    imageUrl: j['image_url'] as String?,
    basePrice: (j['base_price'] as num?)?.toInt() ?? 0,
    flashPrice: (j['flash_price'] as num?)?.toInt() ?? 0,
    stockLimit: (j['stock_limit'] as num?)?.toInt(),
    soldCount: (j['sold_count'] as num?)?.toInt() ?? 0,
    sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
  );
}

class FlashSale {
  final String id;
  final String name;
  final DateTime startsAt;
  final DateTime endsAt;
  final bool isActive;
  final List<FlashSaleProduct> products;

  const FlashSale({
    required this.id,
    required this.name,
    required this.startsAt,
    required this.endsAt,
    this.isActive = true,
    this.products = const [],
  });

  /// Đang trong khung giờ chạy (active + start <= now < end).
  bool get isLive {
    final now = DateTime.now();
    return isActive && !startsAt.isAfter(now) && endsAt.isAfter(now);
  }

  /// Sắp diễn ra (active + chưa tới giờ bắt đầu).
  bool get isUpcoming => isActive && startsAt.isAfter(DateTime.now());

  factory FlashSale.fromJson(Map<String, dynamic> j) => FlashSale(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    startsAt:
        DateTime.tryParse(j['starts_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    endsAt:
        DateTime.tryParse(j['ends_at'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
    isActive: j['is_active'] as bool? ?? true,
    products:
        (j['products'] as List?)
            ?.whereType<Map>()
            .map((e) => FlashSaleProduct.fromJson(Map<String, dynamic>.from(e)))
            .toList() ??
        const [],
  );
}
