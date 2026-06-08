import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/shop/models/shop_model.dart';

const _tag = 'ShopRepository';

class ShopRepository {
  ShopRepository._();
  static final instance = ShopRepository._();

  get _dio    => AuthService.instance.authorizedDio();
  get _public => AuthService.instance.authorizedDio();

  // ── Public ────────────────────────────────────────────────────────────────

  Future<({List<ShopModel> items, int total})> list(
      {int page = 1, int limit = 20}) async {
    final res = await _public.get('/api/shops',
        queryParameters: {'page': page, 'limit': limit});
    final data = res.data as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => ShopModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (data['total'] as num).toInt());
  }

  Future<ShopModel> getBySlug(String slug) async {
    final res = await _public.get('/api/shops/$slug');
    // Backend wraps in {"shop": {...}, "is_following": bool}.  Pull out
    // the inner object before parsing — passing the wrapper straight to
    // ShopModel.fromJson made `j['id']` null and 'Không thể tải thông
    // tin cửa hàng' came back from the catch arm.
    final data = res.data as Map<String, dynamic>;
    final shop = (data['shop'] as Map<String, dynamic>?) ?? data;
    final isFollowing = data['is_following'] as bool? ?? false;
    final model = ShopModel.fromJson(shop);
    return isFollowing ? model.copyWith(isFollowing: true) : model;
  }

  // ── Seller ────────────────────────────────────────────────────────────────

  Future<ShopModel?> getMyShop() async {
    try {
      final res = await _dio.get('/api/shops/me/info');
      final data = res.data as Map<String, dynamic>;
      // {"shop": null} means the seller hasn't created a shop yet.
      final shop = data['shop'];
      if (shop == null) return null;
      return ShopModel.fromJson(shop as Map<String, dynamic>);
    } catch (e) {
      AppLogger.logInfo(_tag, 'No shop yet: $e');
      return null;
    }
  }

  Future<ShopModel> create(Map<String, dynamic> body) async {
    final res = await _dio.post('/api/shops', data: body);
    final data = res.data as Map<String, dynamic>;
    final shop = (data['shop'] as Map<String, dynamic>?) ?? data;
    AppLogger.logInfo(_tag, 'Shop created: ${shop['id']}');
    return ShopModel.fromJson(shop);
  }

  Future<ShopModel> update(String id, Map<String, dynamic> body) async {
    final res = await _dio.patch('/api/shops/$id', data: body);
    final data = res.data as Map<String, dynamic>;
    final shop = (data['shop'] as Map<String, dynamic>?) ?? data;
    return ShopModel.fromJson(shop);
  }

  // ── Follow ────────────────────────────────────────────────────────────────

  /// POST /api/shops/:id/follow
  Future<void> follow(String shopId) async {
    await _dio.post('/api/shops/$shopId/follow');
    AppLogger.logUserEvent(action: 'follow_shop', context: _tag, metadata: {'shopId': shopId});
  }

  /// DELETE /api/shops/:id/follow
  Future<void> unfollow(String shopId) async {
    await _dio.delete('/api/shops/$shopId/follow');
    AppLogger.logUserEvent(action: 'unfollow_shop', context: _tag, metadata: {'shopId': shopId});
  }

  /// GET /api/shops/:id/follow-status → { followed: bool }
  Future<bool> isFollowing(String shopId) async {
    try {
      final res = await _dio.get('/api/shops/$shopId/follow-status');
      return (res.data as Map<String, dynamic>)['followed'] as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// GET /api/shops/me/following → { data: [...], count }
  Future<({List<ShopModel> items, int total})> getFollowedShops(
      {int page = 1, int limit = 20}) async {
    final offset = (page - 1) * limit;
    final res = await _dio.get('/api/shops/me/following',
        queryParameters: {'offset': offset, 'limit': limit});
    final d = res.data as Map<String, dynamic>;
    final items = (d['data'] as List)
        .map((e) => ShopModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (d['count'] as num).toInt());
  }

  /// Lấy toàn bộ shop IDs mà user đang follow (dùng để enrich danh sách live)
  Future<Set<String>> getFollowedShopIds() async {
    try {
      final res = await _dio.get('/api/shops/me/following',
          queryParameters: {'offset': 0, 'limit': 200});
      final d = res.data as Map<String, dynamic>;
      return (d['data'] as List)
          .map((e) => (e as Map<String, dynamic>)['id'] as String)
          .toSet();
    } catch (_) {
      return {};
    }
  }
}
