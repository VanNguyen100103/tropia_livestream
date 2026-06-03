import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/datasources/profile_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/profile_repository.dart';

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  // Biến lưu trữ số dư
  double _balance = 0;
  bool _isLoading = true;

  // Format tiền tệ
  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  @override
  void initState() {
    super.initState();
    _loadWalletData();
  }

  Future<void> _loadWalletData() async {
    final dio = DioClient().dio;

    try {
      // 1. App Token
      final appAuthRepo = AppAuthRepository(
        remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
      );
      await appAuthRepo.authenticateApp();

      // 2. User ID
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null || userId == 0) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 3. Gọi API Profile (Chứa thông tin Wallet)
      final profileRepo = ProfileRepository(
        remoteDataSource: ProfileRemoteDataSource(client: dio),
      );

      final userProfile = await profileRepo.getUserProfile(userId);

      if (userProfile != null && mounted) {
        setState(() {
          _balance = userProfile.wallet.balance;
          _isLoading = false;
        });
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Lỗi tải ví: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text("Ví của tôi"),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: _loadWalletData, // Kéo xuống để cập nhật số dư
        color: Colors.green,
        child: Column(
          children: [
            // Header hiển thị số dư
            Container(
              padding: const EdgeInsets.all(24),
              color: Colors.green,
              width: double.infinity,
              child: Column(
                children: [
                  const Text(
                    "Số dư khả dụng",
                    style: TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),

                  // [MỚI] Hiển thị Loading hoặc Số dư thật
                  _isLoading
                      ? const SizedBox(
                          height: 30,
                          width: 30,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          currencyFormat.format(_balance), // Format số tiền
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(Icons.add, "Nạp tiền"),
                      _buildActionButton(Icons.download, "Rút tiền"),
                      _buildActionButton(Icons.history, "Lịch sử"),
                    ],
                  ),
                ],
              ),
            ),

            // Danh sách giao dịch gần đây
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: 16),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Giao dịch gần đây",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Phần này hiện tại dùng Mock Data vì API chưa có list transaction
                    // Bạn có thể giữ nguyên hoặc thay thế sau khi có API Transaction
                    Expanded(
                      child: ListView.builder(
                        itemCount: 5,
                        itemBuilder: (context, index) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.shopping_bag_outlined,
                                  color: Colors.orange,
                                ),
                              ),
                              title: const Text(
                                "Thanh toán đơn hàng",
                                style: TextStyle(fontWeight: FontWeight.w500),
                              ),
                              subtitle: const Text("20/11/2025 - 14:30"),
                              trailing: const Text(
                                "-150.000đ",
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label) {
    return InkWell(
      onTap: () {
        // Xử lý sự kiện nút bấm
      },
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
