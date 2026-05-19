// =============================================================================
// app_config.dart – tập trung tất cả config môi trường
// =============================================================================

import 'package:flutter/foundation.dart' show kIsWeb;

class AppConfig {
  AppConfig._();

  // ── Agora ────────────────────────────────────────────────────────────────────
  static const agoraAppId = 'YOUR_AGORA_APP_ID';

  // ── Backend URL ──────────────────────────────────────────────────────────────
  // Web (Chrome dev)  : http://localhost:3000  – browser gọi cùng máy
  // Android device    : http://192.168.4.1:3000 – IP LAN của máy tính
  // Android emulator  : http://10.0.2.2:3000
  static String get backendUrl {
    if (kIsWeb) return 'http://localhost:3000';
    return 'http://192.168.4.2:3000';
  }

  static String get apiAuth       => '$backendUrl/api/auth';
  static String get apiLive       => '$backendUrl/api/live';
  static String get apiOrders     => '$backendUrl/api/orders';
  static String get apiProducts   => '$backendUrl/api/products';
  static String get apiShops      => '$backendUrl/api/shops';
  static String get apiCategories => '$backendUrl/api/categories';
  static String get apiPayment    => '$backendUrl/api/payment';
  static String get apiCoupons    => '$backendUrl/api/coupons';
  static String get apiUpload     => '$backendUrl/api/upload';
  static String get apiToken      => '$backendUrl/api/token';
}
