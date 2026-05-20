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

  // ── Deferred (Phase 18 — not wired yet on the Go backend) ──────────────────

  Future<String?> fetchAiReply({
    required String sessionId,
    required String question,
    required String productName,
    required String category,
  }) async {
    AppLogger.logInfo(_tag, 'fetchAiReply: endpoint not wired in Go backend yet');
    return null;
  }

  Future<List<Map<String, dynamic>>> fetchLiveCoupons(String sessionId) async {
    AppLogger.logInfo(_tag, 'fetchLiveCoupons: endpoint not wired in Go backend yet');
    return const [];
  }

  Future<void> broadcastCoupon({
    required String sessionId,
    required String couponCode,
  }) async {
    AppLogger.logInfo(_tag, 'broadcastCoupon: endpoint not wired in Go backend yet');
  }

  Future<Map<String, dynamic>?> analyzeLive(String sessionId) async {
    AppLogger.logInfo(_tag, 'analyzeLive: endpoint not wired in Go backend yet');
    return null;
  }
}
