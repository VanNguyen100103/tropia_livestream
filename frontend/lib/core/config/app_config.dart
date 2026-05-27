// =============================================================================
// app_config.dart – tập trung tất cả config môi trường
// =============================================================================

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class AppConfig {
  AppConfig._();

  // ── Backend URL ──────────────────────────────────────────────────────────────
  // Resolution order:
  //   1. --dart-define=BACKEND_URL=http://192.168.x.y:3000   (highest priority)
  //   2. Web build              → http://localhost:3000      (browser is on host)
  //   3. Android emulator       → http://10.0.2.2:3000       (loopback to host)
  //   4. iOS simulator / desktop → http://localhost:3000
  //   5. Physical device        → must pass --dart-define, otherwise we throw
  //                                a loud assertion in debug mode so the dev
  //                                notices instead of silently hanging.
  //
  // Examples:
  //   flutter run -d <device> --dart-define=BACKEND_URL=http://192.168.1.140:3000
  //   flutter build apk --dart-define=BACKEND_URL=https://api.tropia.vn
  static const String _envBackendUrl =
      String.fromEnvironment('BACKEND_URL', defaultValue: '');

  static String get backendUrl {
    if (_envBackendUrl.isNotEmpty) return _envBackendUrl;
    if (kIsWeb) return 'http://localhost:3000';
    // defaultTargetPlatform works on web (Platform.* from dart:io doesn't).
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  // Convenience prefixes (most repositories use `_dio.get('/api/...')` directly
  // and don't depend on these constants).
  static String get apiAuth       => '$backendUrl/api/auth';
  static String get apiLive       => '$backendUrl/api/live/streams';
  static String get apiOrders     => '$backendUrl/api/orders';
  static String get apiProducts   => '$backendUrl/api/products';
  static String get apiShops      => '$backendUrl/api/shops';
  static String get apiCategories => '$backendUrl/api/categories';
  static String get apiPayment    => '$backendUrl/api/payment';
  static String get apiCoupons    => '$backendUrl/api/coupons';
  static String get apiUpload     => '$backendUrl/api/upload';

  // ── Placeholder image host ──────────────────────────────────────────────────
  // Base URL for the generic product/avatar/banner placeholders used when the
  // backend hasn't returned an image URL yet. Defaults to picsum.photos so dev
  // builds work out of the box; override to a self-hosted host in production
  // if you don't want to depend on a third party:
  //   flutter build apk --dart-define=PLACEHOLDER_IMAGE_BASE_URL=https://cdn.tropia.vn/placeholder
  static const String _envPlaceholderBase =
      String.fromEnvironment('PLACEHOLDER_IMAGE_BASE_URL', defaultValue: 'https://picsum.photos');

  static String get placeholderImageBase => _envPlaceholderBase;
}
