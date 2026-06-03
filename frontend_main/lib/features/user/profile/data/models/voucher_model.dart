class VoucherModel {
  final String id;
  final String code;
  final String title;
  final String description;
  final String discountType; // 'fixed_amount', 'percent', 'shipping'
  final double discountValue;
  final double minOrderValue;
  final double? maxDiscountAmount;
  final String endTime;
  final String status;
  final String applyButtonState; // 'enable' | 'disable'

  VoucherModel({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minOrderValue,
    this.maxDiscountAmount,
    required this.endTime,
    required this.status,
    required this.applyButtonState,
  });

  factory VoucherModel.fromJson(Map<String, dynamic> json) {
    return VoucherModel(
      id: json['id'] ?? '',
      code: json['code'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      discountType: json['discount_type'] ?? 'fixed_amount',
      // Xử lý an toàn cho số (int hoặc double)
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      minOrderValue: (json['min_order_value'] as num?)?.toDouble() ?? 0,
      maxDiscountAmount: (json['max_discount_amount'] as num?)?.toDouble(),
      endTime: json['end_time'] ?? '',
      status: json['status'] ?? 'active',
      applyButtonState: json['apply_button_state'] ?? 'disable',
    );
  }
}