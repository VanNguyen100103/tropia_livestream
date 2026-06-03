class PointsPreviewModel {
  final bool success;
  final int orderAmount;
  final int earnedPoints;
  final String currentRank;

  PointsPreviewModel({
    required this.success,
    required this.orderAmount,
    required this.earnedPoints,
    required this.currentRank,
  });

  factory PointsPreviewModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    return PointsPreviewModel(
      success: _toBool(json['success'] ?? json['Result']),
      orderAmount: _toInt(data['order_amount']),
      earnedPoints: _toInt(data['earned_points']),
      currentRank: (data['current_rank'] ?? '').toString(),
    );
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _toBool(dynamic value) {
  if (value is bool) return value;
  if (value is int) return value == 1;
  final str = value?.toString().toLowerCase() ?? '';
  return str == 'true' || str == '1';
}
