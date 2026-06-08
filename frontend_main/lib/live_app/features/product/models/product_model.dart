import 'package:tropia_mobile_app_android/live_app/features/category/models/category_model.dart';

class ProductVariant {
  final String id;
  final String name;
  final int price;
  final int stock;
  final List<String> images;
  final Map<String, dynamic> attributes;

  const ProductVariant({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    required this.images,
    required this.attributes,
  });

  factory ProductVariant.fromJson(Map<String, dynamic> j) {
    // attributes từ variant_detail là JSON array [{typeName, value, ...}]
    // convert thành Map<axisName, value> để dùng trong LiveProduct
    final rawAttrs = j['attributes'];
    final Map<String, dynamic> attrsMap;
    if (rawAttrs is List) {
      attrsMap = {
        for (final a in rawAttrs.cast<Map<String, dynamic>>())
          (a['typeName'] ?? a['typeSlug'] ?? '') as String:
              (a['value'] ?? a['displayName'] ?? '') as String,
      };
    } else if (rawAttrs is Map<String, dynamic>) {
      attrsMap = rawAttrs;
    } else {
      attrsMap = {};
    }

    // name: build từ attributes hoặc sku
    final name = attrsMap.values.join(' / ').isEmpty
        ? (j['sku'] as String? ?? 'Mặc định')
        : attrsMap.values.join(' / ');

    return ProductVariant(
      id:         j['id']   as String,
      name:       name,
      price:      (j['price'] as num).toInt(),
      stock:      (j['stock'] as num? ?? 0).toInt(),
      images:     (j['images'] as List?)?.cast<String>() ?? [],
      attributes: attrsMap,
    );
  }
}

class ProductModel {
  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? thumbnail;
  final String status;
  final String shopId;
  final String? shopName;
  final CategoryModel? category;
  final List<ProductVariant> variants;
  final int basePrice;
  final int totalStock;

  const ProductModel({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.thumbnail,
    required this.status,
    required this.shopId,
    this.shopName,
    this.category,
    required this.variants,
    required this.basePrice,
    this.totalStock = 0,
  });

  factory ProductModel.fromJson(Map<String, dynamic> j) {
    // Backend trả về variant_detail (từ view) hoặc variants
    final rawVariants = (j['variant_detail'] as List?) ?? (j['variants'] as List?) ?? [];
    final variantList = rawVariants
        .map((v) => ProductVariant.fromJson(v as Map<String, dynamic>))
        .toList();

    final minPrice = variantList.isEmpty
        ? (j['base_price'] as num? ?? 0).toInt()
        : variantList.map((v) => v.price).reduce((a, b) => a < b ? a : b);

    // thumbnail: lấy images[0] hoặc thumbnail trực tiếp
    final images = (j['images'] as List?)?.cast<String>() ?? [];
    final thumbnail = (j['thumbnail'] as String?) ?? (images.isNotEmpty ? images.first : null);

    // category: lấy từ product_categories[is_primary] hoặc key category
    dynamic catJson;
    final productCats = j['product_categories'] as List?;
    if (productCats != null && productCats.isNotEmpty) {
      final primary = productCats.firstWhere(
        (c) => (c as Map)['is_primary'] == true,
        orElse: () => productCats.first,
      ) as Map<String, dynamic>;
      catJson = primary['categories'];
    } else {
      catJson = j['category'];
    }

    // shopName: lấy từ shops.name hoặc shop_name
    final shopObj = j['shops'] as Map<String, dynamic>?;
    final shopName = shopObj?['name'] as String? ?? j['shop_name'] as String?;
    final shopId   = shopObj?['id']   as String? ?? j['shop_id']   as String;

    return ProductModel(
      id: j['id'] as String,
      slug: j['slug'] as String,
      name: j['name'] as String,
      description: j['description'] as String?,
      thumbnail: thumbnail,
      status: j['status'] as String? ?? 'active',
      shopId: shopId,
      shopName: shopName,
      category: catJson is Map<String, dynamic>
          ? CategoryModel.fromJson(catJson)
          : null,
      variants: variantList,
      basePrice: minPrice,
      totalStock: (j['total_stock'] as num? ?? 0).toInt(),
    );
  }
}
