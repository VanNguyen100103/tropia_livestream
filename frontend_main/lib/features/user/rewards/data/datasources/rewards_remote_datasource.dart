import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/rewards_models.dart';

class RewardsRemoteDataSource {
  final Dio client;

  RewardsRemoteDataSource({required this.client});

  Future<RewardsListModel?> getRewardsList({required int userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('app_auth_token') ?? '';

      final response = await client.get(
        'rewards/list',
        queryParameters: {'user_id': userId},
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
          },
        ),
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return RewardsListModel.fromJson(response.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Lỗi lấy danh sách đổi thưởng: $e');
    }

    return null;
  }

  Future<RedeemResultModel?> redeemReward({
    required int userId,
    required int rewardId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('app_auth_token') ?? '';

      final response = await client.post(
        'points/redeem',
        data: {
          'user_id': userId.toString(),
          'reward_id': rewardId,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
        return RedeemResultModel.fromJson(response.data as Map<String, dynamic>);
      }
    } catch (e) {
      debugPrint('Lỗi đổi điểm: $e');
    }

    return null;
  }
}
