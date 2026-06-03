import 'package:tropia_mobile_app_android/features/user/profile/data/models/notification_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/point_history_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/points_info_model.dart';

import '../datasources/profile_remote_datasource.dart';
import '../models/user_profile_model.dart';

class ProfileRepository {
  final ProfileRemoteDataSource remoteDataSource;

  ProfileRepository({required this.remoteDataSource});

  Future<UserProfileModel?> getUserProfile(int userId) async {
    return await remoteDataSource.getUserProfile(userId);
  }

  Future<bool> updateUserProfile(int userId, Map<String, dynamic> data) async {
    return await remoteDataSource.updateUserProfile(userId, data);
  }

  Future<bool> deleteAccount(int userId) async {
    return await remoteDataSource.deleteAccount(userId);
  }

  /// Lấy thông tin chi tiết điểm và hạng thành viên
  Future<PointsInfoModel?> getPointsInfo(int userId) async {
    return await remoteDataSource.getPointsInfo(userId);
  }

  /// Lấy lịch sử biến động điểm
  Future<PointHistoryModel?> getPointsHistory({
    required int userId,
    int page = 1,
    int limit = 10,
  }) async {
    return await remoteDataSource.getPointsHistory(
      userId: userId,
      page: page,
      limit: limit,
    );
  }

  Future<List<NotificationModel>> getNotifications({int page = 1, int limit = 20}) async {
    return await remoteDataSource.getNotifications(page: page, limit: limit);
  }

  Future<int> getUnreadCount() async {
    return await remoteDataSource.getUnreadCount();
  }

  Future<bool> markAsRead(String notificationId) async {
    return await remoteDataSource.markAsRead(notificationId);
  }
}