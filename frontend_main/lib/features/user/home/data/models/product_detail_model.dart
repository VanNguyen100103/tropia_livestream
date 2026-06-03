class ProductDetailModel {
  final String id;
  final String name;
  final String description;
  final List<String> images;
  final bool hasOptions;
  final double defaultPrice;
  final String defaultUnit;
  final List<ProductOptionModel> options;

  const ProductDetailModel({
    required this.id,
    required this.name,
    required this.description,
    required this.images,
    required this.hasOptions,
    required this.defaultPrice,
    required this.defaultUnit,
    required this.options,
  });

  static bool _isValidMedia(String? value) {
    if (value == null) return false;
    final v = value.trim();
    return v.isNotEmpty && v != '0';
  }

  factory ProductDetailModel.fromJson(Map<String, dynamic> json) {
    final images = <String>[];
    void addIfValid(dynamic value) {
      final s = value?.toString();
      if (_isValidMedia(s)) images.add(s!.trim());
    }

    double asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '0') ?? 0;
    }

    bool asBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v?.toString().toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }

    // Backend returns: image, image1..image4
    addIfValid(json['image']);
    addIfValid(json['image1']);
    addIfValid(json['image2']);
    addIfValid(json['image3']);
    addIfValid(json['image4']);

    final hasOptions = asBool(json['has_options']);
    final optionsRaw = json['options'];
    final options = (optionsRaw is List)
      ? optionsRaw
        .whereType<Map>()
        .map((e) => ProductOptionModel.fromJson(e.cast<String, dynamic>()))
        .toList()
      : <ProductOptionModel>[];

    return ProductDetailModel(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      images: images,
      hasOptions: hasOptions,
      defaultPrice: asDouble(json['default_price']),
      defaultUnit: json['default_unit']?.toString() ?? '',
      options: options,
    );
  }
}

class ProductOptionModel {
  final int id;
  final String optionName;
  final int quantity;
  final String unit;
  final double unitPrice;
  final double totalPrice;
  final int stockQuantity;
  final int? deliveryDays;
  final String deliveryText;
  final bool isDefault;
  final bool isAvailable;
  final String? lineType;

  const ProductOptionModel({
    required this.id,
    required this.optionName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.totalPrice,
    required this.stockQuantity,
    required this.deliveryDays,
    required this.deliveryText,
    required this.isDefault,
    required this.isAvailable,
    this.lineType,
  });

  factory ProductOptionModel.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '0') ?? 0;
    }

    bool asBool(dynamic v) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      final s = v?.toString().toLowerCase().trim();
      return s == 'true' || s == '1' || s == 'yes';
    }

    return ProductOptionModel(
      id: (json['id'] as num?)?.toInt() ??
          int.tryParse(json['id']?.toString() ?? '0') ??
          0,
      optionName: json['option_name']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ??
          int.tryParse(json['quantity']?.toString() ?? '0') ??
          0,
      unit: json['unit']?.toString() ?? '',
      unitPrice: asDouble(json['unit_price']),
      totalPrice: asDouble(json['total_price']),
      stockQuantity: (json['stock_quantity'] as num?)?.toInt() ??
          int.tryParse(json['stock_quantity']?.toString() ?? '0') ??
          0,
      deliveryDays: (json['delivery_days'] as num?)?.toInt() ??
          int.tryParse(json['delivery_days']?.toString() ?? ''),
      deliveryText: json['delivery_text']?.toString() ?? '',
      isDefault: asBool(json['is_default']),
      isAvailable: asBool(json['is_available']),
      lineType: json['line_type']?.toString(),
    );
  }
}
