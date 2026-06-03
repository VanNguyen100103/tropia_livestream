class OrderDetailModel {
  final String id;
  final String customerName;
  final String address;
  final double totalAmount;
  final String status;
  final String createdAt;
  final List<OrderProductModel> products;

  OrderDetailModel({
    required this.id,
    required this.customerName,
    required this.address,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    required this.products,
  });

  factory OrderDetailModel.fromJson(Map<String, dynamic> json) {
    var list = json['products'] as List? ?? [];
    List<OrderProductModel> productsList =
        list.map((i) => OrderProductModel.fromJson(i)).toList();

    return OrderDetailModel(
      id: json['id'] ?? '',
      customerName: json['customer_name'] ?? '',
      address: json['address'] ?? '',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] ?? '',
      products: productsList,
    );
  }
}

class OrderProductModel {
  final String id;
  final String name;
  final int quantity;
  final double price;
  final double total;
  final String image;

  OrderProductModel({
    required this.id,
    required this.name,
    required this.quantity,
    required this.price,
    required this.total,
    required this.image,
  });

  factory OrderProductModel.fromJson(Map<String, dynamic> json) {
    return OrderProductModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      total: (json['total'] as num?)?.toDouble() ?? 0.0,
      image: json['image']?.toString() ?? '0',
    );
  }
}