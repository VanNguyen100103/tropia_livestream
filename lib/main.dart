// =============================================================================
// main.dart
// =============================================================================
// Entry point của ứng dụng Tropia.
//
// Chức năng:
//   1. Khởi tạo AppLogger (ghi log từ ngay đầu app)
//   2. Cấu hình MaterialApp với theme Tropia
//   3. Đặt MainScreen làm home (có bottom nav 5 tab)
//   4. Xử lý lỗi Flutter framework không được catch
//
// THỨ TỰ KHỞI TẠO:
//   main() → WidgetsFlutterBinding.ensureInitialized()
//          → AppLogger.init()
//          → runApp(TropiaApp())
//          → MaterialApp → MainScreen → BottomNav
//
// DEBUG vs RELEASE:
//   - Trong debug: Logger ghi ra console với màu sắc
//   - Trong release: Logger im lặng (SilentFilter)
// =============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/features/user/widgets/google_auth_handler.dart';
import 'package:tropia/core/theme/app_theme.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/main/screens/main_screen.dart';
import 'package:tropia/features/live/providers/live_provider.dart';
import 'package:tropia/features/user/providers/user_provider.dart';
import 'package:tropia/features/cart/providers/cart_provider.dart';
import 'package:tropia/features/shop/providers/shop_provider.dart';

/// Entry point của ứng dụng.
Future<void> main() async {
  // 1. Đảm bảo Flutter binding đã được khởi tạo trước khi
  //    gọi bất kỳ platform channel nào
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Khởi tạo logger sớm nhất có thể
  AppLogger.init();
  AppLogger.logInfo('main', 'Tropia app starting...');

  // 3. Khởi tạo AuthService – đọc JWT đã lưu từ lần trước
  try {
    await AuthService.instance.initialize();
    AppLogger.logInfo('main', 'AuthService initialized – signed in: ${AuthService.instance.isSignedIn}');
  } catch (e) {
    AppLogger.logError('main', 'AuthService init failed', e, null);
  }

  // 5. Cấu hình hướng màn hình
  //    - Portrait only (trừ màn hình live full-screen)
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // 4. Cấu hình status bar style (light content trên nền tối)
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
    ),
  );

  // 5. Bắt lỗi Flutter framework không được catch
  FlutterError.onError = (FlutterErrorDetails details) {
    AppLogger.logError(
      'FlutterError',
      details.exceptionAsString(),
      details.exception,
      details.stack,
    );
    // Trong release, có thể gửi lên Crashlytics/Sentry tại đây
  };

  // 6. Chạy app
  runApp(const TropiaApp());
  AppLogger.logInfo('main', 'TropiaApp started successfully');
}

// ─────────────────────────────────────────────────────────────────────────────
// TropiaApp – Root Widget
// ─────────────────────────────────────────────────────────────────────────────

/// Root widget của ứng dụng Tropia.
///
/// Bọc [MaterialApp] với:
///   - Theme Tropia (xanh lá + cam)
///   - Không có debug banner
///   - Locale tiếng Việt (cho intl/timeago)
///   - Tự động xử lý text scaling
class TropiaApp extends StatelessWidget {
  const TropiaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => LiveProvider()),
        ChangeNotifierProvider(create: (_) => CartProvider()),
        ChangeNotifierProvider(create: (_) => ShopProvider()),
      ],
      child: MaterialApp(
      // ── Tên hiển thị (dùng trong task manager, split-screen)
      title: 'Tropia',

      // ── Tắt banner "Debug" góc phải trên
      debugShowCheckedModeBanner: false,

      // ── Theme
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.light, // Luôn dùng light theme

      // ── Locale (tiếng Việt)
      // Khi tích hợp intl đầy đủ, thêm localizationsDelegates và supportedLocales
      // locale: const Locale('vi', 'VN'),

      // ── Màn hình home
      home: const GoogleAuthHandler(child: MainScreen()),

      // ── Handle payment redirect từ MoMo/ZaloPay/VNPay
      onGenerateRoute: (settings) {
        final uri = Uri.tryParse(settings.name ?? '');
        if (uri != null && uri.path == '/payment-result') {
          final status  = uri.queryParameters['status'] ?? 'failed';
          final orderId = uri.queryParameters['orderId'] ?? '';
          final method  = uri.queryParameters['method'] ?? '';
          return MaterialPageRoute<void>(
            builder: (_) => _PaymentResultScreen(
              success: status == 'success',
              orderId: orderId,
              method:  method,
            ),
          );
        }
        return null;
      },

      // ── Builder: bọc thêm MediaQuery để giới hạn text scale
      //    (tránh UI vỡ khi người dùng tăng cỡ chữ hệ thống quá lớn)
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            // Giới hạn text scale từ 0.8x đến 1.2x
            textScaler: TextScaler.linear(
              MediaQuery.of(context).textScaler.scale(1.0).clamp(0.8, 1.2),
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    ),
    );
  }
}

// ── Payment result screen (sau khi MoMo/ZaloPay/VNPay redirect về) ────────────

class _PaymentResultScreen extends StatelessWidget {
  const _PaymentResultScreen({
    required this.success,
    required this.orderId,
    required this.method,
  });
  final bool success;
  final String orderId;
  final String method;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                success ? Icons.check_circle : Icons.cancel,
                size: 80,
                color: success ? const Color(0xFF2E7D32) : Colors.red,
              ),
              const SizedBox(height: 24),
              Text(
                success ? 'Thanh toán thành công!' : 'Thanh toán thất bại',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
              ),
              if (method.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Phương thức: ${method.toUpperCase()}',
                  style: const TextStyle(color: Colors.grey, fontSize: 14),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute<void>(
                      builder: (_) => const GoogleAuthHandler(child: MainScreen()),
                    ),
                    (_) => false,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Về trang chủ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
