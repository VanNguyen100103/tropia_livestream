import 'package:dio/dio.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';

const _tag = 'LiveRepository';

/// Talks to the new Go backend (Gin + pgx + SRS).
///
/// Endpoint shape:
/// - GET  /api/live/streams                 -> { sessions: [...] }
/// - POST /api/live/streams                  -> { session, publish: { rtmp, whip, srt } }
/// - GET  /api/live/streams/:id              -> { session }
/// - POST /api/live/streams/:id/end          -> 204
/// - GET  /api/live/streams/:id/playback     -> { session, playback: { hls, flv, whep } }
/// - GET  /api/live/streams/:id/publish      -> { session, publish }
/// - POST /api/live/streams/:id/join         -> 204
/// - POST /api/live/streams/:id/leave        -> 204
/// - POST /api/live/streams/:id/like         -> 204
/// - GET  /api/live/streams/:id/chat         -> { messages: [...] }
/// - POST /api/live/streams/:id/chat         -> message
/// - GET  /api/live/streams/:id/stats        -> { viewer_count, like_count, ... }
/// - POST /api/live/streams/:id/track-cart-add  -> 204
/// - POST /api/live/streams/:id/track-follow    -> 204
/// - GET  /api/live/streams/:id/products     -> { products: [...] }
class LiveRepository {
  LiveRepository._();
  static final _instance = LiveRepository._();
  static LiveRepository get instance => _instance;

  Dio get _dio => AuthService.instance.authorizedDio();

  // ── Sessions ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchLiveSessions() async {
    final res = await _dio.get('/api/live/streams');
    final data = res.data as Map<String, dynamic>;
    final list = (data['sessions'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Returns { session, publish: { rtmp, whip, srt } }.
  ///
  /// Products / coupons are NOT created in this single call any more —
  /// the Go backend creates the stream session only. Add products via
  /// follow-up endpoints once you have the session id.
  Future<Map<String, dynamic>> startLive({
    required String title,
    required String category,
    String? description,
    String? coverImageUrl,
    List<LiveProduct> products = const [],
    List<Map<String, dynamic>> coupons = const [],
  }) async {
    final payload = {
      'title':    title,
      'category': category,
      if (description != null) 'description': description,
      if (coverImageUrl != null) 'cover_image_url': coverImageUrl,
    };

    AppLogger.logInfo(_tag, 'startLive payload: $payload');

    try {
      final res = await _dio.post('/api/live/streams', data: payload);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      AppLogger.logError(_tag, 'startLive failed ${e.response?.statusCode}: ${e.response?.data}', e, null);
      rethrow;
    }
  }

  Future<void> endLive(String sessionId) async {
    await _dio.post('/api/live/streams/$sessionId/end');
  }

  /// Host-only: toggle DeepSeek auto-reply bot for this session.
  Future<bool> setBotEnabled(String sessionId, bool enabled) async {
    final res = await _dio.patch('/api/live/streams/$sessionId/bot',
        data: {'enabled': enabled});
    final data = res.data as Map<String, dynamic>;
    return (data['ai_bot_enabled'] as bool?) ?? enabled;
  }

  /// Host-only: attach (pin) products to the session so viewers see them.
  /// [items] elements use snake_case keys matching the Go backend:
  ///   product_id (uuid string, optional), product_name, image_url,
  ///   original_price, sale_price, discount_pct, stock_left, unit, is_pinned.
  Future<List<Map<String, dynamic>>> addSessionProducts(
    String sessionId,
    List<Map<String, dynamic>> items,
  ) async {
    final res = await _dio.post('/api/live/streams/$sessionId/products',
        data: {'products': items});
    final data = res.data as Map<String, dynamic>;
    final list = (data['products'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Replace the entire pinned product list for a live session in one
  /// call. Use when the host returns from the picker mid-stream so the
  /// server-side rows match exactly what the host last confirmed —
  /// keeps the bot reply heuristic and viewer-facing carousel in sync.
  Future<List<Map<String, dynamic>>> replaceSessionProducts(
    String sessionId,
    List<Map<String, dynamic>> items,
  ) async {
    final res = await _dio.put('/api/live/streams/$sessionId/products',
        data: {'products': items});
    final data = res.data as Map<String, dynamic>;
    final list = (data['products'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  /// Unpin a single product from a live session. [sessionProductId] is
  /// the `live_session_products.id` (the session-scoped row), not the
  /// catalog product uuid.
  Future<void> removeSessionProduct(String sessionId, String sessionProductId) async {
    await _dio.delete('/api/live/streams/$sessionId/products/$sessionProductId');
  }

  /// Shopee Live "GẶP LÊN" — highlight one session product as the one
  /// currently being demoed. Pass null to clear the highlight.
  /// [sessionProductId] is `live_session_products.id` (session-scoped).
  Future<void> setPinnedProduct(String sessionId, String? sessionProductId) async {
    await _dio.post(
      '/api/live/streams/$sessionId/pin',
      data: {'product_id': sessionProductId},
    );
  }

  /// Re-broadcast an already-created coupon to every viewer's floating
  /// banner. Creating a new coupon already auto-announces; this is for
  /// the "Phát lại" button in the host coupon manager.
  Future<void> announceCoupon(String sessionId, String couponId) async {
    await _dio.post('/api/live/streams/$sessionId/coupons/$couponId/announce');
  }

  /// Fetches playback URLs for a viewer.
  Future<Map<String, dynamic>> fetchPlayback(String sessionId) async {
    final res = await _dio.get('/api/live/streams/$sessionId/playback');
    return res.data as Map<String, dynamic>;
  }

  /// Fetches publish URLs (owner-only).
  Future<Map<String, dynamic>> fetchPublish(String sessionId) async {
    final res = await _dio.get('/api/live/streams/$sessionId/publish');
    return res.data as Map<String, dynamic>;
  }

  // ── Viewer presence ─────────────────────────────────────────────────────────

  Future<void> joinAsViewer(String sessionId) async {
    try {
      await _dio.post('/api/live/streams/$sessionId/join');
      AppLogger.logInfo(_tag, 'Joined: $sessionId');
    } catch (e) {
      AppLogger.logError(_tag, 'joinAsViewer failed', e, null);
    }
  }

  Future<void> leaveAsViewer(String sessionId) async {
    try {
      await _dio.post('/api/live/streams/$sessionId/leave');
      AppLogger.logInfo(_tag, 'Left: $sessionId');
    } catch (e) {
      AppLogger.logError(_tag, 'leaveAsViewer failed', e, null);
    }
  }

  // ── Chat ────────────────────────────────────────────────────────────────────

  Future<void> sendChat({
    required String sessionId,
    required String message,
    String type = 'text',
    bool isHost = false,
  }) async {
    await _dio.post('/api/live/streams/$sessionId/chat', data: {
      'message': message,
      'type':    type,
      if (isHost) 'is_host': true,
    });
  }

  Future<List<Map<String, dynamic>>> fetchRecentChats(String sessionId, {int limit = 50}) async {
    final res = await _dio.get('/api/live/streams/$sessionId/chat', queryParameters: {'limit': limit});
    final data = res.data as Map<String, dynamic>;
    final list = (data['messages'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  // ── Stats polling ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchSessionStats(String sessionId) async {
    final res = await _dio.get('/api/live/streams/$sessionId/stats');
    return res.data as Map<String, dynamic>;
  }

  // ── Products on the live session ───────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchSessionProducts(String sessionId) async {
    final res = await _dio.get('/api/live/streams/$sessionId/products');
    final data = res.data as Map<String, dynamic>;
    final list = (data['products'] as List?) ?? const [];
    return list.cast<Map<String, dynamic>>();
  }

  // ── Like ────────────────────────────────────────────────────────────────────

  Future<void> likeSession(String sessionId) async {
    try {
      await _dio.post('/api/live/streams/$sessionId/like');
    } catch (e) {
      AppLogger.logError(_tag, 'likeSession failed', e, null);
    }
  }

  // ── Tracking ────────────────────────────────────────────────────────────────

  Future<void> trackCartAdd(String sessionId) async {
    try {
      await _dio.post('/api/live/streams/$sessionId/track-cart-add');
    } catch (_) {}
  }

  Future<void> trackFollow(String sessionId) async {
    try {
      await _dio.post('/api/live/streams/$sessionId/track-follow');
    } catch (_) {}
  }

  // ── Orders ──────────────────────────────────────────────────────────────────

  /// Place a live-product order. Maps to the Go backend's POST /api/orders.
  Future<Map<String, dynamic>> placeOrder({
    required String liveProductId,
    required int quantity,
    String? couponCode,
  }) async {
    final res = await _dio.post('/api/orders', data: {
      'live_product_id': liveProductId,
      'quantity':        quantity,
      if (couponCode != null) 'coupon_code': couponCode,
    });
    return res.data as Map<String, dynamic>;
  }

  // ── AI (Phase 18 — DeepSeek-backed on the Go side) ─────────────────────────

  /// Returns up to 3 short Vietnamese viewer questions for the host to
  /// optionally broadcast as starter chat. Falls back to `null` on failure.
  Future<List<String>?> fetchAiSuggestions({
    required String sessionId,
    String? productName,
    String? category,
    List<String> recentComments = const [],
  }) async {
    try {
      final res = await _dio.post(
        '/api/live/streams/$sessionId/ai-suggestions',
        data: {
          if (productName != null) 'product_name': productName,
          if (category != null) 'category': category,
          if (recentComments.isNotEmpty) 'recent_comments': recentComments,
        },
      );
      final list = (res.data as Map<String, dynamic>)['suggestions'] as List?;
      return list?.cast<String>();
    } catch (e) {
      AppLogger.logError(_tag, 'fetchAiSuggestions failed', e, null);
      return null;
    }
  }

  /// Auto-reply for one viewer question. Returns the reply string or null.
  Future<String?> fetchAiReply({
    required String sessionId,
    required String question,
    String? productName,
    String? category,
  }) async {
    try {
      final res = await _dio.post(
        '/api/live/streams/$sessionId/ai-reply',
        data: {
          'question': question,
          if (productName != null) 'product_name': productName,
          if (category != null) 'category': category,
        },
      );
      return (res.data as Map<String, dynamic>)['reply'] as String?;
    } catch (e) {
      AppLogger.logError(_tag, 'fetchAiReply failed', e, null);
      return null;
    }
  }

  /// Sentiment + summary + 4 tips for the host. Returns
  /// `{sentiment, summary, tips: [...]}` or null on failure.
  Future<Map<String, dynamic>?> analyzeLive(String sessionId) async {
    try {
      final res = await _dio.post('/api/live/streams/$sessionId/analyze');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      AppLogger.logError(_tag, 'analyzeLive failed', e, null);
      return null;
    }
  }

  // ── Coupons (live session-scoped) ──────────────────────────────────────────

  /// Public list of coupons created for this live session. Used by the
  /// viewer entry banner ("Lưu") and the live cart voucher picker.
  Future<List<Map<String, dynamic>>> fetchLiveCoupons(String sessionId) async {
    try {
      final res = await _dio.get('/api/live/streams/$sessionId/coupons');
      final list = (res.data as Map<String, dynamic>)['coupons'] as List?;
      return list?.cast<Map<String, dynamic>>() ?? const [];
    } catch (e) {
      AppLogger.logError(_tag, 'fetchLiveCoupons failed', e, null);
      return const [];
    }
  }

  /// Host-only: persist a coupon onto a live session so viewers can claim it.
  /// [discountType] = 'percent' | 'fixed'.
  Future<Map<String, dynamic>?> createLiveCoupon({
    required String sessionId,
    required String code,
    required String discountType,
    required double discountValue,
    double minOrderValue = 0,
    int? maxUses,
    required DateTime expiresAt,
  }) async {
    try {
      final res = await _dio.post(
        '/api/live/streams/$sessionId/coupons',
        data: {
          'code':           code,
          'discount_type':  discountType,
          'discount_value': discountValue,
          'min_order_value': minOrderValue,
          if (maxUses != null) 'max_uses': maxUses,
          'expires_at':     expiresAt.toUtc().toIso8601String(),
        },
      );
      final body = res.data as Map<String, dynamic>;
      return body['coupon'] as Map<String, dynamic>?;
    } on DioException catch (e) {
      AppLogger.logError(_tag, 'createLiveCoupon failed ${e.response?.statusCode}: ${e.response?.data}', e, null);
      rethrow;
    }
  }

  Future<void> broadcastCoupon({
    required String sessionId,
    required String couponCode,
  }) async {
    // Broadcast = chat message with a prefix the viewer side detects to
    // open a popup. Cheap, no extra endpoint.
    await sendChat(
      sessionId: sessionId,
      message:   '🎫 Coupon: $couponCode',
      isHost:    true,
    );
  }

  // ── Gifts (LIVESTREAM_API.md §8) ────────────────────────────────────────────

  /// Danh mục quà (GET /api/live/gifts). Public.
  Future<List<LiveGiftCatalogItem>> fetchGiftCatalog() async {
    try {
      final res = await _dio.get('/api/live/gifts');
      final list = (res.data as Map<String, dynamic>)['items'] as List?;
      return (list ?? const [])
          .cast<Map<String, dynamic>>()
          .map(LiveGiftCatalogItem.fromJson)
          .toList();
    } catch (e) {
      AppLogger.logError(_tag, 'fetchGiftCatalog failed', e, null);
      return const [];
    }
  }

  /// Gửi quà (POST /api/live/gift/send). Trả về `{gift, points_remaining}`.
  /// Ném DioException (kèm message tiếng Việt) khi thiếu điểm / không live /
  /// tự tặng — caller bắt và hiển thị.
  Future<({LiveGiftSent gift, int pointsRemaining})> sendGift({
    required String streamKey,
    required int giftId,
    int quantity = 1,
  }) async {
    final res = await _dio.post('/api/live/gift/send', data: {
      'stream_key': streamKey,
      'gift_id':    giftId,
      'quantity':   quantity,
    });
    final data = res.data as Map<String, dynamic>;
    return (
      gift: LiveGiftSent.fromJson(data['gift'] as Map<String, dynamic>),
      pointsRemaining: (data['points_remaining'] as num? ?? 0).toInt(),
    );
  }

  /// Quà vừa tặng trên stream (GET /api/live/gifts/recent) — overlay hiệu ứng.
  Future<List<LiveGiftSent>> fetchRecentGifts(String streamKey, {int limit = 30}) async {
    try {
      final res = await _dio.get('/api/live/gifts/recent',
          queryParameters: {'stream_key': streamKey, 'limit': limit});
      final list = (res.data as Map<String, dynamic>)['items'] as List?;
      return (list ?? const [])
          .cast<Map<String, dynamic>>()
          .map(LiveGiftSent.fromJson)
          .toList();
    } catch (e) {
      AppLogger.logError(_tag, 'fetchRecentGifts failed', e, null);
      return const [];
    }
  }

  // ── VOD replay timeline ────────────────────────────────────────────────────

  /// Fetches the merged replay timeline for a recorded session: every
  /// host action (bot toggle / pin / coupon) plus chat, each entry
  /// tagged with `t` = ms offset from the start of the MP4. The VOD
  /// player drives overlays off this list synced to videoController
  /// position. Returns null on failure (player still plays the bare
  /// MP4, just without overlays).
  Future<Map<String, dynamic>?> fetchVodTimeline(String sessionId) async {
    try {
      final res = await _dio.get('/api/live/streams/$sessionId/timeline');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      AppLogger.logError(_tag, 'fetchVodTimeline failed', e, null);
      return null;
    }
  }
}
