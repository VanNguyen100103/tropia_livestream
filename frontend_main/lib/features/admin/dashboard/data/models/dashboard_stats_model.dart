class DashboardStatsModel {
  final StatItem revenue;
  final StatItem orders;
  final StatItem customers;
  final StatItem products;

  DashboardStatsModel({
    required this.revenue,
    required this.orders,
    required this.customers,
    required this.products,
  });

  factory DashboardStatsModel.fromJson(Map<String, dynamic> json) {
    return DashboardStatsModel(
      // Thêm kiểm tra null cho từng object con
      revenue: StatItem.fromJson(json['revenue'] ?? {}),
      orders: StatItem.fromJson(json['orders'] ?? {}),
      customers: StatItem.fromJson(json['customers'] ?? {}),
      products: StatItem.fromJson(json['products'] ?? {}),
    );
  }
}

class StatItem {
  final num value;
  final String label;
  final num? growth;
  final num? increase;
  final String? statusText;

  StatItem({
    required this.value,
    required this.label,
    this.growth,
    this.increase,
    this.statusText,
  });

  factory StatItem.fromJson(Map<String, dynamic> json) {
    return StatItem(
      // [QUAN TRỌNG] Ép kiểu an toàn: (json['value'] as num?)
      value: (json['value'] as num?) ?? 0,
      label: json['label']?.toString() ?? '',
      growth: (json['growth'] as num?)?.toDouble(),
      increase: (json['increase'] as num?)?.toDouble(),
      statusText: json['status_text']?.toString(),
    );
  }
}