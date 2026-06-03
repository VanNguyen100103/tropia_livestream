import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';

import 'package:tropia_mobile_app_android/core/routes/slide_right_route.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/points_info_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/presentation/pages/point_history_screen.dart';

class _RankTheme {
  final Color bgStart;
  final Color bgEnd;
  final Color accent;
  final String assetPath;

  const _RankTheme({
    required this.bgStart,
    required this.bgEnd,
    required this.accent,
    required this.assetPath,
  });
}

/// Widget ProfileHeader với animation mở rộng toàn màn hình
/// Khi bấm "Chi tiết điểm" -> Thẻ mở rộng xuống và hiển thị toàn bộ thông tin
class ProfileHeaderAnimated extends StatefulWidget {
  final String userName;
  final String rankName;
  final int points;
  final String barcode;
  final PointsInfoModel? pointsInfo; // Thông tin chi tiết từ API

  const ProfileHeaderAnimated({
    super.key,
    required this.userName,
    required this.rankName,
    required this.points,
    required this.barcode,
    this.pointsInfo,
  });

  @override
  State<ProfileHeaderAnimated> createState() => _ProfileHeaderAnimatedState();
}

class _ProfileHeaderAnimatedState extends State<ProfileHeaderAnimated>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _expandAnimation;
  late Animation<double> _fadeAnimation;
  late Animation<double> _slideAnimation;

  bool _isExpanded = false;

  _RankTheme get _theme {
    final displayRank =
        widget.pointsInfo?.currentRankVietnamese ?? widget.rankName;
    return _resolveRankTheme(displayRank);
  }

  _RankTheme _resolveRankTheme(String rank) {
    final normalized = rank.trim().toLowerCase();
    if (normalized.contains('diamond') ||
        normalized.contains('kim cuong') ||
        normalized.contains('kim cương')) {
      return const _RankTheme(
        bgStart: Color(0xFF0F2027),
        bgEnd: Color(0xFF2C5364),
        accent: Color(0xFF6EE7F9),
        assetPath: 'assets/images/diamond.png',
      );
    }
    if (normalized.contains('platinum') ||
        normalized.contains('bach kim') ||
        normalized.contains('bạch kim')) {
      return const _RankTheme(
        bgStart: Color(0xFF1E1E1E),
        bgEnd: Color(0xFF3A6073),
        accent: Color(0xFFB8F1FF),
        assetPath: 'assets/images/platinum.png',
      );
    }
    if (normalized.contains('gold') ||
        normalized.contains('vang') ||
        normalized.contains('vàng')) {
      return const _RankTheme(
        bgStart: Color(0xFF3A2C00),
        bgEnd: Color(0xFF8C6A00),
        accent: Color(0xFFFFD700),
        assetPath: 'assets/images/gold.png',
      );
    }
    if (normalized.contains('silver') ||
        normalized.contains('bac') ||
        normalized.contains('bạc')) {
      return const _RankTheme(
        bgStart: Color(0xFF1B1D1F),
        bgEnd: Color(0xFF4B5B66),
        accent: Color(0xFFC0C0C0),
        assetPath: 'assets/images/silver.png',
      );
    }
    return const _RankTheme(
      bgStart: Color(0xFF232526),
      bgEnd: Color(0xFF414345),
      accent: Color(0xFFFFD700),
        assetPath: 'assets/images/member.png',
    );
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _expandAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 1.0, curve: Curves.easeIn),
      ),
    );

    _slideAnimation = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
      if (_isExpanded) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final collapsedHeight = 240.0;
    final expandedHeight = screenHeight * 0.85; // 85% màn hình

    return AnimatedBuilder(
      animation: _expandAnimation,
      builder: (context, child) {
        final currentHeight =
            collapsedHeight +
            (expandedHeight - collapsedHeight) * _expandAnimation.value;

        // Tính toán vị trí barcode
        final barcodeBottom = -40.0 + (100 * _expandAnimation.value);

        // Tính diện tích còn lại cho phần nội dung để tránh overflow
        final double availableForContent = currentHeight - 180.0;

        return Stack(
          alignment: Alignment.bottomCenter,
          clipBehavior: Clip.none,
          children: [
            // 1. NỀN CHÍNH (MỞ RỘNG)
            Container(
              height: currentHeight,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_theme.bgStart, _theme.bgEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(
                    30 - (20 * _expandAnimation.value),
                  ),
                  bottomRight: Radius.circular(
                    30 - (20 * _expandAnimation.value),
                  ),
                ),
              ),
              child: Stack(
                children: [
                  // Hinh nen theo rank (PNG)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(
                          30 - (20 * _expandAnimation.value),
                        ),
                        bottomRight: Radius.circular(
                          30 - (20 * _expandAnimation.value),
                        ),
                      ),
                      child: Opacity(
                        opacity: 0.30,
                        child: Image.asset(
                          _theme.assetPath,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  ),
                  // Họa tiết trang trí (Background circles)
                  Positioned(
                    right: -30,
                    top: -50,
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.03),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 50 + (100 * _expandAnimation.value),
                    left: -20,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.05),
                      ),
                    ),
                  ),
                  // Thêm vòng tròn trang trí khi mở rộng
                  if (_expandAnimation.value > 0.3)
                    Positioned(
                      right: 50,
                      bottom: 200,
                      child: Opacity(
                        opacity: _expandAnimation.value,
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _theme.accent.withValues(alpha: 0.05),
                          ),
                        ),
                      ),
                    ),

                  // Nội dung User
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header row (Tên + Rank + Link)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Tên User
                                  Text(
                                    widget.userName.isNotEmpty
                                        ? widget.userName
                                        : "Khách",
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  const SizedBox(height: 8),

                                  // Rank & Point Container
                                  _buildRankBadge(),

                                  const SizedBox(height: 8),

                                  // Link Chi tiết / Quay lại
                                  _buildDetailLink(),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // Nội dung chi tiết (chỉ hiển thị khi mở rộng)
                        if (_expandAnimation.value > 0.1)
                          SizedBox(
                            height: availableForContent.clamp(0.0, 2000.0),
                            child: SingleChildScrollView(
                              physics: const BouncingScrollPhysics(),
                              child: _buildDetailContent(),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. THẺ MÃ VẠCH (ANIMATE THEO)
            Positioned(
              bottom: barcodeBottom,
              left: 16,
              right: 16,
              child: _buildBarcodeCard(),
            ),
          ],
        );
      },
    );
  }

  /// Widget hiển thị badge hạng thành viên
  Widget _buildRankBadge() {
    final displayRank =
        widget.pointsInfo?.currentRankVietnamese ?? widget.rankName;
    final displayPoints = widget.pointsInfo?.currentPoints ?? widget.points;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, color: _theme.accent, size: 16),
          const SizedBox(width: 4),
          Text(
            "${displayRank.toUpperCase()}  |  ",
            style: TextStyle(
              color: _theme.accent,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            "$displayPoints điểm",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Widget link Chi tiết / Quay lại
  Widget _buildDetailLink() {
    return GestureDetector(
      onTap: _toggleExpand,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isExpanded ? "Quay lại tổng quan" : "Chi tiết điểm",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              fontStyle: FontStyle.italic,
              decoration: TextDecoration.underline,
              decorationColor: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 4),
          AnimatedRotation(
            turns: _isExpanded ? 0.5 : 0,
            duration: const Duration(milliseconds: 300),
            child: Icon(
              _isExpanded
                  ? Icons.keyboard_arrow_up
                  : Icons.arrow_forward_ios_rounded,
              size: _isExpanded ? 16 : 10,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  /// Widget nội dung chi tiết điểm (chỉ hiển thị khi mở rộng)
  Widget _buildDetailContent() {
    final info = widget.pointsInfo;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: Transform.translate(
        offset: Offset(0, _slideAnimation.value),
        child: Padding(
          padding: const EdgeInsets.only(top: 30),
                          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Tiêu đề
              Text(
                "THÔNG TIN CHI TIẾT",
                style: TextStyle(
                  color: _theme.accent,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                width: 60,
                height: 2,
                decoration: BoxDecoration(
                  color: _theme.accent,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
              const SizedBox(height: 20),

                // Grid thông tin
              if (info != null) ...[
                _buildInfoRow(
                  icon: Icons.stars_rounded,
                  label: "Điểm hiện tại",
                  value: "${info.currentPoints} điểm",
                  trailing: _buildHistoryInline(),
                ),
                _buildInfoRow(
                  icon: Icons.workspace_premium,
                  label: "Hạng hiện tại",
                  value: info.currentRankVietnamese,
                ),
                _buildInfoRow(
                  icon: Icons.trending_up,
                  label: "Hạng tiếp theo",
                  value: info.nextRankVietnamese,
                ),
                _buildInfoRow(
                  icon: Icons.add_circle_outline,
                  label: "Điểm cần để lên hạng",
                  value: "${info.pointsToNextRank} điểm",
                ),
                _buildInfoRow(
                  icon: Icons.shopping_cart_outlined,
                  label: "Chi tiêu tháng này",
                  value: info.formattedMonthlySpendingFull,
                ),
                _buildInfoRow(
                  icon: Icons.attach_money,
                  label: "Chi tiêu cần để lên hạng",
                  value: info.formattedSpendingToNextRankFull,
                ),
                _buildInfoRow(
                  icon: Icons.percent,
                  label: "Hệ số nhân điểm",
                  value: "x${info.multiplier}",
                  isLast: true,
                ),
                // Add extra bottom spacing so barcode overlay won't cover the last row
                const SizedBox(height: 140),
              ] else ...[
                // Loading hoặc không có dữ liệu
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: CircularProgressIndicator(
                            color: _theme.accent.withValues(alpha: 0.9),
                            strokeWidth: 2,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Đang tải thông tin...",
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Widget một dòng thông tin
  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    Widget? trailing,
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _theme.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(height: 6),
                  trailing,
                ],
              ],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Compact inline history link used as trailing widget for points row
  Widget _buildHistoryInline() {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          SlideRightRoute(page: const PointHistoryScreen()),
        );
      },
      borderRadius: BorderRadius.circular(8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history,
            color: Colors.white.withValues(alpha: 0.85),
            size: 14,
          ),
          const SizedBox(width: 6),
          Text(
            "Lịch sử tích điểm",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Widget thẻ mã vạch
  Widget _buildBarcodeCard() {
    return Container(
      height: 110,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 50,
            width: double.infinity,
            child: widget.barcode.isNotEmpty
                ? BarcodeWidget(
                    barcode: Barcode.code128(),
                    data: widget.barcode,
                    drawText: false,
                    color: const Color(0xFF2C2C2C),
                    width: double.infinity,
                  )
                : Center(
                    child: Text(
                      "Chưa có mã vạch",
                      style: TextStyle(color: Colors.grey[300]),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              children: [
                const TextSpan(text: "Mã thành viên: "),
                TextSpan(
                  text: widget.barcode.isNotEmpty ? widget.barcode : "---",
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
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
