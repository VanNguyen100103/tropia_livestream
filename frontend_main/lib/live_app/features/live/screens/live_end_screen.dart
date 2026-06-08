import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/data/live_repository.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/screens/vod_replay_screen.dart';

const _tag = 'LiveEndScreen';

class LiveEndScreen extends StatefulWidget {
  final String title;
  final String sessionId;
  final int peakViewers;
  final int totalLikes;
  final int cartAddCount;
  final int followCount;

  const LiveEndScreen({
    super.key,
    required this.title,
    required this.sessionId,
    required this.peakViewers,
    required this.totalLikes,
    required this.cartAddCount,
    required this.followCount,
  });

  @override
  State<LiveEndScreen> createState() => _LiveEndScreenState();
}

class _LiveEndScreenState extends State<LiveEndScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;

  bool _analyzing = true;
  String? _sentiment;
  String? _summary;
  List<String> _tips = [];

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
    _runAnalysis();

    AppLogger.logUserEvent(
      action: 'live_end_screen_viewed',
      context: _tag,
      metadata: {
        'title': widget.title,
        'peakViewers': widget.peakViewers,
        'totalLikes': widget.totalLikes,
        'cartAddCount': widget.cartAddCount,
        'followCount': widget.followCount,
      },
    );
  }

  Future<void> _runAnalysis() async {
    final result = await LiveRepository.instance.analyzeLive(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _analyzing = false;
      if (result != null) {
        _sentiment = result['sentiment'] as String?;
        _summary   = result['summary']   as String?;
        _tips      = List<String>.from(result['tips'] as List? ?? []);
      }
      if (_tips.isEmpty) {
        _tips = [
          'Phát live vào khung 19:00–21:00 để có nhiều người xem nhất',
          'Ghim sản phẩm bán chạy trong 10 phút đầu để tăng chuyển đổi',
          'Giao tiếp liên tục với người xem để giữ chân họ lâu hơn',
          'Chuẩn bị voucher độc quyền cho buổi live tiếp theo',
        ];
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: FadeTransition(
        opacity: _fadeIn,
        child: SlideTransition(
          position: _slideUp,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
                  child: _buildStatsGrid(),
                ),
              ),
              SliverToBoxAdapter(child: _buildAnalysisSection()),
              SliverToBoxAdapter(child: _buildActions()),
              const SliverToBoxAdapter(child: SizedBox(height: AppSizes.xl)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + AppSizes.lg,
        left: AppSizes.md,
        right: AppSizes.md,
        bottom: AppSizes.xl,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🎉', style: TextStyle(fontSize: 36)),
            ),
          ),
          const SizedBox(height: AppSizes.md),
          const Text(
            'Tổng kết buổi Live',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXxl,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            widget.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: AppSizes.fontMd,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSizes.sm,
      crossAxisSpacing: AppSizes.sm,
      childAspectRatio: 1.8,
      padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
      children: [
        _StatCard(
          icon: Icons.visibility_outlined,
          iconColor: AppColors.primary,
          value: widget.peakViewers >= 1000
              ? '${(widget.peakViewers / 1000).toStringAsFixed(1)}K'
              : '${widget.peakViewers}',
          label: 'Lượt xem',
        ),
        _StatCard(
          icon: Icons.shopping_cart_outlined,
          iconColor: AppColors.secondary,
          value: '${widget.cartAddCount}',
          label: 'Thêm vào giỏ',
        ),
        _StatCard(
          icon: Icons.person_add_outlined,
          iconColor: AppColors.primaryLight,
          value: '${widget.followCount}',
          label: 'Theo dõi shop',
        ),
        _StatCard(
          icon: Icons.favorite_outline,
          iconColor: AppColors.error,
          value: widget.totalLikes >= 1000
              ? '${(widget.totalLikes / 1000).toStringAsFixed(1)}K'
              : '${widget.totalLikes}',
          label: 'Lượt thích',
        ),
      ],
    );
  }

  Widget _buildAnalysisSection() {
    return Container(
      margin: const EdgeInsets.all(AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: _analyzing ? _buildAnalyzingPlaceholder() : _buildAnalysisResult(),
    );
  }

  Widget _buildAnalyzingPlaceholder() {
    return const Column(
      children: [
        SizedBox(height: AppSizes.sm),
        CircularProgressIndicator(),
        SizedBox(height: AppSizes.md),
        Text(
          'Đang phân tích buổi live với DeepSeek AI...',
          style: TextStyle(color: AppColors.textSecondary, fontSize: AppSizes.fontSm),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: AppSizes.sm),
      ],
    );
  }

  Widget _buildAnalysisResult() {
    final sentimentColor = _sentiment == 'tích cực'
        ? AppColors.primary
        : _sentiment == 'cần cải thiện'
            ? AppColors.error
            : AppColors.gold;
    final sentimentIcon = _sentiment == 'tích cực'
        ? Icons.sentiment_very_satisfied
        : _sentiment == 'cần cải thiện'
            ? Icons.sentiment_dissatisfied
            : Icons.sentiment_neutral;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4, height: 18,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            const Expanded(
              child: Text(
                'Phân tích AI & Mẹo cải thiện',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppSizes.fontMd,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (_sentiment != null) ...[
              Icon(sentimentIcon, color: sentimentColor, size: 18),
              const SizedBox(width: 4),
              Text(
                _sentiment!,
                style: TextStyle(
                  color: sentimentColor,
                  fontSize: AppSizes.fontSm,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
        if (_summary != null && _summary!.isNotEmpty) ...[
          const SizedBox(height: AppSizes.sm),
          Container(
            padding: const EdgeInsets.all(AppSizes.sm),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            ),
            child: Text(
              _summary!,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppSizes.fontSm,
                height: 1.5,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSizes.sm),
        ..._tips.map(
          (tip) => Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 3),
                  child: Icon(Icons.lightbulb_outline, size: 14, color: AppColors.gold),
                ),
                const SizedBox(width: AppSizes.xs),
                Expanded(
                  child: Text(
                    tip,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppSizes.fontSm,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                AppLogger.logUserEvent(
                  action: 'live_replay_opened',
                  context: _tag,
                  metadata: {'session_id': widget.sessionId},
                );
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VodReplayScreen(
                    sessionId: widget.sessionId,
                    title: widget.title,
                  ),
                ));
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
              ),
              icon: const Icon(Icons.play_circle_outline, size: 20),
              label: const Text(
                'Xem lại buổi Live',
                style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () {
                AppLogger.logUserEvent(
                  action: 'live_summary_shared',
                  context: _tag,
                  metadata: {'title': widget.title},
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Đã copy link kết quả!')),
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
              ),
              icon: const Icon(Icons.share_outlined, size: 18),
              label: const Text(
                'Chia sẻ kết quả',
                style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                AppLogger.logUserEvent(action: 'live_end_go_home', context: _tag);
                Navigator.of(context).popUntil((route) => route.isFirst);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSizes.sm),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
              ),
              icon: const Icon(Icons.home_outlined, size: 18),
              label: const Text(
                'Về trang chủ',
                style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: AppSizes.fontLg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppSizes.fontXs,
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
