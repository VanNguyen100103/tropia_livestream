class OrderModel {
  final String id;
  final String sessionId;
  final String productId;
  final String productName;
  final String? productThumbnail;
  final int quantity;
  final int unitPrice;
  final int totalPrice;
  final int finalPrice;
  final String? couponCode;
  final int discountAmount;
  final String status;
  final String buyerName;
  final DateTime createdAt;

  const OrderModel({
    required this.id,
    required this.sessionId,
    required this.productId,
    required this.productName,
    this.productThumbnail,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.finalPrice,
    this.couponCode,
    required this.discountAmount,
    required this.status,
    required this.buyerName,
    required this.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> j) => OrderModel(
        id: j['id'] as String,
        sessionId: j['session_id'] as String? ?? '',
        productId: j['product_id'] as String? ?? '',
        productName: j['product_name'] as String? ?? '',
        productThumbnail: j['product_thumbnail'] as String?,
        quantity: (j['quantity'] as num).toInt(),
        unitPrice: (j['unit_price'] as num).toInt(),
        totalPrice: (j['total_price'] as num).toInt(),
        finalPrice: (j['final_price'] as num? ?? j['total_price'] as num).toInt(),
        couponCode: j['coupon_code'] as String?,
        discountAmount: (j['discount_amount'] as num? ?? 0).toInt(),
        status: j['status'] as String? ?? 'pending',
        buyerName: j['buyer_name'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
      );

  bool get isPending => status == 'pending';
  bool get isPaid => status == 'paid';
  bool get isCancelled => status == 'cancelled';
}
