class CartAttribute {
  final String typeName;
  final String value;
  final String? colorHex;

  const CartAttribute({
    required this.typeName,
    required this.value,
    this.colorHex,
  });

  factory CartAttribute.fromJson(Map<String, dynamic> j) => CartAttribute(
        typeName: j['typeName'] as String? ?? j['type_name'] as String? ?? '',
        value:    j['value']    as String? ?? '',
        colorHex: j['colorHex'] as String? ?? j['color_hex'] as String?,
      );
}

class CartItemModel {
  final String id;
  final String variantId;
  final String productId;
  final String productName;
  final String shopId;
  final String shopName;
  final String? imageUrl;
  final List<CartAttribute> attributes;
  final int unitPrice;
  final int originalPrice;
  int quantity;
  bool isSelected;

  CartItemModel({
    required this.id,
    required this.variantId,
    required this.productId,
    required this.productName,
    required this.shopId,
    required this.shopName,
    this.imageUrl,
    required this.attributes,
    required this.unitPrice,
    required this.originalPrice,
    required this.quantity,
    this.isSelected = true,
  });

  factory CartItemModel.fromJson(Map<String, dynamic> j) => CartItemModel(
        id:            j['id']           as String,
        variantId:     j['variant_id']   as String,
        // Live items may have NULL product_id / shop_id / shop_name (no
        // catalog product, no shop row for the seller). Fall back so the
        // model never throws on parse — cart grouping treats '' shopId as
        // "ungrouped".
        productId:     (j['product_id']   as String?) ?? (j['variant_id'] as String),
        productName:   (j['product_name'] as String?) ?? '',
        shopId:        (j['shop_id']      as String?) ?? '',
        shopName:      (j['shop_name']    as String?) ?? '',
        imageUrl:      j['image_url']    as String?,
        attributes:    (j['attributes'] as List? ?? [])
            .map((e) => CartAttribute.fromJson(e as Map<String, dynamic>))
            .toList(),
        unitPrice:     (j['unit_price']     as num).toInt(),
        originalPrice: (j['original_price'] as num).toInt(),
        quantity:      (j['quantity']       as num).toInt(),
        isSelected:    j['is_selected']     as bool? ?? true,
      );

  int get subtotal       => unitPrice * quantity;
  int get saving         => (originalPrice - unitPrice) * quantity;
  bool get hasDiscount   => originalPrice > unitPrice;
  int get discountPercent =>
      originalPrice > 0 ? ((originalPrice - unitPrice) * 100 ~/ originalPrice) : 0;

  // Chuỗi mô tả variant: "Đỏ · L · 1kg"
  String get attributeLabel =>
      attributes.map((a) => a.value).join(' · ');
}

class CartSummary {
  final int totalItems;
  final int totalPrice;
  final int totalSaving;

  const CartSummary({
    required this.totalItems,
    required this.totalPrice,
    required this.totalSaving,
  });

  // Backend returns snake_case (cart.go list handler). Keep camelCase
  // fallbacks for transition / older builds.
  factory CartSummary.fromJson(Map<String, dynamic> j) => CartSummary(
        totalItems:  ((j['total_items']  ?? j['totalItems']  ?? 0) as num).toInt(),
        totalPrice:  ((j['total_price']  ?? j['totalPrice']  ?? 0) as num).toInt(),
        totalSaving: ((j['total_saving'] ?? j['totalSaving'] ?? 0) as num).toInt(),
      );
}
