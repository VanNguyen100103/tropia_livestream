import 'package:dio/dio.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';

const _tag = 'LiveRepository';

class LiveRepository {
  LiveRepository._();
  static final _instance = LiveRepository._();
  static LiveRepository get instance => _instance;

  get _dio => AuthService.instance.authorizedDio();

  // ── Sessions ────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchLiveSessions() async {
    final res = await _dio.get('/api/live');
    return List<Map<String, dynamic>>.from(res.data as List);
  }

  Future<Map<String, dynamic>> startLive({
    required String title,
    required String category,
    required List<LiveProduct> products,
    List<Map<String, dynamic>> coupons = const [],
  }) async {
    final payload = {
      'title':    title,
      'category': category,
      'products': products.map((p) {
        // imageUrl phải là URL hợp lệ (http/https), bỏ qua local file path
        final isValidUrl = p.imageUrl.startsWith('http://') || p.imageUrl.startsWith('https://');
        // unit: chỉ dùng đơn vị ngắn, max 20 ký tự
        final unitVal = p.unit.length > 20 ? p.unit.substring(0, 20).trim() : p.unit.trim();
        return {
          'name':            p.name,
          if (isValidUrl) 'imageUrl': p.imageUrl,
          'originalPrice':   p.originalPrice,
          'salePrice':       p.salePrice,
          'discountPercent': p.discountPercent,
          'totalStock':      p.totalStock,
          'unit':            unitVal.isEmpty ? 'cái' : unitVal,
          if (p.category.isNotEmpty) 'category': p.category,
        };
      }).toList(),
      'coupons': coupons,
    };

    AppLogger.logInfo(_tag, 'startLive payload: $payload');

    try {
      final res = await _dio.post('/api/live/start', data: payload);
      return res.data as Map<String, dynamic>;
    } on DioException catch (e) {
      // Log chi tiết lỗi validation để debug
      AppLogger.logError(_tag, 'startLive failed ${e.response?.statusCode}: ${e.response?.data}', e, null);
      rethrow;
    }
  }

  Future<void> endLive(String sessionId) async {
    await _dio.post('/api/live/$sessionId/end');
  }

  // ── Viewer presence ─────────────────────────────────────────────────────────

  Future<void> joinAsViewer(String sessionId) async {
    try {
      await _dio.post('/api/live/$sessionId/join');
      AppLogger.logInfo(_tag, 'Joined: $sessionId');
    } catch (e) {
      AppLogger.logError(_tag, 'joinAsViewer failed', e, null);
    }
  }

  Future<void> leaveAsViewer(String sessionId) async {
    try {
      await _dio.post('/api/live/$sessionId/leave');
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
    await _dio.post('/api/live/$sessionId/chat', data: {
      'message': message,
      'type':    type,
      if (isHost) 'isHost': true,
    });
  }

  Future<List<Map<String, dynamic>>> fetchRecentChats(String sessionId, {int limit = 50}) async {
    final res = await _dio.get('/api/live/$sessionId/chat', queryParameters: {'limit': limit});
    return List<Map<String, dynamic>>.from(res.data as List);
  }

  // ── Stats polling ───────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> fetchSessionStats(String sessionId) async {
    final res = await _dio.get('/api/live/$sessionId/stats');
    return res.data as Map<String, dynamic>;
  }

  // ── AI auto-reply ───────────────────────────────────────────────────────────

  Future<String?> fetchAiReply({
    required String sessionId,
    required String question,
    required String productName,
    required String category,
  }) async {
    try {
      final res = await _dio.post('/api/live/$sessionId/ai-reply', data: {
        'question':    question,
        'productName': productName,
        'category':    category,
      });
      return (res.data as Map<String, dynamic>)['reply'] as String?;
    } catch (e) {
      AppLogger.logError(_tag, 'fetchAiReply failed', e, null);
      return null;
    }
  }

  // ── Coupons ──────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchLiveCoupons(String sessionId) async {
    try {
      final res = await _dio.get('/api/live/$sessionId/coupons');
      return List<Map<String, dynamic>>.from(res.data as List);
    } catch (e) {
      AppLogger.logError(_tag, 'fetchLiveCoupons failed', e, null);
      return [];
    }
  }

  Future<void> broadcastCoupon({
    required String sessionId,
    required String couponCode,
  }) async {
    await _dio.post('/api/live/$sessionId/broadcast-coupon', data: {
      'couponCode': couponCode,
    });
  }

  // ── Like ────────────────────────────────────────────────────────────────────

  Future<void> likeSession(String sessionId) async {
    try {
      await _dio.post('/api/live/$sessionId/like');
    } catch (e) {
      AppLogger.logError(_tag, 'likeSession failed', e, null);
    }
  }

  // ── Tracking ────────────────────────────────────────────────────────────────

  Future<void> trackCartAdd(String sessionId) async {
    try {
      await _dio.post('/api/live/$sessionId/track-cart-add');
    } catch (_) {}
  }

  Future<void> trackFollow(String sessionId) async {
    try {
      await _dio.post('/api/live/$sessionId/track-follow');
    } catch (_) {}
  }

  // ── Phân tích sentiment buổi live ───────────────────────────────────────────

  Future<Map<String, dynamic>?> analyzeLive(String sessionId) async {
    try {
      final res = await _dio.post('/api/live/$sessionId/analyze');
      return res.data as Map<String, dynamic>;
    } catch (e) {
      AppLogger.logError(_tag, 'analyzeLive failed', e, null);
      return null;
    }
  }

  // ── Orders ──────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> placeOrder({
    required String sessionId,
    required String productId,
    required int quantity,
  }) async {
    final res = await _dio.post('/api/orders', data: {
      'sessionId': sessionId,
      'productId': productId,
      'quantity':  quantity,
      'buyerName': AuthService.instance.currentUser?.name ?? 'Khách',
    });
    return res.data as Map<String, dynamic>;
  }
}
