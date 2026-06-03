class ChartDataModel {
  final String month;
  final double revenue;

  ChartDataModel({required this.month, required this.revenue});

  factory ChartDataModel.fromJson(Map<String, dynamic> json) {
    // Xử lý chuỗi "T1" -> lấy số 1 (nếu cần sort hoặc tính toán)
    // Ở đây ta giữ nguyên String month để hiển thị trục X
    return ChartDataModel(
      month: json['month'] ?? '',
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0.0,
    );
  }
}