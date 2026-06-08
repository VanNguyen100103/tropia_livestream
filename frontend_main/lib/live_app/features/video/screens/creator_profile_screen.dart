// =============================================================================
// creator_profile_screen.dart
// =============================================================================
// Trang creator: avatar + nút theo dõi + lưới video của họ. Chạm 1 video → mở
// trình xem dọc (tái dùng VideoPlayerItem) bắt đầu từ video đó.
//
// Tự quản lý state cục bộ (không dùng VideoProvider của feed chính) để có thể
// mở từ route push ngoài provider scope.
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/features/product/screens/product_detail_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/user/screens/login_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/data/video_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_add_to_cart_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_comment_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_player_item.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_report_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_share_sheet.dart';

class CreatorProfileScreen extends StatefulWidget {
  final String userId;
  final String displayName;
  final String? avatarUrl;
  final bool following;

  const CreatorProfileScreen({
    super.key,
    required this.userId,
    required this.displayName,
    this.avatarUrl,
    this.following = false,
  });

  @override
  State<CreatorProfileScreen> createState() => _CreatorProfileScreenState();
}

class _CreatorProfileScreenState extends State<CreatorProfileScreen> {
  final _repo = VideoRepository();
  List<VideoPost> _videos = [];
  bool _loading = true;
  late bool _following = widget.following;

  bool get _isMe => AuthService.instance.currentUser?.id == widget.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _repo.fetchUserVideos(widget.userId);
      if (mounted) setState(() => _videos = list);
    } catch (_) {
      // keep empty
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (!AuthService.instance.isSignedIn) {
      Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
      return;
    }
    final newVal = !_following;
    setState(() => _following = newVal);
    try {
      final res = newVal
          ? await _repo.follow(widget.userId)
          : await _repo.unfollow(widget.userId);
      if (mounted) setState(() => _following = res);
    } catch (_) {
      if (mounted) setState(() => _following = !newVal);
    }
  }

  void _openViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _CreatorFeedViewer(
          videos: List.of(_videos),
          initialIndex: index,
          onVideoDeleted: _removeVideo,
        ),
      ),
    );
  }

  /// Gỡ video khỏi lưới sau khi nó bị xóa trong trình xem (đồng bộ với viewer).
  void _removeVideo(String id) {
    if (!mounted) return;
    setState(() => _videos = _videos.where((v) => v.id != id).toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
        title: Text(widget.displayName),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSizes.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primaryContainer,
                  backgroundImage: widget.avatarUrl != null
                      ? CachedNetworkImageProvider(widget.avatarUrl!)
                      : null,
                  child: widget.avatarUrl == null
                      ? const Icon(
                          Icons.person,
                          color: AppColors.primary,
                          size: 36,
                        )
                      : null,
                ),
                const SizedBox(width: AppSizes.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.displayName,
                        style: const TextStyle(
                          fontSize: AppSizes.fontXl,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_videos.length} video',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: AppSizes.fontSm,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!_isMe)
                  FilledButton(
                    onPressed: _toggleFollow,
                    style: FilledButton.styleFrom(
                      backgroundColor: _following
                          ? AppColors.background
                          : AppColors.primary,
                      foregroundColor: _following
                          ? AppColors.textPrimary
                          : Colors.white,
                    ),
                    child: Text(_following ? 'Đang theo dõi' : 'Theo dõi'),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  )
                : _videos.isEmpty
                ? const Center(
                    child: Text(
                      'Chưa có video',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.all(2),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                          childAspectRatio: 0.7,
                        ),
                    itemCount: _videos.length,
                    itemBuilder: (_, i) => _GridTile(
                      video: _videos[i],
                      onTap: () => _openViewer(i),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _GridTile extends StatelessWidget {
  final VideoPost video;
  final VoidCallback onTap;
  const _GridTile({required this.video, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final thumb = video.thumbUrl;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (thumb != null)
            CachedNetworkImage(
              imageUrl: thumb,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _placeholder(),
            )
          else
            _placeholder(),
          Positioned(
            left: 4,
            bottom: 4,
            child: Row(
              children: [
                const Icon(Icons.play_arrow, color: Colors.white, size: 14),
                const SizedBox(width: 2),
                Text(
                  _fmt(video.viewCount),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.fontXs,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 3)],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
    color: Colors.black87,
    alignment: Alignment.center,
    child: const Icon(
      Icons.play_circle_outline,
      color: Colors.white30,
      size: 32,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// In-place vertical viewer for a creator's videos (no global VideoProvider).
// ─────────────────────────────────────────────────────────────────────────────

class _CreatorFeedViewer extends StatefulWidget {
  final List<VideoPost> videos;
  final int initialIndex;
  final void Function(String id)? onVideoDeleted;
  const _CreatorFeedViewer({
    required this.videos,
    required this.initialIndex,
    this.onVideoDeleted,
  });

  @override
  State<_CreatorFeedViewer> createState() => _CreatorFeedViewerState();
}

class _CreatorFeedViewerState extends State<_CreatorFeedViewer> {
  final _repo = VideoRepository();
  late final PageController _pageController = PageController(
    initialPage: widget.initialIndex,
  );
  late final List<VideoPost> _videos = List.of(widget.videos);
  late int _activeIndex = widget.initialIndex;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _requireLogin() {
    if (AuthService.instance.isSignedIn) return true;
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LoginScreen()));
    return false;
  }

  void _replace(int i, VideoPost v) => setState(() => _videos[i] = v);

  Future<void> _toggleLike(int i) async {
    if (!_requireLogin()) return;
    final before = _videos[i];
    final liked = !before.liked;
    _replace(
      i,
      before.copyWith(
        liked: liked,
        likeCount: (before.likeCount + (liked ? 1 : -1)).clamp(0, 1 << 30),
      ),
    );
    try {
      final count = liked
          ? await _repo.like(before.id)
          : await _repo.unlike(before.id);
      _replace(i, _videos[i].copyWith(likeCount: count));
    } catch (_) {
      _replace(i, before);
    }
  }

  Future<void> _toggleFollow(int i) async {
    if (!_requireLogin()) return;
    final before = _videos[i];
    // Khớp ngữ nghĩa nút (+) của feed: có shop → theo dõi SHOP; ngược lại creator.
    if (before.hasShop) {
      await _toggleShopFollow(before.shopId!, before.shopSlug!);
    } else {
      await _toggleCreatorFollow(before.userId);
    }
  }

  Future<void> _toggleCreatorFollow(String userId) async {
    final f = !_videos.firstWhere((v) => v.userId == userId).following;
    for (var j = 0; j < _videos.length; j++) {
      if (_videos[j].userId == userId)
        _videos[j] = _videos[j].copyWith(following: f);
    }
    setState(() {});
    try {
      final res = f ? await _repo.follow(userId) : await _repo.unfollow(userId);
      if (res != f) {
        for (var j = 0; j < _videos.length; j++) {
          if (_videos[j].userId == userId)
            _videos[j] = _videos[j].copyWith(following: res);
        }
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _toggleShopFollow(String shopId, String slug) async {
    final f = !_videos.firstWhere((v) => v.shopId == shopId).shopFollowing;
    for (var j = 0; j < _videos.length; j++) {
      if (_videos[j].shopId == shopId)
        _videos[j] = _videos[j].copyWith(shopFollowing: f);
    }
    setState(() {});
    try {
      final res = f
          ? await _repo.followShop(slug)
          : await _repo.unfollowShop(slug);
      if (res != f) {
        for (var j = 0; j < _videos.length; j++) {
          if (_videos[j].shopId == shopId)
            _videos[j] = _videos[j].copyWith(shopFollowing: res);
        }
        setState(() {});
      }
    } catch (_) {}
  }

  void _comment(int i) {
    final v = _videos[i];
    showVideoCommentSheet(
      context,
      videoId: v.id,
      commentCount: v.commentCount,
      video: v,
      onAdded: () => _replace(
        i,
        _videos[i].copyWith(commentCount: _videos[i].commentCount + 1),
      ),
    );
  }

  Future<void> _share(int i) async {
    final v = _videos[i];
    await Share.share(
      'Xem video của @${v.displayName} trên Tropia\n${v.playUrl}',
    );
    _replace(i, _videos[i].copyWith(shareCount: _videos[i].shareCount + 1));
    await _repo.incShare(v.id);
  }

  // Nút "..." (Xem thêm) → share sheet kiểu Shopee (navigate10).
  void _more(int i) {
    final v = _videos[i];
    final isOwner = AuthService.instance.currentUser?.id == v.userId;
    showVideoShareSheet(
      context,
      video: v,
      isOwner: isOwner,
      onShared: () {
        _replace(i, _videos[i].copyWith(shareCount: _videos[i].shareCount + 1));
        _repo.incShare(v.id);
      },
      onDeleted: () => _onDeleted(i),
    );
  }

  /// Gỡ video vừa xóa khỏi trình xem; báo lưới cha gỡ theo. Hết video → đóng
  /// trình xem.
  void _onDeleted(int i) {
    if (i < 0 || i >= _videos.length) return;
    widget.onVideoDeleted?.call(_videos[i].id);
    setState(() {
      _videos.removeAt(i);
      if (_activeIndex >= _videos.length) {
        _activeIndex = (_videos.length - 1).clamp(0, 1 << 30);
      }
    });
    if (_videos.isEmpty) Navigator.of(context).maybePop();
  }

  Future<void> _addToCart(VideoPost v, VideoProduct p) async {
    if (p.slug.isEmpty) return;
    if (!_requireLogin()) return;
    final added = await showVideoAddToCartSheet(
      context,
      product: p,
      shopId: v.shopId,
      shopHasVoucher: v.shopHasVoucher,
    );
    if (added && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Đã thêm vào giỏ hàng')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _videos.length,
            onPageChanged: (i) => setState(() => _activeIndex = i),
            itemBuilder: (_, i) {
              final v = _videos[i];
              return VideoPlayerItem(
                key: ValueKey(v.id),
                video: v,
                isActive: i == _activeIndex,
                onLike: () => _toggleLike(i),
                onComment: () => _comment(i),
                onShare: () => _share(i),
                onMore: () => _more(i),
                onFollow: () => _toggleFollow(i),
                onOpenProfile: () {}, // already on this creator
                onReport: () => showVideoReportSheet(context, videoId: v.id),
                onOpenProduct: (p) {
                  if (p.slug.isEmpty) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ProductDetailScreen(slug: p.slug),
                    ),
                  );
                },
                onAddToCart: (p) => _addToCart(v, p),
                onViewed: () => _repo.incView(v.id),
              );
            },
          ),
          SafeArea(
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}
