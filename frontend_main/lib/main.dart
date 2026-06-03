import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';

// [1] THAY ĐỔI IMPORT:
// Bỏ AuthPage (vì SplashPage sẽ lo việc gọi nó)
// import 'package:tropia_mobile_app_android/features/user/auth/presentation/auth_page.dart'; 
import 'package:tropia_mobile_app_android/features/user/intro/splash_page.dart'; // <--- Import cái này

// Import Service
import 'package:tropia_mobile_app_android/core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Load .env
  try {
    await dotenv.load(fileName: ".env");
    debugPrint("✅ Đã load .env thành công");
  } catch (e) {
    debugPrint("⚠️ Lỗi load .env: $e");
  }

  // 2. Setup Firebase (lightweight only)
  try {
    await Firebase.initializeApp();

    // A. Background Handler
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // B. Logging
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("--------------------------------------------------");
      debugPrint("📩 [MAIN] ĐÃ NHẬN TIN NHẮN KHI APP ĐANG MỞ:");
      debugPrint("   Tiêu đề: ${message.notification?.title}");
      debugPrint("   Nội dung: ${message.notification?.body}");
      debugPrint("   Data: ${message.data}");
      debugPrint("--------------------------------------------------");
    });

    debugPrint("🔥 App đã sẵn sàng nhận thông báo!");
  } catch (e) {
    debugPrint("❌ Lỗi khởi tạo: $e");
  }

  // 3. Chạy App trước để tránh ANR khi init dịch vụ nặng
  runApp(const MyApp());

  // 4. Khởi tạo notification service bất đồng bộ sau khi UI đã lên
  unawaited(_initializeNotificationServiceSafely());
}

Future<void> _initializeNotificationServiceSafely() async {
  try {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await NotificationService().initialize();
  } catch (e) {
    debugPrint("❌ Lỗi NotificationService init: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cửa Hàng Tiện Lợi',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.green),
        useMaterial3: true,
      ),
      
      // [2] QUAN TRỌNG NHẤT: Đổi thành SplashPage để kích hoạt Auto Login
      home: const SplashPage(), 
      // -----------------------------------------------------------------

      builder: (context, child) {
        Widget errorWidget = child ??
            const Scaffold(
              body: Center(child: Text('Lỗi: Không thể tải widget')),
            );

        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.0)),
          child: errorWidget,
        );
      },
    );
  }
}
