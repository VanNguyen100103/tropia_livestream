import 'package:flutter/material.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:tropia_mobile_app_android/core/constants/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/datasources/profile_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/profile_repository.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/points_info_model.dart';

class LoyaltyCard extends StatefulWidget {
  // [MỚI] Nhận dữ liệu từ ngoài vào (giữ làm fallback)
  final String rankName;
  final int points;
  final String barcode;

  const LoyaltyCard({
    super.key,
    required this.rankName,
    required this.points,
    required this.barcode, // Có thể dùng để hiển thị mã QR khi bấm vào nút
  });

  @override
  State<LoyaltyCard> createState() => _LoyaltyCardState();
}

class _LoyaltyCardState extends State<LoyaltyCard> {
  String _rankName = '';
  int _points = 0;
  String _barcode = '';
  // ignore: unused_field
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _rankName = widget.rankName;
    _points = widget.points;
    _barcode = widget.barcode;
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;

      // Prepare repo (it will read token from SharedPreferences internally)
      final dio = DioClient().dio;
      final profileRepo = ProfileRepository(
        remoteDataSource: ProfileRemoteDataSource(client: dio),
      );

      if (userId > 0) {
        final PointsInfoModel? info = await profileRepo.getPointsInfo(userId);
        if (info != null && mounted) {
          setState(() {
            _rankName = info.currentRankVietnamese;
            _points = info.currentPoints;
          });
        }
      }

      // Barcode: API doesn't provide it, try to read cached barcode
      final cachedBarcode = prefs.getString('loyalty_barcode') ?? '';
      if (cachedBarcode.isNotEmpty && mounted) {
        setState(() => _barcode = cachedBarcode);
      }
    } catch (e) {
      // ignore errors, keep fallback values
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color cardBackgroundStart = Color(0xFF232526);
    const Color cardBackgroundEnd = Color(0xFF414345);
    const Color accentColor = Color(0xFFFF6B6B);
    const Color goldColor = Color(0xFFFFD700);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      height: 140,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF232526).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [cardBackgroundStart, cardBackgroundEnd],
        ),
      ),
      child: Stack(
        children: [
          // ... Các hình tròn trang trí giữ nguyên ...
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            left: 20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: accentColor.withValues(alpha: 0.1),
              ),
            ),
          ),

          // --- Nội dung chính ---
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.workspace_premium,
                          color: goldColor,
                          size: 20,
                        ),
                        const SizedBox(width: 6),
                        // [MỚI] Hiển thị Rank thật (viết hoa)
                        Text(
                          _rankName.toUpperCase(),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.7),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // [MỚI] Hiển thị Điểm thật
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: "$_points ",
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const TextSpan(
                            text: "điểm",
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => _showBarcodeDialog(context),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.confirmation_number,
                            color: Colors.black,
                            size: 18,
                          ),
                          SizedBox(width: 8),
                          Text(
                            "Tích điểm",
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Hàm hiển thị mã vạch đơn giản (Demo)
  void _showBarcodeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Mã thành viên"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 70,
              width: 260,
              child: _barcode.isNotEmpty
                  ? BarcodeWidget(
                      barcode: Barcode.code128(),
                      data: _barcode,
                      drawText: false,
                      color: const Color(0xFF2C2C2C),
                      width: double.infinity,
                    )
                  : Center(
                      child: Text(
                        "Chưa có mã vạch",
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ),
            ),
            const SizedBox(height: 12),
            Text(
              _barcode,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Đóng"),
          ),
        ],
      ),
    );
  }
}
