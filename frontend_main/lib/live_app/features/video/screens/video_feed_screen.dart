// =============================================================================
// video_feed_screen.dart
// =============================================================================
// Feed "video đề xuất" dạng dọc (Shopee Video / TikTok). Đây là nội dung của
// tab "Video" trong màn Live & Video dùng chung.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/product/screens/product_detail_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/user/screens/login_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/providers/video_provider.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/screens/creator_profile_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_add_to_cart_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_comment_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_player_item.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_report_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_share_sheet.dart';

const _tag = 'VideoFeedScreen';

class VideoFeedScreen extends StatefulWidget {
  const VideoFeedScreen({super.key});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen>
    with AutomaticKeepAliveClientMixin {
  final PageController _pageController = PageController();
  int _activeIndex = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VideoProvider>().ensureLoaded();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _requireLogin() {
    if (AuthService.instance.isSignedIn) return true;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng nhập để tiếp tục'),
        content: const Text('Bạn cần đăng nhập để tương tác với video.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Đăng nhập'),
          ),
        ],
      ),
    );
    return false;
  }

  void _onLike(VideoPost v) {
    if (!_requireLogin()) return;
    context.read<VideoProvider>().toggleLike(v.id);
  }

  void _onFollow(VideoPost v) {
    if (!_requireLogin()) return;
    // Có shop → theo dõi shop; video cá nhân → fallback theo dõi creator.
    context.read<VideoProvider>().toggleFollowForVideo(v.id);
  }

  void _onComment(VideoPost v) {
    showVideoCommentSheet(
      context,
      videoId: v.id,
      commentCount: v.commentCount,
      video: v,
      onAdded: () => context.read<VideoProvider>().bumpCommentCount(v.id),
    );
  }

  Future<void> _onShare(VideoPost v) async {
    AppLogger.logUserEvent(
      action: 'video_share',
      context: _tag,
      metadata: {'videoId': v.id},
    );
    final caption = v.caption?.isNotEmpty ?? false ? '\n${v.caption}' : '';
    await Share.share(
      'Xem video của @${v.displayName} trên Tropia$caption\n${v.playUrl}',
    );
    if (mounted) context.read<VideoProvider>().registerShare(v.id);
  }

  // Nút "..." (Xem thêm) → share sheet kiểu Shopee (navigate10).
  void _onMore(VideoPost v) {
    AppLogger.logUserEvent(
      action: 'video_more_tapped',
      context: _tag,
      metadata: {'videoId': v.id},
    );
    final isOwner = AuthService.instance.currentUser?.id == v.userId;
    showVideoShareSheet(
      context,
      video: v,
      isOwner: isOwner,
      onShared: () => context.read<VideoProvider>().registerShare(v.id),
      onDeleted: () => context.read<VideoProvider>().remove(v.id),
    );
  }

  void _onOpenProfile(VideoPost v) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreatorProfileScreen(
          userId: v.userId,
          displayName: v.displayName,
          avatarUrl: v.avatarUrl,
          following: v.following,
        ),
      ),
    );
  }

  void _onOpenProduct(VideoProduct p) {
    if (p.slug.isEmpty) return;
    AppLogger.logUserEvent(
      action: 'video_product_tap',
      context: _tag,
      metadata: {'productId': p.productId, 'slug': p.slug},
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(slug: p.slug),
      ),
    );
  }

  Future<void> _onAddToCart(VideoPost v, VideoProduct p) async {
    if (p.slug.isEmpty) return;
    if (!_requireLogin()) return;
    AppLogger.logUserEvent(
      action: 'video_add_to_cart_tap',
      context: _tag,
      metadata: {'productId': p.productId, 'slug': p.slug},
    );
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
    super.build(context);
    return Container(
      color: Colors.black,
      child: Consumer<VideoProvider>(
        builder: (context, provider, _) {
          if (provider.isLoading && provider.feed.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            );
          }
          if (provider.error != null && provider.feed.isEmpty) {
            return _ErrorState(
              message: provider.error!,
              onRetry: provider.loadFeed,
            );
          }
          if (provider.feed.isEmpty) {
            return _EmptyState(onRefresh: provider.loadFeed);
          }
          final videos = provider.feed;
          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: provider.refresh,
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount: videos.length,
              onPageChanged: (i) {
                setState(() => _activeIndex = i);
                // Prefetch khi gần cuối.
                if (i >= videos.length - 2) provider.loadMore();
              },
              itemBuilder: (context, i) {
                final v = videos[i];
                return VideoPlayerItem(
                  key: ValueKey(v.id),
                  video: v,
                  isActive: i == _activeIndex,
                  onLike: () => _onLike(v),
                  onComment: () => _onComment(v),
                  onShare: () => _onShare(v),
                  onMore: () => _onMore(v),
                  onFollow: () => _onFollow(v),
                  onOpenProfile: () => _onOpenProfile(v),
                  onReport: () => showVideoReportSheet(context, videoId: v.id),
                  onOpenProduct: _onOpenProduct,
                  onAddToCart: (p) => _onAddToCart(v, p),
                  onViewed: () => provider.registerView(v.id),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Future<void> Function() onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: AppSizes.iconXl,
            color: Colors.white30,
          ),
          const SizedBox(height: AppSizes.md),
          const Text(
            'Chưa có video nào',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontLg,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          const Text(
            'Quay lại sau để xem video đề xuất',
            style: TextStyle(color: Colors.white54, fontSize: AppSizes.fontSm),
          ),
          const SizedBox(height: AppSizes.md),
          OutlinedButton.icon(
            onPressed: onRefresh,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
            ),
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Tải lại'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.signal_wifi_bad,
            size: AppSizes.iconXl,
            color: Colors.white30,
          ),
          const SizedBox(height: AppSizes.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.xl),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: AppSizes.fontMd,
              ),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}
