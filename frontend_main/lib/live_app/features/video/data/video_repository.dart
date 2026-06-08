// =============================================================================
// video_repository.dart
// =============================================================================
// Gọi các endpoint /api/videos của Go backend.
//
// Dùng [AuthService.authorizedDio]: nó tự gắn Bearer token KHI đã đăng nhập
// (bỏ qua khi ẩn danh → backend coi là khách, hợp với route optAuth) và tự
// unwrap envelope chuẩn ({Result, data, ...}) → response.data là payload trong.
// =============================================================================

import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';

class VideoRepository {
  Dio get _dio => AuthService.instance.authorizedDio();

  List<VideoPost> _parseList(dynamic data) {
    final list = (data is Map ? data['videos'] : data) as List? ?? const [];
    return list
        .whereType<Map>()
        .map((e) => VideoPost.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  // ── Feeds ──────────────────────────────────────────────────────────────────

  Future<List<VideoPost>> fetchFeed({int limit = 10, int offset = 0}) async {
    final res = await _dio.get(
      '/api/videos/feed',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _parseList(res.data);
  }

  Future<List<VideoPost>> fetchFollowing({
    int limit = 10,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/api/videos/following',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _parseList(res.data);
  }

  Future<List<VideoPost>> fetchUserVideos(
    String userId, {
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/api/videos/user/$userId',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _parseList(res.data);
  }

  Future<List<VideoPost>> fetchMyVideos({
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/api/videos/me',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _parseList(res.data);
  }

  /// Videos the logged-in user đã thích (tab "Đã thích" trang cá nhân),
  /// mới-thích-trước. Cùng shape với feed nên tái dùng được trình xem video.
  Future<List<VideoPost>> fetchLikedVideos({
    int limit = 30,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/api/videos/me/liked',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    return _parseList(res.data);
  }

  Future<VideoPost> fetchVideo(String id) async {
    final res = await _dio.get('/api/videos/$id');
    return VideoPost.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// Số liệu hồ sơ của tôi (header trang cá nhân): đang theo dõi / người theo
  /// dõi / tổng lượt thích. Backend gộp shop_follows + user_follows nên khớp
  /// với tab Live ("Theo dõi") và feed Video.
  Future<({int following, int followers, int likes})> fetchMyStats() async {
    final res = await _dio.get('/api/videos/me/stats');
    final m = res.data is Map
        ? Map<String, dynamic>.from(res.data as Map)
        : const <String, dynamic>{};
    int g(String k) => (m[k] as num?)?.toInt() ?? 0;
    return (
      following: g('following_count'),
      followers: g('follower_count'),
      likes: g('like_count'),
    );
  }

  // ── Hashtags ─────────────────────────────────────────────────────────────────

  /// Gợi ý hashtag cho ô "#" lúc đăng video. [query] rỗng → danh sách thịnh hành;
  /// có [query] → khớp tiền tố (không phân biệt hoa thường). Trả về list rỗng nếu
  /// lỗi mạng để dropdown không làm sập màn soạn.
  Future<List<HashtagSuggestion>> searchHashtags(
    String query, {
    int limit = 10,
  }) async {
    try {
      final res = await _dio.get(
        '/api/videos/hashtags',
        queryParameters: {if (query.isNotEmpty) 'q': query, 'limit': limit},
      );
      final list =
          (res.data is Map ? res.data['hashtags'] : res.data) as List? ??
          const [];
      return list
          .whereType<Map>()
          .map((e) => HashtagSuggestion.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  // ── Comments ─────────────────────────────────────────────────────────────────

  Future<List<VideoComment>> fetchComments(
    String videoId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/api/videos/$videoId/comments',
      queryParameters: {'limit': limit, 'offset': offset},
    );
    final list =
        (res.data is Map ? res.data['comments'] : res.data) as List? ??
        const [];
    return list
        .whereType<Map>()
        .map((e) => VideoComment.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<VideoComment> addComment(String videoId, String content) async {
    final res = await _dio.post(
      '/api/videos/$videoId/comments',
      data: {'content': content},
    );
    return VideoComment.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  // ── Interactions ─────────────────────────────────────────────────────────────

  /// Trả về like_count mới.
  Future<int> like(String videoId) async {
    final res = await _dio.post('/api/videos/$videoId/like');
    return (res.data is Map
            ? (res.data['like_count'] as num?)?.toInt()
            : null) ??
        0;
  }

  Future<int> unlike(String videoId) async {
    final res = await _dio.delete('/api/videos/$videoId/like');
    return (res.data is Map
            ? (res.data['like_count'] as num?)?.toInt()
            : null) ??
        0;
  }

  Future<void> incView(String videoId) async {
    try {
      await _dio.post('/api/videos/$videoId/view');
    } catch (_) {
      // fire-and-forget
    }
  }

  Future<void> incShare(String videoId) async {
    try {
      await _dio.post('/api/videos/$videoId/share');
    } catch (_) {}
  }

  /// Trả về true nếu đang follow sau lệnh.
  Future<bool> follow(String userId) async {
    final res = await _dio.post('/api/videos/creators/$userId/follow');
    return (res.data is Map ? res.data['following'] as bool? : null) ?? true;
  }

  Future<bool> unfollow(String userId) async {
    final res = await _dio.delete('/api/videos/creators/$userId/follow');
    return (res.data is Map ? res.data['following'] as bool? : null) ?? false;
  }

  /// Theo dõi SHOP gắn trên video — gọi đúng endpoint shop (resolve bằng slug).
  /// Backend trả {followed: bool}.
  Future<bool> followShop(String slug) async {
    final res = await _dio.post('/api/shops/$slug/follow');
    return (res.data is Map ? res.data['followed'] as bool? : null) ?? true;
  }

  Future<bool> unfollowShop(String slug) async {
    final res = await _dio.delete('/api/shops/$slug/follow');
    return (res.data is Map ? res.data['followed'] as bool? : null) ?? false;
  }

  // ── Posting ──────────────────────────────────────────────────────────────────

  /// Upload MP4 (+ ảnh bìa optional). Trả về {video_url, thumbnail_url?}.
  Future<Map<String, String>> uploadVideo(
    XFile video, {
    XFile? thumbnail,
  }) async {
    final videoBytes = await video.readAsBytes();
    String name = video.name;
    if (!name.toLowerCase().endsWith('.mp4') &&
        !name.toLowerCase().endsWith('.mov')) {
      name = '$name.mp4';
    }
    final form = FormData.fromMap({
      'video': MultipartFile.fromBytes(videoBytes, filename: name),
    });
    if (thumbnail != null) {
      final tb = await thumbnail.readAsBytes();
      String tn = thumbnail.name;
      if (!RegExp(
        r'\.(jpg|jpeg|png|webp)$',
        caseSensitive: false,
      ).hasMatch(tn)) {
        tn = '$tn.jpg';
      }
      form.files.add(
        MapEntry('thumbnail', MultipartFile.fromBytes(tb, filename: tn)),
      );
    }
    final res = await _dio.post('/api/videos/upload', data: form);
    final data = Map<String, dynamic>.from(res.data as Map);
    return {
      'video_url': data['video_url'] as String? ?? '',
      if (data['thumbnail_url'] != null)
        'thumbnail_url': data['thumbnail_url'] as String,
    };
  }

  Future<VideoPost> createVideo({
    required String videoUrl,
    String? thumbnailUrl,
    String? caption,
    List<String> hashtags = const [],
    int durationSec = 0,
    int width = 0,
    int height = 0,
    bool allowReuse = true,
    List<String> productIds = const [],
    List<String> couponIds = const [],
  }) async {
    final res = await _dio.post(
      '/api/videos',
      data: {
        'video_url': videoUrl,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
        if (caption != null) 'caption': caption,
        'hashtags': hashtags,
        'duration_sec': durationSec,
        'width': width,
        'height': height,
        'allow_reuse': allowReuse,
        if (productIds.isNotEmpty) 'product_ids': productIds,
        if (couponIds.isNotEmpty) 'coupon_ids': couponIds,
      },
    );
    return VideoPost.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  Future<void> deleteVideo(String id) async {
    await _dio.delete('/api/videos/$id');
  }

  // ── Moderation ───────────────────────────────────────────────────────────────

  Future<void> reportVideo(String videoId, String reason) async {
    await _dio.post('/api/videos/$videoId/report', data: {'reason': reason});
  }

  /// Admin: danh sách báo cáo (mặc định pending).
  Future<List<VideoReport>> fetchReports({
    String status = 'pending',
    int limit = 50,
    int offset = 0,
  }) async {
    final res = await _dio.get(
      '/api/video-reports',
      queryParameters: {'status': status, 'limit': limit, 'offset': offset},
    );
    final list =
        (res.data is Map ? res.data['reports'] : res.data) as List? ?? const [];
    return list
        .whereType<Map>()
        .map((e) => VideoReport.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Admin: xử lý báo cáo. takedown=true → gỡ video; false → bỏ qua.
  Future<void> resolveReport(String reportId, {required bool takedown}) async {
    await _dio.post(
      '/api/video-reports/$reportId/resolve',
      data: {'action': takedown ? 'takedown' : 'dismiss'},
    );
  }
}
