class CartModel {
  final List<CartItemModel> items;
  final CartSummaryModel summary;

  CartModel({required this.items, required this.summary});

  factory CartModel.fromJson(Map<String, dynamic> json) {
    return CartModel(
      items:
          (json['items'] as List?)
              ?.map((e) => CartItemModel.fromJson(e))
              .toList() ??
          [],
      summary: CartSummaryModel.fromJson(json['summary'] ?? {}),
    );
  }
}

class CartItemModel {
  final String productId;
  final String name;
  final String image;
  final double price;
  final double? originalPrice; // <--- BẠN ĐANG THIẾU TRƯỜNG NÀY
  final int quantity;
  final double totalLinePrice;
  final CartItemOptionModel? option;

  CartItemModel({
    required this.productId,
    required this.name,
    required this.image,
    required this.price,
    this.originalPrice, // <--- Thêm vào constructor
    required this.quantity,
    required this.totalLinePrice,
    required this.option,
  });

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '0') ?? 0;
    }

    return CartItemModel(
      // API may return int for product_id (e.g. 60016) while the app expects String.
      productId: (json['product_id'] ?? '').toString(),
      name: json['name'] ?? '',
      image: json['image'] ?? '',
      price: asDouble(json['price']),

      // <--- Thêm logic parse originalPrice
      originalPrice: (json['original_price'] as num?)?.toDouble(),

      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      totalLinePrice: asDouble(json['total_line_price']),
      option: (json['option'] is Map)
          ? CartItemOptionModel.fromJson(
              (json['option'] as Map).cast<String, dynamic>(),
            )
          : null,
    );
  }
}

class CartItemOptionModel {
  final int optionId;
  final String optionName;
  final int quantity;
  final String unit;
  final double unitPrice;
  final double totalPrice;
  final int? deliveryDays;
  final String deliveryText;

  const CartItemOptionModel({
    required this.optionId,
    required this.optionName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.totalPrice,
    required this.deliveryDays,
    required this.deliveryText,
  });

  factory CartItemOptionModel.fromJson(Map<String, dynamic> json) {
    double asDouble(dynamic v) {
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '0') ?? 0;
    }

    return CartItemOptionModel(
      optionId: (json['option_id'] as num?)?.toInt() ??
          int.tryParse(json['option_id']?.toString() ?? '0') ??
          0,
      optionName: json['option_name']?.toString() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ??
          int.tryParse(json['quantity']?.toString() ?? '0') ??
          0,
      unit: json['unit']?.toString() ?? '',
      unitPrice: asDouble(json['unit_price']),
      totalPrice: asDouble(json['total_price']),
      deliveryDays: (json['delivery_days'] as num?)?.toInt() ??
          int.tryParse(json['delivery_days']?.toString() ?? ''),
      deliveryText: json['delivery_text']?.toString() ?? '',
    );
  }
}

class CartSummaryModel {
  final int totalItems;
  final double subtotal;
  final double totalPayment;

  CartSummaryModel({
    required this.totalItems,
    required this.subtotal,
    required this.totalPayment,
  });

  factory CartSummaryModel.fromJson(Map<String, dynamic> json) {
    return CartSummaryModel(
      totalItems: (json['total_items'] as num?)?.toInt() ?? 0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      totalPayment: (json['total_payment'] as num?)?.toDouble() ?? 0,
    );
  }
}
