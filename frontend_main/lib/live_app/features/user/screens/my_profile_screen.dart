// =============================================================================
// my_profile_screen.dart  ("hồ sơ" — mở khi nhấn biểu tượng user ở tab Live & Video)
// =============================================================================
// Trang cá nhân kiểu Shopee Video / TikTok cho user đang đăng nhập:
//   - Header: avatar + 3 chỉ số (đang theo dõi / người theo dõi / lượt thích)
//   - Tên + tên tài khoản (@handle)
//   - 2 nút: "Sửa hồ sơ" và "Kênh Người sáng tạo"
//   - TabBar: Video | Live | Đã thích  → lưới video của tôi
//   - FAB "+ Đăng video" mở luồng tạo video (navigate2/3)
//
// Tự nạp dữ liệu qua [VideoRepository] + [AuthService] (giống CreatorProfile).
// Cần được push trong [liveScope] để truy cập UserProvider/VideoProvider khi
// đăng video.
// =============================================================================

import 'dart:async';
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

import 'package:tropia_mobile_app_android/live_app/core/config/app_config.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/data/live_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/screens/vod_replay_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/product/screens/product_detail_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/shop/screens/seller_dashboard_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/user/providers/user_provider.dart';
import 'package:tropia_mobile_app_android/live_app/features/user/screens/login_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/data/video_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/providers/video_provider.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/screens/creator_profile_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/screens/video_create_screen.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_add_to_cart_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_comment_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_player_item.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_report_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/video_share_sheet.dart';
import 'package:tropia_mobile_app_android/live_app/shell/live_tab_entry.dart' show liveScope;

const _tag = 'MyProfileScreen';

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen>
    with SingleTickerProviderStateMixin {
  final _repo = VideoRepository();
  final _liveRepo = LiveRepository.instance;
  late final TabController _tabController = TabController(length: 3, vsync: this);
  List<VideoPost> _videos = [];
  // Tab "Đã thích" — video user đã tim. Tab "Live" — buổi live đã kết thúc của
  // chính user đã có bản ghi (replay). Cùng nạp trong _load().
  List<VideoPost> _liked = [];
  List<LiveReplay> _replays = [];
  bool _loading = true;

  // Chỉ số follow lấy từ backend (GET /api/videos/me/stats) — gộp shop_follows
  // + user_follows nên khớp với tab Live "Theo dõi". null = chưa nạp xong.
  int _following = 0;
  int _followers = 0;
  int? _serverLikes;

  AuthUser? get _user => AuthService.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // 4 nguồn (video / đã thích / replay / chỉ số follow) nạp song song — lỗi
    // một cái không che cái kia, và tab Live không phải chờ tab Video.
    await Future.wait([
      _repo
          .fetchMyVideos()
          .then((list) {
            if (mounted) setState(() => _videos = list);
          })
          .catchError((_) {}),
      _repo
          .fetchLikedVideos()
          .then((list) {
            if (mounted) setState(() => _liked = list);
          })
          .catchError((_) {}),
      _liveRepo
          .fetchMyReplays()
          .then((rows) {
            if (mounted) {
              setState(() => _replays = rows.map(LiveReplay.fromJson).toList());
            }
          })
          .catchError((_) {}),
      _repo
          .fetchMyStats()
          .then((s) {
            if (mounted) {
              setState(() {
                _following = s.following;
                _followers = s.followers;
                _serverLikes = s.likes;
              });
            }
          })
          .catchError((_) {}),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  // Tổng lượt thích: ưu tiên số từ backend (cộng toàn bộ video); chưa có thì
  // tạm cộng like_count của các video đã nạp.
  int get _totalLikes =>
      _serverLikes ?? _videos.fold(0, (sum, v) => sum + v.likeCount);

  String _handle(AuthUser u) {
    final fromEmail = u.email.split('@').first;
    return fromEmail.isNotEmpty ? fromEmail : u.id.replaceAll('-', '');
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  void _openViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MyVideosViewer(
          repo: _repo,
          videos: List.of(_videos),
          initialIndex: index,
          onVideoDeleted: _removeVideo,
        ),
      ),
    );
  }

  /// Gỡ video khỏi lưới hồ sơ sau khi nó bị xóa trong trình xem (đồng bộ).
  void _removeVideo(String id) {
    if (!mounted) return;
    setState(() => _videos = _videos.where((v) => v.id != id).toList());
  }

  // Kênh Người sáng tạo — seller có cửa hàng → mở dashboard; còn lại báo sắp có.
  void _openCreatorChannel() {
    AppLogger.logUserEvent(action: 'tap_creator_channel', context: _tag);
    if (_user?.isSeller ?? false) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => liveScope(context, const SellerDashboardScreen()),
        ),
      );
    } else {
      _toast('Bạn cần là Người sáng tạo / chủ shop để mở kênh này');
    }
  }

  Future<void> _onCreateVideo() async {
    AppLogger.logUserEvent(action: 'create_video_tapped', context: _tag);
    if (!AuthService.instance.isSignedIn) return;
    if (!context.read<UserProvider>().canHostLive) {
      _toast(
        'Tài khoản chưa được cấp quyền đăng video. Liên hệ chủ shop để được duyệt.',
      );
      return;
    }
    final post = await Navigator.of(context).push<VideoPost>(
      MaterialPageRoute<VideoPost>(builder: (_) => const VideoCreateScreen()),
    );
    if (post != null && mounted) {
      context.read<VideoProvider>().prepend(post);
      setState(() => _videos = [post, ..._videos]);
    }
  }

  void _shareProfile() {
    final u = _user;
    if (u == null) return;
    Share.share('Theo dõi ${u.name} trên Tropia Video!');
  }

  @override
  Widget build(BuildContext context) {
    final user = _user;
    if (user == null) return _buildNotSignedIn();

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(child: _buildHeaderBar()),
            SliverToBoxAdapter(child: _buildProfileHeader(user)),
            SliverToBoxAdapter(child: _buildActionButtons()),
            SliverPersistentHeader(
              pinned: true,
              delegate: _TabBarDelegate(
                TabBar(
                  controller: _tabController,
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.textPrimary,
                  indicatorSize: TabBarIndicatorSize.label,
                  labelStyle: const TextStyle(
                    fontSize: AppSizes.fontMd,
                    fontWeight: FontWeight.w700,
                  ),
                  tabs: const [
                    Tab(text: 'Video'),
                    Tab(text: 'Live'),
                    Tab(text: 'Đã thích'),
                  ],
                ),
              ),
            ),
          ],
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildVideoGrid(),
              _buildReplayGrid(),
              _buildLikedGrid(),
            ],
          ),
        ),
      ),
      floatingActionButton: _buildPostVideoFab(),
    );
  }

  // ── Top bar: back / share / menu ───────────────────────────────────────────

  Widget _buildHeaderBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs, vertical: AppSizes.xs),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.ios_share, color: AppColors.textPrimary),
            onPressed: _shareProfile,
          ),
          IconButton(
            icon: const Icon(Icons.menu, color: AppColors.textPrimary),
            onPressed: _showMenuSheet,
          ),
        ],
      ),
    );
  }

  void _showMenuSheet() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.radiusLg)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Cài đặt'),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('Chia sẻ hồ sơ'),
              onTap: () {
                Navigator.pop(context);
                _shareProfile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.error),
              title: const Text('Đăng xuất', style: TextStyle(color: AppColors.error)),
              onTap: () async {
                Navigator.pop(context);
                await AuthService.instance.logout();
                if (mounted) Navigator.of(context).maybePop();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Profile header: avatar + stats + name ──────────────────────────────────

  Widget _buildProfileHeader(AuthUser user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.xs, AppSizes.md, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: AppColors.surfaceVariant,
                backgroundImage: user.avatarUrl != null
                    ? CachedNetworkImageProvider(user.avatarUrl!)
                    : null,
                child: user.avatarUrl == null
                    ? const Icon(Icons.person, size: 48, color: AppColors.textHint)
                    : null,
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StatItem(value: _following, label: 'Người đang\ntheo dõi'),
                    _StatItem(value: _followers, label: 'Người theo\ndõi'),
                    _StatItem(value: _totalLikes, label: 'Lượt thích'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          Text(
            user.name,
            style: const TextStyle(
              fontSize: AppSizes.fontXxl,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tên tài khoản: ${_handle(user)}',
            style: const TextStyle(
              fontSize: AppSizes.fontSm,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Sửa hồ sơ / Kênh Người sáng tạo ────────────────────────────────────────

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.md, AppSizes.md, AppSizes.md),
      child: Row(
        children: [
          Expanded(
            child: _OutlinedAction(
              icon: Icons.edit_outlined,
              label: 'Sửa hồ sơ',
              onTap: () {
                AppLogger.logUserEvent(action: 'tap_edit_profile', context: _tag);
                _toast('Tính năng sửa hồ sơ sắp ra mắt');
              },
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: _OutlinedAction(
              icon: Icons.dashboard_customize_outlined,
              label: 'Kênh Người sáng tạo',
              showDot: true,
              onTap: _openCreatorChannel,
            ),
          ),
        ],
      ),
    );
  }

  // ── Tab Video: lưới video của tôi ──────────────────────────────────────────

  Widget _buildVideoGrid() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_videos.isEmpty) {
      return _buildEmptyTab(Icons.video_library_outlined, 'Chưa có video nào');
    }
    return GridView.builder(
      padding: const EdgeInsets.all(1.5),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1.5,
        crossAxisSpacing: 1.5,
        childAspectRatio: 0.7,
      ),
      itemCount: _videos.length,
      itemBuilder: (_, i) => _GridTile(video: _videos[i], onTap: () => _openViewer(i)),
    );
  }

  // ── Tab Đã thích: lưới video đã tim (card giống tab Video) ──────────────────

  Widget _buildLikedGrid() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_liked.isEmpty) {
      return _buildEmptyTab(Icons.favorite_border, 'Chưa có video đã thích');
    }
    return GridView.builder(
      padding: const EdgeInsets.all(1.5),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1.5,
        crossAxisSpacing: 1.5,
        childAspectRatio: 0.7,
      ),
      itemCount: _liked.length,
      itemBuilder: (_, i) =>
          _GridTile(video: _liked[i], onTap: () => _openLikedViewer(i)),
    );
  }

  void _openLikedViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MyVideosViewer(
          repo: _repo,
          videos: List.of(_liked),
          initialIndex: index,
          likedMode: true,
          onVideoDeleted: _removeLikedVideo,
        ),
      ),
    );
  }

  /// Gỡ video khỏi lưới "Đã thích" sau khi nó bị xóa trong trình xem.
  void _removeLikedVideo(String id) {
    if (!mounted) return;
    setState(() => _liked = _liked.where((v) => v.id != id).toList());
  }

  // ── Tab Live: lưới buổi live đã kết thúc (replay) của tôi ───────────────────

  Widget _buildReplayGrid() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_replays.isEmpty) {
      return _buildEmptyTab(Icons.live_tv_outlined, 'Chưa có buổi Live nào');
    }
    return GridView.builder(
      padding: const EdgeInsets.all(1.5),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 1.5,
        crossAxisSpacing: 1.5,
        childAspectRatio: 0.7,
      ),
      itemCount: _replays.length,
      itemBuilder: (_, i) =>
          _ReplayTile(replay: _replays[i], onTap: () => _openReplay(_replays[i])),
    );
  }

  void _openReplay(LiveReplay replay) {
    AppLogger.logUserEvent(action: 'open_my_replay', context: _tag);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            VodReplayScreen(sessionId: replay.id, title: replay.title),
      ),
    );
  }

  Widget _buildEmptyTab(IconData icon, String label) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: AppSizes.iconXl, color: AppColors.textHint),
          const SizedBox(height: AppSizes.sm),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildPostVideoFab() {
    return FloatingActionButton.extended(
      onPressed: _onCreateVideo,
      backgroundColor: AppColors.secondary,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.add),
      label: const Text(
        'Đăng video',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  // ── Chưa đăng nhập ─────────────────────────────────────────────────────────

  Widget _buildNotSignedIn() {
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_outline, size: 64, color: AppColors.textHint),
              const SizedBox(height: AppSizes.md),
              const Text(
                'Đăng nhập để xem hồ sơ của bạn',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSizes.lg),
              FilledButton(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
                ),
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Đăng nhập'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _StatItem extends StatelessWidget {
  final int value;
  final String label;
  const _StatItem({required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$value',
          style: const TextStyle(
            fontSize: AppSizes.fontXl,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: AppSizes.fontXs,
            color: AppColors.textSecondary,
            height: 1.15,
          ),
        ),
      ],
    );
  }
}

class _OutlinedAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showDot;
  const _OutlinedAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: AppColors.textPrimary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppSizes.fontSm,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (showDot) ...[
              const SizedBox(width: 4),
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
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
              errorWidget: (_, _, _) => _placeholder(),
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
    child: const Icon(Icons.play_circle_outline, color: Colors.white30, size: 32),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LiveReplay — 1 buổi live đã kết thúc đã có bản ghi (GET /api/live/replays).
// Chỉ giữ các trường lưới hồ sơ cần; URL ghép host qua AppConfig như video.
// ─────────────────────────────────────────────────────────────────────────────

class LiveReplay {
  final String id; // session uuid → dùng cho VodReplayScreen
  final String title;
  final String? coverImageUrl;
  final String? vodMp4Url; // bản ghi MP4 thật trên R2 — dùng trích frame bìa
  final int viewerCount;
  final int likeCount;

  const LiveReplay({
    required this.id,
    required this.title,
    this.coverImageUrl,
    this.vodMp4Url,
    this.viewerCount = 0,
    this.likeCount = 0,
  });

  /// URL ảnh bìa đã ghép host; null nếu không có / không phải http(s) hợp lệ.
  String? get coverUrl => _resolve(coverImageUrl);

  /// URL bản ghi MP4 đã ghép host — nguồn để trích frame đầu làm bìa khi
  /// seller không tự đặt ảnh bìa. null nếu không có / không hợp lệ.
  String? get vodUrl => _resolve(vodMp4Url);

  static String? _resolve(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final u = AppConfig.resolveBackendUrl(raw);
    return (u.startsWith('http://') || u.startsWith('https://')) ? u : null;
  }

  factory LiveReplay.fromJson(Map<String, dynamic> json) => LiveReplay(
    id: json['id'] as String? ?? '',
    title: (json['title'] as String?)?.trim().isNotEmpty == true
        ? json['title'] as String
        : 'Buổi live',
    coverImageUrl: json['cover_image_url'] as String?,
    vodMp4Url: json['vod_mp4_url'] as String?,
    viewerCount: (json['viewer_count'] as num?)?.toInt() ?? 0,
    likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bìa replay = frame đầu của bản ghi MP4 THẬT, trích ngay trên máy. KHÔNG ghi
// file, KHÔNG upload R2, KHÔNG lưu DB — chỉ cache trong RAM phiên này (yêu cầu:
// "lấy thật nhưng đừng lưu"). Một URL chỉ giải mã một lần; tab Live build lại
// vẫn lấy từ cache nên không decode lặp.
// ─────────────────────────────────────────────────────────────────────────────

class _ReplayThumbCache {
  static final Map<String, Uint8List?> _done = {};
  static final Map<String, Future<Uint8List?>> _inflight = {};

  // Throttle: chỉ trích vài frame cùng lúc. Cả lưới build một loạt ô rồi cùng
  // trích frame từ R2 sẽ làm nghẽn mạng → đa số fail/treo (đúng triệu chứng "ô
  // rỗng"). Xếp hàng 2 cái một thì cái nào cũng đủ băng thông và lần lượt hiện.
  static const _maxConcurrent = 2;
  static int _active = 0;
  static final List<_ThumbJob> _queue = [];

  static Future<Uint8List?> frame(String url) {
    if (_done.containsKey(url)) return Future.value(_done[url]);
    final existing = _inflight[url];
    if (existing != null) return existing;
    final completer = Completer<Uint8List?>();
    _inflight[url] = completer.future;
    _queue.add(_ThumbJob(url, completer));
    _pump();
    return completer.future;
  }

  static void _pump() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final job = _queue.removeAt(0);
      _active++;
      _generate(job.url).then(job.completer.complete).whenComplete(() {
        _active--;
        _inflight.remove(job.url);
        _pump();
      });
    }
  }

  static Future<Uint8List?> _generate(String url) async {
    // video_thumbnail dùng platform channel — web không hỗ trợ → để placeholder.
    if (kIsWeb) {
      _done[url] = null;
      return null;
    }
    try {
      // Timeout ở đây CHỈ để giải phóng chỗ trong hàng đợi nếu một URL hiếm hoi
      // bị treo (không phải để ẩn replay) — đặt rộng rãi để frame thật kịp lấy.
      final bytes = await VideoThumbnail.thumbnailData(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 360, // đủ nét cho ô lưới 1/3 màn hình, nhẹ băng thông
        quality: 60,
      ).timeout(const Duration(seconds: 20), onTimeout: () => null);
      final out = (bytes != null && bytes.isNotEmpty) ? bytes : null;
      _done[url] = out;
      return out;
    } catch (_) {
      // MP4 đã bị xoá khỏi R2 / mạng lỗi → null, rơi về placeholder.
      _done[url] = null;
      return null;
    }
  }
}

class _ThumbJob {
  final String url;
  final Completer<Uint8List?> completer;
  _ThumbJob(this.url, this.completer);
}

class _ReplayTile extends StatelessWidget {
  final LiveReplay replay;
  final VoidCallback onTap;
  const _ReplayTile({required this.replay, required this.onTap});

  // Nền ô: ưu tiên ảnh bìa seller đặt; không có thì trích frame đầu của bản
  // ghi MP4 thật (qua hàng đợi throttle để không bắn 1 loạt request tới R2).
  // Trong lúc chờ → ô loading trung tính; trích xong thì thay bằng frame thật.
  Widget _buildBackground() {
    final cover = replay.coverUrl;
    if (cover != null) {
      return CachedNetworkImage(
        imageUrl: cover,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => _vodFrame(),
      );
    }
    return _vodFrame();
  }

  Widget _vodFrame() {
    final vod = replay.vodUrl;
    if (vod == null) return _loadingBox();
    return FutureBuilder<Uint8List?>(
      future: _ReplayThumbCache.frame(vod),
      builder: (_, snap) {
        final bytes = snap.data;
        if (bytes != null) {
          return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
        }
        return _loadingBox();
      },
    );
  }

  Widget _loadingBox() => const ColoredBox(color: AppColors.surfaceVariant);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),
          // Mờ đáy cho dễ đọc badge + lượt xem.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.center,
                  colors: [Colors.black54, Colors.transparent],
                ),
              ),
            ),
          ),
          // Badge REPLAY góc trên trái.
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.liveRed,
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text(
                'REPLAY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  letterSpacing: .5,
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            bottom: 4,
            child: Row(
              children: [
                const Icon(Icons.play_arrow, color: Colors.white, size: 14),
                const SizedBox(width: 2),
                Text(
                  _fmt(replay.viewerCount),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// Trình xem dọc cho video của tôi (tái dùng VideoPlayerItem). "..." mở share sheet.
// ─────────────────────────────────────────────────────────────────────────────

class _MyVideosViewer extends StatefulWidget {
  final VideoRepository repo;
  final List<VideoPost> videos;
  final int initialIndex;
  // likedMode = true khi mở từ tab "Đã thích": các video có thể của người khác
  // → bật theo dõi + mở hồ sơ creator, và quyền xóa tính theo từng video. Mặc
  // định false (tab Video — toàn bộ là video của chính mình).
  final bool likedMode;
  final void Function(String id)? onVideoDeleted;
  const _MyVideosViewer({
    required this.repo,
    required this.videos,
    required this.initialIndex,
    this.likedMode = false,
    this.onVideoDeleted,
  });

  @override
  State<_MyVideosViewer> createState() => _MyVideosViewerState();
}

class _MyVideosViewerState extends State<_MyVideosViewer> {
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

  void _replace(int i, VideoPost v) => setState(() => _videos[i] = v);

  Future<void> _toggleLike(int i) async {
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
          ? await widget.repo.like(before.id)
          : await widget.repo.unlike(before.id);
      _replace(i, _videos[i].copyWith(likeCount: count));
    } catch (_) {
      _replace(i, before);
    }
  }

  void _comment(int i) {
    final v = _videos[i];
    showVideoCommentSheet(
      context,
      videoId: v.id,
      commentCount: v.commentCount,
      video: v,
      onAdded: () =>
          _replace(i, _videos[i].copyWith(commentCount: _videos[i].commentCount + 1)),
    );
  }

  Future<void> _share(int i) async {
    final v = _videos[i];
    await Share.share('Xem video của @${v.displayName} trên Tropia\n${v.playUrl}');
    _replace(i, _videos[i].copyWith(shareCount: _videos[i].shareCount + 1));
    await widget.repo.incShare(v.id);
  }

  // Chủ sở hữu tính theo từng video (tab Video: luôn của mình → true; tab Đã
  // thích: có thể của người khác → chỉ true với video của chính mình).
  bool _isOwner(VideoPost v) =>
      AuthService.instance.currentUser?.id == v.userId;

  void _more(int i) {
    final v = _videos[i];
    showVideoShareSheet(
      context,
      video: v,
      isOwner: _isOwner(v),
      onShared: () {
        _replace(i, _videos[i].copyWith(shareCount: _videos[i].shareCount + 1));
        widget.repo.incShare(v.id);
      },
      onDeleted: () => _onDeleted(i),
    );
  }

  // ── Theo dõi (chỉ dùng ở likedMode — video có thể của creator/shop khác) ────
  // Khớp ngữ nghĩa nút (+) của feed: có shop → theo dõi SHOP; ngược lại creator.

  Future<void> _toggleFollow(int i) async {
    final before = _videos[i];
    if (before.hasShop) {
      await _toggleShopFollow(before.shopId!, before.shopSlug!);
    } else {
      await _toggleCreatorFollow(before.userId);
    }
  }

  Future<void> _toggleCreatorFollow(String userId) async {
    final f = !_videos.firstWhere((v) => v.userId == userId).following;
    for (var j = 0; j < _videos.length; j++) {
      if (_videos[j].userId == userId) {
        _videos[j] = _videos[j].copyWith(following: f);
      }
    }
    setState(() {});
    try {
      final res =
          f ? await widget.repo.follow(userId) : await widget.repo.unfollow(userId);
      if (res != f) {
        for (var j = 0; j < _videos.length; j++) {
          if (_videos[j].userId == userId) {
            _videos[j] = _videos[j].copyWith(following: res);
          }
        }
        setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _toggleShopFollow(String shopId, String slug) async {
    final f = !_videos.firstWhere((v) => v.shopId == shopId).shopFollowing;
    for (var j = 0; j < _videos.length; j++) {
      if (_videos[j].shopId == shopId) {
        _videos[j] = _videos[j].copyWith(shopFollowing: f);
      }
    }
    setState(() {});
    try {
      final res = f
          ? await widget.repo.followShop(slug)
          : await widget.repo.unfollowShop(slug);
      if (res != f) {
        for (var j = 0; j < _videos.length; j++) {
          if (_videos[j].shopId == shopId) {
            _videos[j] = _videos[j].copyWith(shopFollowing: res);
          }
        }
        setState(() {});
      }
    } catch (_) {}
  }

  void _openCreator(VideoPost v) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CreatorProfileScreen(
          userId: v.userId,
          displayName: v.displayName,
          avatarUrl: v.avatarUrl,
          following: v.isFollowed,
        ),
      ),
    );
  }

  /// Gỡ video vừa xóa khỏi trình xem; báo lưới hồ sơ gỡ theo. Hết video → đóng
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
                // Tab Video: video của chính mình → không theo dõi / mở hồ sơ.
                // Tab Đã thích: có thể của người khác → bật theo dõi + mở creator.
                onFollow: widget.likedMode ? () => _toggleFollow(i) : () {},
                onOpenProfile: widget.likedMode ? () => _openCreator(v) : () {},
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
                onViewed: () => widget.repo.incView(v.id),
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

// Pinned TabBar trong NestedScrollView.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          Expanded(child: tabBar),
          const Divider(height: 1, thickness: 0.5),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_TabBarDelegate oldDelegate) => oldDelegate.tabBar != tabBar;
}

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}
