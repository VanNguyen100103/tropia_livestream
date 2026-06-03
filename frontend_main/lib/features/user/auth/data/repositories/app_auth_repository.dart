import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../datasources/app_auth_remote_datasource.dart';
import '../models/app_token_model.dart';

class AppAuthRepository {
  final AppAuthRemoteDataSource remoteDataSource;

  AppAuthRepository({required this.remoteDataSource});

  // Hàm này vừa gọi API, vừa lưu token
  Future<String?> authenticateApp() async {
    try {
      // 1. Kiểm tra xem đã có token chưa (Optional: Nếu muốn caching)
      // final prefs = await SharedPreferences.getInstance();
      // final savedToken = prefs.getString('app_auth_token');
      // if (savedToken != null) return savedToken;

      // 2. Gọi API mới
      final AppTokenModel? model = await remoteDataSource.getAuthorToken();

      if (model != null && model.token.isNotEmpty) {
        // 3. Lưu Token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('app_auth_token', model.token);

        if (kDebugMode) {
          debugPrint("Đã lưu App Token mới");
        }
        return model.token;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Hàm chỉ lấy token đã lưu (Dùng cho Cart/Profile load dữ liệu)
  Future<String?> getSavedToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('app_auth_token');
  }
}
