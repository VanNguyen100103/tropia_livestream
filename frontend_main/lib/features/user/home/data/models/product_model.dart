class ProductModel {
  final String id;
  final String name;
  final double originalPrice;
  final double salePrice;
  final String image;
  final String discount;
  final int sold;
  final int stock;
  final int? discountSlotsTotal;
  final int? discountSlotsLeft;
  final bool? isDiscountAvailable;
  final List<Map<String, dynamic>> options;
  final List<Map<String, dynamic>> optionsRecommend;

  ProductModel({
    required this.id,
    required this.name,
    required this.originalPrice,
    required this.salePrice,
    required this.image,
    required this.discount,
    required this.sold,
    required this.stock,
    this.discountSlotsTotal,
    this.discountSlotsLeft,
    this.isDiscountAvailable,
    this.options = const [],
    this.optionsRecommend = const [],
  });

  bool get isOutOfStock => stock <= 0;

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    // Ưu tiên original_price → price_public → price_regular
    final originalPriceRaw = json['original_price'] ??
        (json.containsKey('price_public')
            ? json['price_public']
            : json['price_regular']);

    // Ưu tiên final_price → price_sale → price_flash → price
    final salePriceRaw = json['final_price'] ??
        (json.containsKey('price_sale')
            ? json['price_sale']
            : json.containsKey('price_flash')
                ? json['price_flash']
                : json['price']);

    final discountRaw = json.containsKey('discount')
        ? json['discount']
        : json['discount_percent'];
    final discountText = (discountRaw == null) ? '' : discountRaw.toString();
    final normalizedDiscount = discountText.isEmpty
        ? ''
        : (RegExp(r'^\d+(\.\d+)?$').hasMatch(discountText)
              ? '$discountText%'
              : discountText);

    return ProductModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      originalPrice: double.tryParse(originalPriceRaw?.toString() ?? '0') ?? 0,
      salePrice: double.tryParse(salePriceRaw?.toString() ?? '0') ?? 0,
      image: json['primary_image']?.toString().isNotEmpty == true
          ? json['primary_image'].toString()
          : json['image']?.toString() ?? '',
      discount: normalizedDiscount,
      sold: int.tryParse(json['sold']?.toString() ?? '0') ?? 0,
      stock: int.tryParse(json['stock']?.toString() ?? '0') ?? 0,
      discountSlotsTotal: (json['discount_slots_total'] as num?)?.toInt(),
      discountSlotsLeft: (json['discount_slots_left'] as num?)?.toInt(),
      isDiscountAvailable: json['is_discount_available'] as bool?,
      options: _parseMapList(json['options']),
      optionsRecommend: _parseMapList(json['options_recommend']),
    );
  }

  static List<Map<String, dynamic>> _parseMapList(dynamic raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
}
