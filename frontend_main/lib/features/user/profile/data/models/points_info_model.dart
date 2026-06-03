/// Model chứa thông tin chi tiết điểm và hạng thành viên
/// API: GET /api/points/info?user_id={userId}
library;
import 'package:intl/intl.dart';

class PointsInfoModel {
  final String userId;
  final int currentPoints;
  final String currentRank;
  final double multiplier;
  final double monthlySpending;
  final String nextRank;
  final int pointsToNextRank;
  final double spendingToNextRank;

  PointsInfoModel({
    required this.userId,
    required this.currentPoints,
    required this.currentRank,
    required this.multiplier,
    required this.monthlySpending,
    required this.nextRank,
    required this.pointsToNextRank,
    required this.spendingToNextRank,
  });

  factory PointsInfoModel.fromJson(Map<String, dynamic> json) {
    return PointsInfoModel(
      userId: json['user_id']?.toString() ?? '',
      currentPoints: (json['current_points'] as num?)?.toInt() ?? 0,
      currentRank: json['current_rank'] ?? 'Member',
      multiplier: (json['multiplier'] as num?)?.toDouble() ?? 1.0,
      monthlySpending: (json['monthly_spending'] as num?)?.toDouble() ?? 0,
      nextRank: json['next_rank'] ?? '',
      pointsToNextRank: (json['points_to_next_rank'] as num?)?.toInt() ?? 0,
      spendingToNextRank:
          (json['spending_to_next_rank'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'current_points': currentPoints,
      'current_rank': currentRank,
      'multiplier': multiplier,
      'monthly_spending': monthlySpending,
      'next_rank': nextRank,
      'points_to_next_rank': pointsToNextRank,
      'spending_to_next_rank': spendingToNextRank,
    };
  }

  /// Chuyển đổi hạng sang tiếng Việt
  String get currentRankVietnamese {
    switch (currentRank.toLowerCase()) {
      case 'member':
        return 'Thành viên';
      case 'silver':
        return 'Bạc';
      case 'gold':
        return 'Vàng';
      case 'platinum':
        return 'Bạch kim';
      case 'diamond':
        return 'Kim cương';
      default:
        return currentRank;
    }
  }

  /// Chuyển đổi hạng tiếp theo sang tiếng Việt
  String get nextRankVietnamese {
    switch (nextRank.toLowerCase()) {
      case 'member':
        return 'Thành viên';
      case 'silver':
        return 'Bạc';
      case 'gold':
        return 'Vàng';
      case 'platinum':
        return 'Bạch kim';
      case 'diamond':
        return 'Kim cương';
      default:
        return nextRank;
    }
  }

  /// Format số tiền chi tiêu tháng
  String get formattedMonthlySpending {
    return '${_formatCurrency(monthlySpending)} đ';
  }

  /// Format số tiền chi tiêu tháng — HIỂN THỊ DẠNG ĐẦY ĐỦ (KHÔNG VIẾT TẮT)
  String get formattedMonthlySpendingFull {
    final f = NumberFormat.decimalPattern('vi_VN');
    final value = monthlySpending.round();
    return '${f.format(value)} đ';
  }

  /// Format số tiền cần để lên hạng
  String get formattedSpendingToNextRank {
    return '${_formatCurrency(spendingToNextRank)} đ';
  }

  /// Format số tiền cần để lên hạng — HIỂN THỊ DẠNG ĐẦY ĐỦ (KHÔNG VIẾT TẮT)
  String get formattedSpendingToNextRankFull {
    final f = NumberFormat.decimalPattern('vi_VN');
    final value = spendingToNextRank.round();
    return '${f.format(value)} đ';
  }

  /// Helper format tiền tệ
  String _formatCurrency(double amount) {
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(amount % 1000000 == 0 ? 0 : 1)}M';
    } else if (amount >= 1000) {
      return '${(amount / 1000).toStringAsFixed(amount % 1000 == 0 ? 0 : 1)}K';
    }
    return amount.toStringAsFixed(0);
  }
}
