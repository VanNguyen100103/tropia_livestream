class RewardItemModel {
  final int id;
  final String title;
  final int pointCost;
  final bool canRedeem;

  RewardItemModel({
    required this.id,
    required this.title,
    required this.pointCost,
    required this.canRedeem,
  });

  factory RewardItemModel.fromJson(Map<String, dynamic> json) {
    return RewardItemModel(
      id: _toInt(json['id']),
      title: (json['title'] ?? '').toString(),
      pointCost: _toInt(json['point_cost']),
      canRedeem: _toBool(json['can_redeem']),
    );
  }
}

class RewardsListModel {
  final List<RewardItemModel> rewards;
  final int userPoints;

  RewardsListModel({
    required this.rewards,
    required this.userPoints,
  });

  factory RewardsListModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final rewardsJson = (data['rewards'] as List?) ?? [];

    return RewardsListModel(
      rewards: rewardsJson
          .whereType<Map<String, dynamic>>()
          .map(RewardItemModel.fromJson)
          .toList(),
      userPoints: _toInt(data['user_points']),
    );
  }
}

class RedeemResultModel {
  final bool success;
  final String message;
  final String voucherCode;
  final int pointsRemaining;

  RedeemResultModel({
    required this.success,
    required this.message,
    required this.voucherCode,
    required this.pointsRemaining,
  });

  factory RedeemResultModel.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? {};

    return RedeemResultModel(
      success: _toBool(json['success']),
      message: (json['message'] ?? '').toString(),
      voucherCode: (data['voucher_code'] ?? '').toString(),
      pointsRemaining: _toInt(data['points_remaining']),
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
