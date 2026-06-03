// lib/core/constants/api_constants.dart
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiConstants {
  static String? _tryGetEnv(String key) {
    try {
      return dotenv.env[key];
    } catch (_) {
      return null;
    }
  }

  // 1. Phải dùng "static String get" thay vì "const" vì dotenv load lúc chạy app

  // --- BASE URL ---

  // [OLD] Local API (Android Emulator) - Giữ lại để backup
  // static String get baseUrl =>
  //    dotenv.env['BASE_URL'] ?? 'http://10.0.2.2/API/web/index.php?r=api/';

  // [NEW] Deploy API (Server thật)
  static String get baseUrl =>
      _tryGetEnv('BASE_URL') ??
      'http://tropia.thienhaisoft.com/index.php?r=api/';

  // --- IMAGE URL ---

  // [OLD] Local Image
  // static String get imageBaseUrl => dotenv.env['IMAGE_URL'] ?? '';

  // [NEW] Deploy Image (Thường là root domain chứa folder uploads)
  static String get imageBaseUrl =>
      _tryGetEnv('IMAGE_URL') ?? 'http://tropia.thienhaisoft.com/';

  // --- ENDPOINTS ---
  static const String categories = "categories";
  static const String banners = "banners";
  static const String products = "products";
  static const String login = "auth/login";
  static const String flashSale = "flash-sale";
  static const String readyToCook = "ready-to-cook";
  static const String featuredCategories = "featured-categories";

  static const String dailyMarket = "daily-market";
  static const String categoryDetails = "category-details";
  static const String search = "search";
  static const String productsSearch = "products-search";
  static const String productsStatusDetail = "products-status-detail";
}
