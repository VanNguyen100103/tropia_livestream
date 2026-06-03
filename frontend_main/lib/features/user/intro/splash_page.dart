import 'package:flutter/material.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/auth/presentation/auth_page.dart';
import 'package:tropia_mobile_app_android/features/user/dashboard/presentation/dashboard_page.dart';
import 'package:tropia_mobile_app_android/features/admin/shared/widgets/admin_scaffold.dart';
import 'package:tropia_mobile_app_android/core/services/notification_service.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    _checkAutoLogin();
  }

  Future<void> _checkAutoLogin() async {
    // 1. Chờ 1 chút (để Logo hiện lên cho đẹp, tránh nháy màn hình)
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();
    
    // 2. Lấy Token User (Token phiên làm việc)
    final userSessionToken = prefs.getString('user_session_token');
    final userId = prefs.getInt('user_id');
    final role = prefs.getString('role');

    // 3. Logic kiểm tra
    if (userSessionToken != null && userSessionToken.isNotEmpty && userId != null) {
      // ✅ TÌM THẤY PHIÊN ĐĂNG NHẬP CŨ
      debugPrint("🚀 Auto Login: Khôi phục phiên cho User $userId");

      // A. Nạp Token User vào Header
      DioClient().dio.options.headers["Authorization"] = "Bearer $userSessionToken";
      
      // B. Báo Notification Service online ở nền để không chặn UI
      unawaited(NotificationService().updateUserId(userId));

      // C. Vào thẳng Dashboard (hoặc Admin)
      _navigateToHome(role);
      
    } else {
      // ❌ KHÔNG CÓ PHIÊN ĐĂNG NHẬP -> Về trang Login
      debugPrint("⚠️ Không có phiên đăng nhập -> Vào AuthPage");
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AuthPage()),
      );
    }
  }

  void _navigateToHome(String? role) {
    if (role == 'admin' || role == 'superadmin') {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const AdminScaffold()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => DashboardPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Màu nền trùng với màn hình chờ hệ thống
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo App
            Image.asset(
              'assets/images/logo.png',
              width: 150, height: 150,
              // Nếu chưa load được ảnh thì hiện icon tạm
              errorBuilder: (_,_,_) => const Icon(Icons.store, size: 100, color: Colors.green),
            ),
            const SizedBox(height: 20),
            // Vòng tròn xoay xoay báo hiệu đang xử lý
            const CircularProgressIndicator(color: Colors.green),
          ],
        ),
      ),
    );
  }
}
