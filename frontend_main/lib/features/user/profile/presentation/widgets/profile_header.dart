import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';


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

class ProfileHeader extends StatelessWidget {
  final String userName;
  final String rankName;
  final int points;
  final String barcode;
  final VoidCallback? onDetailTap; // Thêm callback để xử lý khi bấm vào link

  const ProfileHeader({
    super.key,
    required this.userName,
    required this.rankName,
    required this.points,
    required this.barcode,
    this.onDetailTap, // Nhận hàm xử lý sự kiện
  });

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
  Widget build(BuildContext context) {
    final theme = _resolveRankTheme(rankName);
    final Color goldColor = theme.accent;

    return Stack(
      alignment: Alignment.bottomCenter,
      clipBehavior: Clip.none,
      children: [
        // 1. NỀN CHÍNH
        Container(
          height: 240,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [theme.bgStart, theme.bgEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(30),
              bottomRight: Radius.circular(30),
            ),
          ),
          child: Stack(
            children: [
              // Hinh nen theo rank (PNG)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                  child: Opacity(
                    opacity: 0.30,
                    child: Image.asset(
                      theme.assetPath,
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
                bottom: 50,
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

              // Nội dung User
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tên User
                        Text(
                          userName.isNotEmpty ? userName : "Khách",
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Rank & Point Container
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.workspace_premium,
                                color: goldColor,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "${rankName.toUpperCase()}  |  ",
                                style: TextStyle(
                                  color: goldColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                "$points điểm",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // --- PHẦN MỚI THÊM VÀO ---
                        const SizedBox(height: 8), // Khoảng cách với rank
                        GestureDetector(
                          onTap: () {
                            // Xử lý sự kiện khi bấm vào link
                            if (onDetailTap != null) {
                              onDetailTap!();
                            } else {
                              debugPrint("Đã bấm xem chi tiết");
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "Chi tiết điểm",
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.7),
                                  fontSize: 12,
                                  fontStyle: FontStyle.italic, // Chữ nghiêng cho đẹp
                                  decoration: TextDecoration.underline, // Gạch chân giống link
                                  decorationColor: Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 10,
                                color: Colors.white.withValues(alpha: 0.7),
                              )
                            ],
                          ),
                        ),
                        // -------------------------
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. THẺ MÃ VẠCH
        Positioned(
          bottom: -40,
          left: 16,
          right: 16,
          child: Container(
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
                  child: barcode.isNotEmpty
                      ? BarcodeWidget(
                          barcode: Barcode.code128(),
                          data: barcode,
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
                        text: barcode.isNotEmpty ? barcode : "---",
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
          ),
        ),
      ],
    );
  }
}