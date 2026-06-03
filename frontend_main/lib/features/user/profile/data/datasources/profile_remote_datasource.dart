import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // [QUAN TRỌNG] Cần để lấy token
import 'package:flutter/foundation.dart'; // Thêm import cho debugPrint

// Import Models
import 'package:tropia_mobile_app_android/features/user/profile/data/models/notification_model.dart';
import '../models/user_profile_model.dart';
import '../models/address_model.dart';
import '../models/points_info_model.dart';
import '../models/point_history_model.dart';


class ProfileRemoteDataSource {
  final Dio client;

  ProfileRemoteDataSource({required this.client});

  // =========================================================
  // PHẦN 1: USER PROFILE (Giữ nguyên code của bạn)
  // =========================================================

  Future<UserProfileModel?> getUserProfile(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {"Authorization": "bearer $appToken"});

      final response = await client.get(
        "user-profile",
        queryParameters: {'user_id': userId},
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        return UserProfileModel.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      debugPrint("Lỗi lấy Profile: $e");
      return null;
    }
  }

  Future<bool> updateUserProfile(int userId, Map<String, dynamic> updateData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {
        "Authorization": "bearer $appToken",
        "Content-Type": "application/json",
      });

      final response = await client.post(
        "user-profile-update",
        queryParameters: {'user_id': userId},
        data: updateData,
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Lỗi cập nhật Profile: $e");
      return false;
    }
  }

  Future<bool> deleteAccount(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {
        "Authorization": "Bearer $appToken",
        "Content-Type": "application/json",
      });

      final response = await client.post(
        "delete-account",
        data: {"user_id": userId},
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Lỗi xóa tài khoản: $e");
      return false;
    }
  }

  // =========================================================
  // PHẦN 2: THÔNG TIN ĐIỂM & HẠNG (POINTS INFO) - API MỚI
  // =========================================================

  /// Lấy thông tin chi tiết điểm và hạng thành viên
  /// API: GET /api/points/info?user_id={userId}
  Future<PointsInfoModel?> getPointsInfo(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {"Authorization": "bearer $appToken"});

      final response = await client.get(
        "points/info",
        queryParameters: {'user_id': userId},
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        return PointsInfoModel.fromJson(response.data['data']);
      }
      return null;
    } catch (e) {
      debugPrint("Lỗi lấy Points Info: $e");
      return null;
    }
  }

  // =========================================================
  // PHẦN 2.1: LỊCH SỬ ĐIỂM (POINTS HISTORY)
  // =========================================================

  /// Lấy lịch sử biến động điểm
  /// API: GET /api/points/history?user_id={userId}&page={page}&limit={limit}
  Future<PointHistoryModel?> getPointsHistory({
    required int userId,
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {"Authorization": "bearer $appToken"});

      final response = await client.get(
        "points/history",
        queryParameters: {
          'user_id': userId,
          'page': page,
          'limit': limit,
        },
        options: options,
      );

      final isSuccess =
          response.data?['success'] == true || response.data?['Result'] == true;

      if (response.statusCode == 200 && isSuccess) {
        final data = response.data['data'] as Map<String, dynamic>?;
        if (data == null) return null;
        return PointHistoryModel.fromJson(data);
      }
      return null;
    } catch (e) {
      debugPrint("Lỗi lấy Points History: $e");
      return null;
    }
  }

  // =========================================================
  // PHẦN 3: ĐỊA CHỈ (ADDRESS) (Giữ nguyên code của bạn)
  // =========================================================

  Future<List<AddressModel>> getUserAddresses(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {"Authorization": "bearer $appToken"});

      final response = await client.get(
        "user-addresses",
        queryParameters: {'user_id': userId},
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        final List<dynamic> data = response.data['data'];
        return data.map((e) => AddressModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Lỗi lấy danh sách địa chỉ: $e");
      return [];
    }
  }

  Future<bool> addUserAddress(Map<String, dynamic> body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {
        "Authorization": "bearer $appToken",
        "Content-Type": "application/json",
      });

      final response = await client.post(
        "user-addresses",
        data: body,
        options: options,
      );

      if (response.statusCode == 200 &&
          (response.data['Result'] == true || response.data['status'] == 200)) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Lỗi thêm địa chỉ: $e");
      return false;
    }
  }

  Future<bool> deleteUserAddress(int addressId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {
        "Authorization": "bearer $appToken",
        "Content-Type": "application/json",
      });

      final response = await client.delete(
        "user/addresses-delete",
        data: {"address_id": addressId},
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("Lỗi xóa địa chỉ: $e");
      return false;
    }
  }

  // =========================================================
  // PHẦN 3: THÔNG BÁO (NOTIFICATION) - ĐÃ CẬP NHẬT CHUẨN
  // =========================================================

  Future<List<NotificationModel>> getNotifications({int page = 1, int limit = 20}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final fcmToken = await FirebaseMessaging.instance.getToken();
      
      // Lấy Token Authorization (nếu cần thiết cho API này)
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {"Authorization": "bearer $appToken"});

      if (userId == null) return [];

      // [UPDATE] Gọi API với đầy đủ tham số user_id & device_token
      final response = await client.get(
        'notifications', // Đảm bảo DioClient đã cấu hình BaseUrl đúng
        queryParameters: {
          'user_id': userId,
          'device_token': fcmToken,
          'page': page,
          'limit': limit
        },
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        // [UPDATE] Parse đúng key 'notifications' thay vì 'items'
        final List listRaw = response.data['data']['notifications'] ?? [];
        return listRaw.map((e) => NotificationModel.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      debugPrint("Lỗi tải thông báo: $e");
      return [];
    }
  }

  // Hàm lấy số thông báo chưa đọc
  Future<int> getUnreadCount() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final fcmToken = await FirebaseMessaging.instance.getToken();
      
      final appToken = prefs.getString('app_auth_token') ?? '';
      final options = Options(headers: {"Authorization": "bearer $appToken"});

      if (userId == null) return 0;

      final response = await client.get(
        'notifications',
        queryParameters: {
          'user_id': userId,
          'device_token': fcmToken,
          'page': 1,
          'limit': 1, // Chỉ lấy 1 để tối ưu, nhưng vẫn có unread_count
        },
        options: options,
      );

      if (response.statusCode == 200 && response.data['Result'] == true) {
        return response.data['data']['unread_count'] ?? 0;
      }
      return 0;
    } catch (e) {
      debugPrint("Lỗi lấy unread count: $e");
      return 0;
    }
  }

  Future<bool> markAsRead(String notificationId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      final appToken = prefs.getString('app_auth_token') ?? '';

      final options = Options(
        headers: {
          "Authorization": "bearer $appToken",
          "Content-Type": "application/json",
        },
      );
      
      // Nếu id là 'all' thì bỏ qua (hoặc xử lý riêng nếu API hỗ trợ)
      if (notificationId == 'all') return true; 

      debugPrint("📡 Marking notification $notificationId as read for user $userId");

      // [UPDATE] Dùng POST và endpoint notification-mark-read
      final response = await client.post(
        'notification-mark-read',
        data: {
          'notification_id': notificationId,
          'user_id': userId,
        },
        options: options,
      );
      
      debugPrint("📡 Mark read response: ${response.statusCode} - ${response.data}");

      // API trả về statusCode 200 là thành công
      if (response.statusCode == 200) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint("❌ Lỗi đọc thông báo: $e");
      return false;
    }
  }
}
