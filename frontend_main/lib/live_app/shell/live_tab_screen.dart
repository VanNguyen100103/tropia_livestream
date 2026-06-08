import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/models/live_stream_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/providers/live_provider.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/screens/live_setup_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/screens/live_stream_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/widgets/live_card_widget.dart';
import 'package:tropia_mobile_app_android/live_app/features/user/providers/user_provider.dart';
import 'package:tropia_mobile_app_android/live_app/features/user/screens/login_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/user/screens/my_profile_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/providers/video_provider.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/screens/video_create_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/screens/video_feed_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/flashsale/screens/flash_sale_admin_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/screens/video_reports_admin_screen.dart';
import 'package:tropia_mobile_app_android/live_app/shell/live_tab_entry.dart'
    show liveScope;

const _tag = 'LiveTabScreen';

class LiveTabScreen extends StatefulWidget {
  const LiveTabScreen({super.key});

  @override
  State<LiveTabScreen> createState() => _LiveTabScreenState();
}

class _LiveTabScreenState extends State<LiveTabScreen>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  late TabController _tabController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 3 tabs: Video | Live | Theo dõi. Order matches LiveTab enum so
    // the index lookup below works without a manual mapping.
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      final tab = LiveTab.values[_tabController.index];
      // Gate the "Theo dõi" tab behind login — otherwise an anonymous
      // viewer would just see an empty list with no explanation. Bounce
      // them back to Live and prompt for login.
      if (tab == LiveTab.following && !AuthService.instance.isSignedIn) {
        _tabController.animateTo(1);
        _promptLoginForFollowing();
        return;
      }
      context.read<LiveProvider>().setActiveTab(tab);
      // Rebuild so the body swaps between the video feed (tab Video) and the
      // live stream list (tab Live / Theo dõi).
      if (mounted) setState(() {});
    });
  }

  void _promptLoginForFollowing() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng nhập để xem shop đang theo dõi'),
        content: const Text(
          'Bạn cần đăng nhập để xem các buổi live từ những shop bạn đã theo dõi.',
        ),
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
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Biểu tượng user (góc trên trái) → mở hồ sơ cá nhân. Khách chưa đăng nhập →
  // mời đăng nhập trước. Route được bọc liveScope để MyProfileScreen truy cập
  // UserProvider/VideoProvider khi đăng video.
  void _openProfile() {
    AppLogger.logUserEvent(action: 'open_profile_tapped', context: _tag);
    if (!AuthService.instance.isSignedIn) {
      _promptLoginForFollowing();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => liveScope(context, const MyProfileScreen()),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // Màu status bar trắng (nền AppBar tối)
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            _buildTopBar(),
            _buildTabBar(),
            Expanded(
              // Tab "Video" → feed video ngắn (Shopee Video). Tab "Live" /
              // "Theo dõi" → danh sách livestream như cũ.
              child: _tabController.index == LiveTab.video.index
                  ? const VideoFeedScreen()
                  : Consumer<LiveProvider>(
                      builder: (context, provider, _) {
                        if (provider.isLoading) return _buildLoadingState();
                        if (provider.errorMessage != null)
                          return _buildErrorState(provider);
                        final streams = provider.filteredStreams;
                        if (streams.isEmpty) return _buildEmptyState();
                        return _buildContent(streams, provider);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top bar (Shopee style: dark, icons left + right, tabs center) ──────────

  Widget _buildTopBar() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      color: Colors.black,
      padding: EdgeInsets.only(
        top: topPadding,
        left: AppSizes.sm,
        right: AppSizes.sm,
      ),
      height: topPadding + 52,
      child: Row(
        children: [
          // Bên trái: avatar user + search
          IconButton(
            icon: const Icon(Icons.person_outline, color: Colors.white),
            onPressed: _openProfile,
          ),
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {},
          ),
          // Giữa: placeholder (tabs ở dưới)
          const Spacer(),
          // Admin: vào hàng đợi kiểm duyệt video (báo cáo).
          // Admin: kiểm duyệt video + tạo/quản lý Flash Sale.
          if (AuthService.instance.currentUser?.role == 'admin') ...[
            IconButton(
              tooltip: 'Kiểm duyệt video',
              icon: const Icon(Icons.shield_outlined, color: Colors.white),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const VideoReportsAdminScreen(),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Flash Sale',
              icon: const Icon(Icons.bolt, color: Colors.white),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const FlashSaleAdminScreen(),
                ),
              ),
            ),
          ],
          // Bên phải: nút "+" tạo video (Shopee style) — luôn hiển thị, chặn
          // quyền khi nhấn. Kèm nút "Live" cho chủ shop / nhân viên được duyệt.
          _buildCreateVideoButton(),
          if (context.watch<UserProvider>().canHostLive) ...[
            const SizedBox(width: AppSizes.sm),
            _buildGoLiveButton(),
          ],
        ],
      ),
    );
  }

  // Nút "+" tạo video — Shopee hiển thị cho mọi người; quyền đăng được kiểm tra
  // khi nhấn (chủ shop / nhân viên được duyệt / admin).
  Widget _buildCreateVideoButton() {
    return IconButton(
      tooltip: 'Tạo video',
      icon: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Icon(Icons.add, color: Colors.white, size: 18),
      ),
      onPressed: _onCreateVideo,
    );
  }

  Widget _buildGoLiveButton() {
    return GestureDetector(
      onTap: () {
        AppLogger.logUserEvent(action: 'go_live_tapped', context: _tag);
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            // Re-provide the Live tab's provider scope — this route is pushed
            // onto the root Navigator, outside LiveTabEntry's MultiProvider, so
            // LiveSetupScreen's Consumer<LiveProvider> would otherwise crash.
            builder: (_) => liveScope(context, const LiveSetupScreen()),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54),
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.live_tv, color: Colors.white, size: 15),
            SizedBox(width: 4),
            Text(
              'Live',
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Mở luồng tạo video. Khách chưa đăng nhập → mời đăng nhập; user không có
  // quyền đăng → báo cần được chủ shop duyệt (backend cũng enforce qua liveGate).
  void _onCreateVideo() {
    AppLogger.logUserEvent(action: 'create_video_tapped', context: _tag);
    if (!AuthService.instance.isSignedIn) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Đăng nhập để đăng video'),
          content: const Text('Bạn cần đăng nhập để đăng video.'),
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
      return;
    }
    if (!context.read<UserProvider>().canHostLive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tài khoản chưa được cấp quyền đăng video. Liên hệ chủ shop để được duyệt.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context)
        .push<VideoPost>(
          MaterialPageRoute<VideoPost>(
            builder: (_) => const VideoCreateScreen(),
          ),
        )
        .then((post) {
          if (post != null && mounted) {
            context.read<VideoProvider>().prepend(post);
            _tabController.animateTo(LiveTab.video.index);
          }
        });
  }

  // ── Tab bar (Video | ● Live | Theo dõi) – nền đen ─────────────────────────

  Widget _buildTabBar() {
    return Container(
      color: Colors.black,
      child: TabBar(
        controller: _tabController,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white54,
        indicatorColor: Colors.white,
        indicatorWeight: 2.5,
        indicatorSize: TabBarIndicatorSize.label,
        labelStyle: const TextStyle(
          fontSize: AppSizes.fontMd,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: AppSizes.fontMd,
          fontWeight: FontWeight.w400,
        ),
        isScrollable: true,
        tabAlignment: TabAlignment.center,
        tabs: [
          const Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.play_circle_outline, size: 15),
                SizedBox(width: 4),
                Text(AppStrings.liveTabVideo),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 4),
                  decoration: const BoxDecoration(
                    color: AppColors.liveRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const Text(AppStrings.liveTabLive),
              ],
            ),
          ),
          // "Theo dõi" — Shopee-style. Shows a small counter next to the
          // label when there's at least one followed shop currently live,
          // so the user has a reason to glance at it.
          Tab(
            child: Consumer<LiveProvider>(
              builder: (_, p, __) {
                final liveFollowedCount = p.streams
                    .where(
                      (s) => s.isFollowing && s.status == StreamStatus.live,
                    )
                    .length;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(AppStrings.liveTabFollowing),
                    if (liveFollowedCount > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.liveRed,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$liveFollowedCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Content: followed row + grid ──────────────────────────────────────────

  Widget _buildContent(List<LiveStream> streams, LiveProvider provider) {
    // Shops đang được follow và đang live (dùng cho hàng avatar trên)
    final followedLive = streams
        .where((s) => s.isFollowing && s.status == StreamStatus.live)
        .toList();

    return Container(
      color: AppColors.background,
      child: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () => context.read<LiveProvider>().refresh(),
        child: CustomScrollView(
          // Stable keys on every sliver so the card list (and the muted
          // preview players inside it) survive a rebuild when the followed-
          // shops row / live banner appear or disappear between refreshes.
          // Without keys, toggling those leading slivers shifts positions →
          // the keyless SliverList gets matched to the wrong slot → its
          // whole subtree remounts → HlsViewerWeb restarts from segment 0
          // → the "reload thumbnail 2-3 lần" flicker.
          slivers: [
            // Hàng followed shops đang live (chỉ tab Live)
            if (_tabController.index == 1 && followedLive.isNotEmpty)
              SliverToBoxAdapter(
                key: const ValueKey('followed-shops-row'),
                child: _FollowedShopsRow(
                  streams: followedLive,
                  onTap: _openStream,
                ),
              ),

            // Banner số buổi live (chỉ tab Live)
            if (_tabController.index == 1)
              SliverToBoxAdapter(
                key: const ValueKey('live-now-banner'),
                child: _buildLiveNowBanner(
                  streams.where((s) => s.status == StreamStatus.live).length,
                ),
              ),

            // List card full-width (Shopee style)
            SliverList(
              key: const ValueKey('live-card-list'),
              delegate: SliverChildBuilderDelegate(
                (context, index) => Column(
                  key: ValueKey('live-card-${streams[index].id}'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LiveCardWidget(
                      stream: streams[index],
                      onTap: () => _openStream(streams[index]),
                      onFollowTap: () => context
                          .read<LiveProvider>()
                          .toggleFollow(streams[index].id),
                    ),
                    const Divider(
                      height: 8,
                      thickness: 8,
                      color: AppColors.background,
                    ),
                  ],
                ),
                childCount: streams.length,
                // Map a child's key back to its index so the builder reuses
                // the right element when the list order/length shifts.
                findChildIndexCallback: (Key key) {
                  if (key is ValueKey<String>) {
                    final id = key.value.replaceFirst('live-card-', '');
                    final idx = streams.indexWhere((s) => s.id == id);
                    return idx == -1 ? null : idx;
                  }
                  return null;
                },
              ),
            ),
            const SliverToBoxAdapter(
              key: ValueKey('bottom-padding'),
              child: SizedBox(height: AppSizes.xxl),
            ),
          ],
        ),
      ),
    );
  }

  // ── Live now banner ────────────────────────────────────────────────────────

  Widget _buildLiveNowBanner(int liveCount) {
    if (liveCount == 0) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        0,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.md,
        vertical: AppSizes.sm,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.sm,
              vertical: 2,
            ),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.liveRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: AppSizes.xs),
                const Text(
                  'ĐANG PHÁT',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.fontXs,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Text(
            '$liveCount buổi live đang diễn ra',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontSm,
            ),
          ),
          const Spacer(),
          const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 13),
        ],
      ),
    );
  }

  // ── Loading shimmer ────────────────────────────────────────────────────────

  Widget _buildLoadingState() {
    return Container(
      color: AppColors.background,
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: ListView.separated(
          padding: EdgeInsets.zero,
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.md,
                  AppSizes.sm,
                  AppSizes.md,
                  AppSizes.xs,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 14,
                            width: 120,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 6),
                          Container(height: 10, width: 80, color: Colors.white),
                        ],
                      ),
                    ),
                    Container(
                      height: 30,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(
                          AppSizes.radiusFull,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildErrorState(LiveProvider provider) {
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.signal_wifi_bad,
              size: AppSizes.iconXl,
              color: AppColors.textHint,
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              provider.errorMessage ?? AppStrings.liveError,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppSizes.fontMd,
              ),
            ),
            const SizedBox(height: AppSizes.lg),
            FilledButton.icon(
              onPressed: () => context.read<LiveProvider>().refresh(),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              icon: const Icon(Icons.refresh),
              label: const Text(AppStrings.actionRetry),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    // Custom copy for the "Theo dõi" tab so the user understands why the
    // list is empty (no follows yet) instead of "no live happening".
    final isFollowing = _tabController.index == LiveTab.following.index;
    return Container(
      color: AppColors.background,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isFollowing ? Icons.favorite_border : Icons.live_tv_outlined,
              size: AppSizes.iconXl,
              color: AppColors.textHint,
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              isFollowing ? 'Bạn chưa theo dõi shop nào' : AppStrings.liveEmpty,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppSizes.fontLg,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              isFollowing
                  ? 'Theo dõi shop để cập nhật khi họ phát live'
                  : 'Quay lại sau để xem các buổi live tiếp theo',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppSizes.fontSm,
              ),
            ),
            if (isFollowing) ...[
              const SizedBox(height: AppSizes.md),
              FilledButton.icon(
                onPressed: () => _tabController.animateTo(1),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: const Text('Khám phá live'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Open stream ────────────────────────────────────────────────────────────

  void _openStream(LiveStream stream) {
    AppLogger.logUserEvent(
      action: 'live_card_tapped',
      context: _tag,
      metadata: {'streamId': stream.id, 'sellerName': stream.sellerName},
    );

    if (!AuthService.instance.isSignedIn) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Đăng nhập để xem live'),
          content: const Text(
            'Bạn cần đăng nhập để xem livestream và tương tác với người bán.',
          ),
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
      return;
    }

    Navigator.of(context).push(
      PageRouteBuilder<void>(
        // Same scope re-provide as the host route above (viewer screen also
        // reads LiveProvider).
        pageBuilder: (_, __, ___) =>
            liveScope(context, LiveStreamScreen(streamId: stream.id)),
        transitionsBuilder: (_, animation, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
              .animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
          child: child,
        ),
        transitionDuration: AppDurations.slow,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hàng avatar "Shop đang follow đang live" — như Shopee
// ─────────────────────────────────────────────────────────────────────────────

class _FollowedShopsRow extends StatelessWidget {
  final List<LiveStream> streams;
  final void Function(LiveStream) onTap;

  const _FollowedShopsRow({required this.streams, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSizes.md,
              bottom: AppSizes.sm,
            ),
            child: Row(
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    color: AppColors.liveRed,
                    shape: BoxShape.circle,
                  ),
                ),
                const Text(
                  'Shop bạn theo dõi đang live',
                  style: TextStyle(
                    fontSize: AppSizes.fontSm,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
              itemCount: streams.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSizes.md),
              itemBuilder: (context, i) => _FollowedShopAvatar(
                stream: streams[i],
                onTap: () => onTap(streams[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FollowedShopAvatar extends StatelessWidget {
  final LiveStream stream;
  final VoidCallback onTap;

  const _FollowedShopAvatar({required this.stream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Avatar với ring đỏ LIVE
            Stack(
              alignment: Alignment.center,
              children: [
                // Ring đỏ gradient
                Container(
                  width: 66,
                  height: 66,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [AppColors.liveRed, Color(0xFFFF6B35)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
                // Ring trắng cách ly
                Container(
                  width: 61,
                  height: 61,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                ),
                // Avatar
                ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: stream.sellerAvatarUrl,
                    width: 57,
                    height: 57,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 57,
                      height: 57,
                      color: AppColors.primaryContainer,
                      child: const Icon(
                        Icons.storefront,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                  ),
                ),
                // Badge LIVE đỏ bên dưới avatar
                Positioned(
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.liveRed,
                      borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                    ),
                    child: const Text(
                      'LIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            // Tên shop
            Text(
              stream.sellerName,
              style: const TextStyle(
                fontSize: AppSizes.fontXs,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
