// =============================================================================
// video_provider.dart
// =============================================================================
// State cho feed "video đề xuất" (tab Video) + các tương tác like/follow/share
// và luồng đăng video (upload + create).
// =============================================================================

import 'package:flutter/foundation.dart';

import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/data/video_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';

const _tag = 'VideoProvider';

class VideoProvider extends ChangeNotifier {
  final VideoRepository _repo = VideoRepository();

  static const int _pageSize = 10;

  final List<VideoPost> _feed = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _error;
  bool _loadedOnce = false;

  // Dedupe view pings — count a video as "viewed" at most once per session.
  final Set<String> _viewed = {};

  List<VideoPost> get feed => List.unmodifiable(_feed);
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get loadedOnce => _loadedOnce;

  // ── Load ─────────────────────────────────────────────────────────────────────

  /// Tải feed lần đầu / khi tab Video lần đầu hiển thị. Không tải lại nếu đã có
  /// dữ liệu, trừ khi [force].
  Future<void> ensureLoaded({bool force = false}) async {
    if (_loadedOnce && !force) return;
    await loadFeed();
  }

  Future<void> loadFeed() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final items = await _repo.fetchFeed(limit: _pageSize, offset: 0);
      _feed
        ..clear()
        ..addAll(items);
      _hasMore = items.length >= _pageSize;
      _loadedOnce = true;
    } catch (e, st) {
      _error = AuthService.errorMessage(e);
      AppLogger.logError(_tag, 'loadFeed failed', e, st);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadFeed();

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore || _isLoading) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final items = await _repo.fetchFeed(
        limit: _pageSize,
        offset: _feed.length,
      );
      // Tránh trùng (feed ranking có thể trả lại item cũ giữa các trang).
      final existing = _feed.map((v) => v.id).toSet();
      _feed.addAll(items.where((v) => !existing.contains(v.id)));
      _hasMore = items.length >= _pageSize;
    } catch (e, st) {
      AppLogger.logError(_tag, 'loadMore failed', e, st);
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  // ── Interactions ─────────────────────────────────────────────────────────────

  void _replace(VideoPost v) {
    final i = _feed.indexWhere((x) => x.id == v.id);
    if (i != -1) _feed[i] = v;
  }

  Future<void> toggleLike(String videoId) async {
    final i = _feed.indexWhere((x) => x.id == videoId);
    if (i == -1) return;
    final before = _feed[i];
    final optimisticLiked = !before.liked;
    // Optimistic update.
    _feed[i] = before.copyWith(
      liked: optimisticLiked,
      likeCount: (before.likeCount + (optimisticLiked ? 1 : -1)).clamp(
        0,
        1 << 30,
      ),
    );
    notifyListeners();
    try {
      final count = optimisticLiked
          ? await _repo.like(videoId)
          : await _repo.unlike(videoId);
      _replace(_feed[i].copyWith(likeCount: count));
      notifyListeners();
    } catch (e) {
      // Revert.
      _replace(before);
      notifyListeners();
      AppLogger.logError(_tag, 'toggleLike failed', e);
      rethrow;
    }
  }

  /// Theo dõi / bỏ theo dõi theo NGỮ CẢNH thẻ video: có shop → theo dõi SHOP;
  /// video cá nhân (không shop) → fallback theo dõi CREATOR.
  Future<void> toggleFollowForVideo(String videoId) async {
    final i = _feed.indexWhere((x) => x.id == videoId);
    if (i == -1) return;
    final v = _feed[i];
    if (v.hasShop) {
      await toggleShopFollow(v.shopId!, v.shopSlug!);
    } else {
      await toggleFollow(v.userId);
    }
  }

  /// Theo dõi / bỏ theo dõi SHOP — đồng bộ trên MỌI video cùng shop trong feed.
  Future<void> toggleShopFollow(String shopId, String slug) async {
    final idx = _feed.indexWhere((x) => x.shopId == shopId);
    if (idx == -1) return;
    final newVal = !_feed[idx].shopFollowing;
    for (var i = 0; i < _feed.length; i++) {
      if (_feed[i].shopId == shopId) {
        _feed[i] = _feed[i].copyWith(shopFollowing: newVal);
      }
    }
    notifyListeners();
    try {
      final result = newVal
          ? await _repo.followShop(slug)
          : await _repo.unfollowShop(slug);
      if (result != newVal) {
        for (var i = 0; i < _feed.length; i++) {
          if (_feed[i].shopId == shopId) {
            _feed[i] = _feed[i].copyWith(shopFollowing: result);
          }
        }
        notifyListeners();
      }
    } catch (e) {
      // Revert.
      for (var i = 0; i < _feed.length; i++) {
        if (_feed[i].shopId == shopId) {
          _feed[i] = _feed[i].copyWith(shopFollowing: !newVal);
        }
      }
      notifyListeners();
      AppLogger.logError(_tag, 'toggleShopFollow failed', e);
      rethrow;
    }
  }

  /// Theo dõi / bỏ theo dõi creator — đồng bộ trên MỌI video của họ trong feed.
  Future<void> toggleFollow(String userId) async {
    final idx = _feed.indexWhere((x) => x.userId == userId);
    if (idx == -1) return;
    final newVal = !_feed[idx].following;
    for (var i = 0; i < _feed.length; i++) {
      if (_feed[i].userId == userId) {
        _feed[i] = _feed[i].copyWith(following: newVal);
      }
    }
    notifyListeners();
    try {
      final result = newVal
          ? await _repo.follow(userId)
          : await _repo.unfollow(userId);
      if (result != newVal) {
        for (var i = 0; i < _feed.length; i++) {
          if (_feed[i].userId == userId) {
            _feed[i] = _feed[i].copyWith(following: result);
          }
        }
        notifyListeners();
      }
    } catch (e) {
      // Revert.
      for (var i = 0; i < _feed.length; i++) {
        if (_feed[i].userId == userId) {
          _feed[i] = _feed[i].copyWith(following: !newVal);
        }
      }
      notifyListeners();
      AppLogger.logError(_tag, 'toggleFollow failed', e);
      rethrow;
    }
  }

  /// Đếm 1 lượt xem (tối đa 1 lần / video / phiên).
  void registerView(String videoId) {
    if (_viewed.contains(videoId)) return;
    _viewed.add(videoId);
    final i = _feed.indexWhere((x) => x.id == videoId);
    if (i != -1) {
      _feed[i] = _feed[i].copyWith(viewCount: _feed[i].viewCount + 1);
      notifyListeners();
    }
    _repo.incView(videoId);
  }

  void bumpCommentCount(String videoId, [int delta = 1]) {
    final i = _feed.indexWhere((x) => x.id == videoId);
    if (i != -1) {
      _feed[i] = _feed[i].copyWith(
        commentCount: (_feed[i].commentCount + delta).clamp(0, 1 << 30),
      );
      notifyListeners();
    }
  }

  Future<void> registerShare(String videoId) async {
    final i = _feed.indexWhere((x) => x.id == videoId);
    if (i != -1) {
      _feed[i] = _feed[i].copyWith(shareCount: _feed[i].shareCount + 1);
      notifyListeners();
    }
    await _repo.incShare(videoId);
  }

  // ── Publish ──────────────────────────────────────────────────────────────────

  /// Chèn video vừa đăng (màn publish tự upload+create) lên đầu feed để hiển thị
  /// ngay. Nếu feed chưa tải lần nào thì để [ensureLoaded] kéo về.
  void prepend(VideoPost v) {
    if (_feed.any((x) => x.id == v.id)) return;
    if (_loadedOnce) {
      _feed.insert(0, v);
    } else {
      _feed.insert(0, v);
      _loadedOnce = true;
    }
    AppLogger.logUserEvent(
      action: 'video_published',
      context: _tag,
      metadata: {'videoId': v.id},
    );
    notifyListeners();
  }

  /// Gỡ video khỏi feed sau khi chủ video xóa nó (share sheet → "Xóa").
  void remove(String videoId) {
    final i = _feed.indexWhere((x) => x.id == videoId);
    if (i == -1) return;
    _feed.removeAt(i);
    AppLogger.logUserEvent(
      action: 'video_deleted',
      context: _tag,
      metadata: {'videoId': videoId},
    );
    notifyListeners();
  }
}
