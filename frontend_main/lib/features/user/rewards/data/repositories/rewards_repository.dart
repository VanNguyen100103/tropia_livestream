import '../datasources/rewards_remote_datasource.dart';
import '../models/rewards_models.dart';

class RewardsRepository {
  final RewardsRemoteDataSource remoteDataSource;

  RewardsRepository({required this.remoteDataSource});

  Future<RewardsListModel?> getRewardsList({required int userId}) async {
    return await remoteDataSource.getRewardsList(userId: userId);
  }

  Future<RedeemResultModel?> redeemReward({
    required int userId,
    required int rewardId,
  }) async {
    return await remoteDataSource.redeemReward(
      userId: userId,
      rewardId: rewardId,
    );
  }
}
