import 'dart:io';

import 'package:dio/dio.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';

const _tag = 'UploadRepository';

/// Upload client for Tropia's Go backend, which stores files on Cloudflare R2.
///
/// All endpoints return:
///   - single-file:  { "url": "https://pub-<hash>.r2.dev/<key>", "key": "<key>" }
///   - multi-file:   { "urls": [ "https://...", ... ] }
///
/// 5 MB per file, jpg/png/webp only (enforced server-side).
class UploadRepository {
  UploadRepository._();
  static final instance = UploadRepository._();

  Dio get _dio => AuthService.instance.authorizedDio();

  // ── Avatar ────────────────────────────────────────────────────────────────

  /// POST /api/upload/avatar — any authenticated user.
  /// Form: `image` (file).  Response: `{ url, key }`.
  Future<String> uploadAvatar(File file) async {
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(file.path, filename: 'avatar.jpg'),
    });
    final res = await _dio.post('/api/upload/avatar', data: form);
    AppLogger.logInfo(_tag, 'Avatar uploaded');
    return (res.data as Map<String, dynamic>)['url'] as String;
  }

  // ── Product images ────────────────────────────────────────────────────────

  /// POST /api/upload/product — seller/admin only.
  /// Form: `product_id`, `images[]` (up to 10).  Response: `{ urls: [...] }`.
  Future<List<String>> uploadProductImages(String productId, List<File> files) async {
    final form = FormData.fromMap({
      'product_id': productId,
      'images': await Future.wait(
        files.map((f) => MultipartFile.fromFile(f.path, filename: f.uri.pathSegments.last)),
      ),
    });
    final res = await _dio.post('/api/upload/product', data: form);
    final urls = ((res.data as Map<String, dynamic>)['urls'] as List).cast<String>();
    AppLogger.logInfo(_tag, 'Uploaded ${urls.length} product images');
    return urls;
  }

  // ── Variant images ────────────────────────────────────────────────────────

  /// POST /api/upload/variant — seller/admin only.
  /// Form: `variant_id`, `images[]` (up to 5).  Response: `{ urls: [...] }`.
  Future<List<String>> uploadVariantImages(String variantId, List<File> files) async {
    final form = FormData.fromMap({
      'variant_id': variantId,
      'images': await Future.wait(
        files.map((f) => MultipartFile.fromFile(f.path, filename: f.uri.pathSegments.last)),
      ),
    });
    final res = await _dio.post('/api/upload/variant', data: form);
    return ((res.data as Map<String, dynamic>)['urls'] as List).cast<String>();
  }

  // ── Shop banner ───────────────────────────────────────────────────────────

  /// POST /api/upload/shop — seller/admin only.
  /// Form: `shop_id`, `image`.  Response: `{ url, key }`.
  Future<String> uploadShopBanner(String shopId, File file) async {
    final form = FormData.fromMap({
      'shop_id': shopId,
      'image':   await MultipartFile.fromFile(file.path, filename: 'banner.jpg'),
    });
    final res = await _dio.post('/api/upload/shop', data: form);
    return (res.data as Map<String, dynamic>)['url'] as String;
  }

  // ── Shop logo (avatar) ──────────────────────────────────────────────────────

  /// POST /api/upload/shop-logo — seller/admin only.
  /// Form: `shop_id`, `image`. Backend đẩy ảnh lên R2 **và** lưu URL vào
  /// `shops.logo_url` ngay trong cùng request, rồi trả `{ url, key }`. Nhờ đó
  /// avatar trên thẻ/clip của shop (shop_avatar = logo_url) cập nhật luôn.
  Future<String> uploadShopLogo(String shopId, File file) async {
    final form = FormData.fromMap({
      'shop_id': shopId,
      'image':   await MultipartFile.fromFile(file.path, filename: 'logo.jpg'),
    });
    final res = await _dio.post('/api/upload/shop-logo', data: form);
    AppLogger.logInfo(_tag, 'Shop logo uploaded');
    return (res.data as Map<String, dynamic>)['url'] as String;
  }

  // ── Live thumbnail ────────────────────────────────────────────────────────

  /// POST /api/upload/live — seller/admin only.
  /// Form: `session_id`, `image`.  Response: `{ url, key }`.
  Future<String> uploadLiveThumbnail(String sessionId, File file) async {
    final form = FormData.fromMap({
      'session_id': sessionId,
      'image':      await MultipartFile.fromFile(file.path, filename: 'thumb.jpg'),
    });
    final res = await _dio.post('/api/upload/live', data: form);
    return (res.data as Map<String, dynamic>)['url'] as String;
  }

  // ── Temp (pre-product-creation) ───────────────────────────────────────────

  /// POST /api/upload/temp — any authenticated user.
  /// Form: `image`.  Response: `{ url, key }`.
  ///
  /// Used by quick-create flows where you upload an image before the product
  /// row exists. The temp key has no owner association — clean up via a
  /// scheduled R2 lifecycle rule if you want.
  Future<String> uploadTempImage(File file) async {
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(file.path, filename: 'temp.jpg'),
    });
    final res = await _dio.post('/api/upload/temp', data: form);
    return (res.data as Map<String, dynamic>)['url'] as String;
  }
}
