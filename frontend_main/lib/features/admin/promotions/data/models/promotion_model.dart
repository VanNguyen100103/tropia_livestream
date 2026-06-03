class PromotionModel {
  final String id;
  final String title;
  final String description;
  final double discountValue;
  final double minOrderValue;
  final String startDate;
  final String endDate;
  final String status;

  PromotionModel({
    required this.id,
    required this.title,
    required this.description,
    required this.discountValue,
    required this.minOrderValue,
    required this.startDate,
    required this.endDate,
    required this.status,
  });

  factory PromotionModel.fromJson(Map<String, dynamic> json) {
    return PromotionModel(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0.0,
      minOrderValue: (json['min_order_value'] as num?)?.toDouble() ?? 0.0,
      startDate: json['start_date'] ?? '',
      endDate: json['end_date'] ?? '',
      status: json['status'] ?? 'inactive',
    );
  }
}