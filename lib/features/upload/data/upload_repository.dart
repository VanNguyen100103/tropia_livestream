import 'dart:io';

import 'package:dio/dio.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';

const _tag = 'UploadRepository';

class UploadRepository {
  UploadRepository._();
  static final instance = UploadRepository._();

  get _dio => AuthService.instance.authorizedDio();

  // ── Avatar ────────────────────────────────────────────────────────────────

  /// POST /api/upload/avatar  → { url, publicId }
  Future<String> uploadAvatar(File file) async {
    final form = FormData.fromMap({
      'image': await MultipartFile.fromFile(file.path, filename: 'avatar.jpg'),
    });
    final res = await _dio.post('/api/upload/avatar', data: form);
    AppLogger.logInfo(_tag, 'Avatar uploaded');
    return res.data['url'] as String;
  }

  // ── Product images ────────────────────────────────────────────────────────

  /// POST /api/upload/product  → [{ url, publicId }, ...]
  Future<List<String>> uploadProductImages(String productId, List<File> files) async {
    final form = FormData.fromMap({
      'productId': productId,
      'images': await Future.wait(
        files.map((f) => MultipartFile.fromFile(f.path, filename: f.uri.pathSegments.last)),
      ),
    });
    final res = await _dio.post('/api/upload/product', data: form);
    final list = res.data as List;
    AppLogger.logInfo(_tag, 'Uploaded ${list.length} product images');
    return list.map((e) => e['url'] as String).toList();
  }

  // ── Variant images ────────────────────────────────────────────────────────

  /// POST /api/upload/variant  → [{ url, publicId }, ...]
  Future<List<String>> uploadVariantImages(String variantId, List<File> files) async {
    final form = FormData.fromMap({
      'variantId': variantId,
      'images': await Future.wait(
        files.map((f) => MultipartFile.fromFile(f.path, filename: f.uri.pathSegments.last)),
      ),
    });
    final res = await _dio.post('/api/upload/variant', data: form);
    final list = res.data as List;
    return list.map((e) => e['url'] as String).toList();
  }

  // ── Shop banner ───────────────────────────────────────────────────────────

  /// POST /api/upload/shop  → { url, publicId }
  Future<String> uploadShopBanner(String shopId, File file) async {
    final form = FormData.fromMap({
      'shopId': shopId,
      'image':  await MultipartFile.fromFile(file.path, filename: 'banner.jpg'),
    });
    final res = await _dio.post('/api/upload/shop', data: form);
    return res.data['url'] as String;
  }

  // ── Live thumbnail ────────────────────────────────────────────────────────

  /// POST /api/upload/live  → { url, publicId }
  Future<String> uploadLiveThumbnail(String sessionId, File file) async {
    final form = FormData.fromMap({
      'sessionId': sessionId,
      'image':     await MultipartFile.fromFile(file.path, filename: 'thumb.jpg'),
    });
    final res = await _dio.post('/api/upload/live', data: form);
    return res.data['url'] as String;
  }
}
