class OrderModel {
  final String id;
  final String customerName;
  final String address;
  final double totalAmount;
  final String status;
  final String createdAt;

  OrderModel({
    required this.id,
    required this.customerName,
    required this.address,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] ?? '',
      customerName: json['customer_name'] ?? 'Khách lẻ',
      address: json['address'] ?? '',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0.0,
      status: json['status'] ?? 'pending',
      createdAt: json['created_at'] ?? '',
    );
  }
}