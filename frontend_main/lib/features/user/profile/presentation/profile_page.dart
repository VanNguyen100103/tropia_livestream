import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/livestream/core/services/auth_service.dart'
    as live_auth;
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/auth/presentation/auth_page.dart';

// --- PROFILE FEATURE ---
import 'package:tropia_mobile_app_android/features/user/profile/data/datasources/profile_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/user_profile_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/points_info_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/profile_repository.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/mock_profile_data.dart';
import 'package:tropia_mobile_app_android/features/user/profile/presentation/widgets/profile_header_animated.dart';
import 'package:tropia_mobile_app_android/features/user/profile/presentation/widgets/profile_menu_section.dart';
import 'package:tropia_mobile_app_android/features/user/profile/presentation/pages/profile_edit_page.dart';

// --- ADDRESS FEATURE ---
import 'package:tropia_mobile_app_android/features/user/profile/presentation/pages/user_address_page.dart';

// [QUAN TRỌNG] IMPORT NOTIFICATION SERVICE ĐỂ XÓA TOKEN
import 'package:tropia_mobile_app_android/core/services/notification_service.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // Biến dữ liệu Profile
  String _userName = "";
  String _rankName = "Thành viên";
  int _points = 0;
  String _barcode = "";

  // Biến dữ liệu cá nhân
  int _userId = 0;
  String _phone = "";
  String _avatar = "";
  // ignore: unused_field
  String _email = "";
  // ignore: unused_field
  String _address = "";

  // Thông tin chi tiết điểm từ API points/info
  PointsInfoModel? _pointsInfo;

  // ignore: unused_field
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final dio = DioClient().dio;

    // 1. Đảm bảo App Token
    final appAuthRepo = AppAuthRepository(
      remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
    );
    await appAuthRepo.authenticateApp();

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    // A. Load cache trước cho mượt
    if (mounted) {
      setState(() {
        _userId = userId ?? 0;
        _userName = prefs.getString('user_fullname') ?? "";
        _phone = prefs.getString('user_phone') ?? "";
        _avatar = prefs.getString('user_avatar') ?? "";
        _email = prefs.getString('email') ?? "";
        _address = prefs.getString('user_address') ?? "";

        _rankName = prefs.getString('loyalty_rank') ?? "Thành viên";
        _points = prefs.getInt('loyalty_points') ?? 0;
        _barcode = prefs.getString('loyalty_barcode') ?? "";
      });
    }

    if (userId == null || userId == 0) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    // B. Gọi API lấy dữ liệu mới nhất
    try {
      final profileRepo = ProfileRepository(
        remoteDataSource: ProfileRemoteDataSource(client: dio),
      );

      final userProfile = await profileRepo.getUserProfile(userId);

      if (userProfile != null && mounted) {
        setState(() {
          // Update Loyalty Info
          _userName = userProfile.name;
          _rankName = userProfile.loyalty.rankName;
          _points = userProfile.loyalty.currentPoints;
          _barcode = userProfile.loyalty.barcode;

          // Update Personal Info
          _phone = userProfile.phone;
          _avatar = userProfile.avatarUrl;

          _isLoading = false;
        });

        // C. Cập nhật Cache
        await prefs.setString('user_fullname', _userName);
        await prefs.setString('user_phone', _phone);
        await prefs.setString('user_avatar', _avatar);
        await prefs.setString('loyalty_rank', _rankName);
        await prefs.setInt('loyalty_points', _points);
        await prefs.setString('loyalty_barcode', _barcode);
      }

      // D. Gọi API lấy thông tin chi tiết điểm và hạng
      await _loadPointsInfo(userId, profileRepo);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Lỗi tải profile: $e");
    }
  }

  /// Gọi API lấy thông tin chi tiết điểm và hạng thành viên
  Future<void> _loadPointsInfo(
    int userId,
    ProfileRepository profileRepo,
  ) async {
    try {
      final pointsInfo = await profileRepo.getPointsInfo(userId);
      if (pointsInfo != null && mounted) {
        setState(() {
          _pointsInfo = pointsInfo;
          // Cập nhật rank và points từ API mới (ưu tiên hơn)
          _rankName = pointsInfo.currentRankVietnamese;
          _points = pointsInfo.currentPoints;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải thông tin điểm: $e");
    }
  }

  // --- HÀM XỬ LÝ LOGOUT & XÓA TÀI KHOẢN (ĐÃ CẬP NHẬT LOGIC NOTIFICATION) ---
  Future<void> _performLogoutOrDelete() async {
    // 1. [QUAN TRỌNG] Báo Server Notification biết User này đã thoát
    // Để tránh gửi thông báo nhầm khi người khác mượn máy
    try {
      await NotificationService().clearUserId();
      debugPrint("✅ Đã xóa User ID khỏi Notification Service");
    } catch (e) {
      debugPrint("⚠️ Lỗi xóa User ID Noti (không ảnh hưởng logout): $e");
    }

    // 1b. Đăng xuất module Livestream — token của nó nằm trong
    // flutter_secure_storage + singleton RAM nên prefs.clear() không chạm tới.
    // Bỏ qua nếu lỗi (không chặn logout).
    try {
      await live_auth.AuthService.instance.logout();
    } catch (e) {
      debugPrint("⚠️ Lỗi logout module Live (không chặn logout chính): $e");
    }

    // 2. Xóa dữ liệu trong ổ cứng (SharedPreferences)
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    // 3. Xóa Token đang lưu trong RAM (Dio Client)
    DioClient().dio.options.headers.remove("Authorization");

    if (!mounted) return;

    // 4. Điều hướng về trang Login
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const AuthPage()),
      (Route<dynamic> route) => false,
    );
  }

  Future<void> _handleLogout() async {
    final bool? shouldLogout = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Đăng xuất"),
          content: const Text("Bạn có chắc chắn muốn đăng xuất?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                "Đăng xuất",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      await _performLogoutOrDelete();
    }
  }

  Future<void> _handleDeleteAccount() async {
    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Xóa tài khoản"),
          content: const Text(
            "Hành động này không thể hoàn tác. Bạn có chắc chắn muốn xóa tài khoản không?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(
                "Xóa vĩnh viễn",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true) return;

    // Gọi API xóa tài khoản
    try {
      final dio = DioClient().dio;
      final profileRepo = ProfileRepository(
        remoteDataSource: ProfileRemoteDataSource(client: dio),
      );
      final success = await profileRepo.deleteAccount(_userId);

      if (!mounted) return;

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Không thể xóa tài khoản. Vui lòng thử lại."),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Lỗi: ${e.toString()}"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Xóa thành công → thực hiện logout
    await _performLogoutOrDelete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: RefreshIndicator(
        onRefresh: _loadUserProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // 1. Header với Animation mở rộng
              ProfileHeaderAnimated(
                userName: _userName,
                rankName: _rankName,
                points: _points,
                barcode: _barcode,
                pointsInfo: _pointsInfo,
              ),

              const SizedBox(height: 50),

              // 2. Menu Tiện ích
              ProfileMenuSection(items: MockProfileData.utilityMenu),

              // 3. Menu Cài đặt
              ProfileMenuSection(
                title: "Thông tin cá nhân",
                onProfileUpdate: _loadUserProfile,
                items: [
                  {
                    'icon': Icons.person_outline,
                    'title': 'Chỉnh sửa hồ sơ',
                    'trailing': 'Thay đổi',
                    'destination': ProfileEditPage(
                      userProfile: UserProfileModel(
                        id: _userId,
                        name: _userName,
                        phone: _phone,
                        avatarUrl: _avatar,
                        loyalty: LoyaltyModel(
                          rankName: _rankName,
                          currentPoints: _points,
                          barcode: _barcode,
                        ),
                        wallet: WalletModel(balance: 0, currencyUnit: 'đ'),
                        counters: CountersModel(
                          unreadNotifications: 0,
                          availableVouchers: 0,
                        ),
                      ),
                    ),
                  },
                  {
                    'icon': Icons.lock_outline,
                    'title': 'Đổi mật khẩu',
                    'destination': null,
                  },
                  {
                    'icon': Icons.location_on_outlined,
                    'title': 'Sổ địa chỉ',
                    'destination': const UserAddressPage(),
                  },
                ],
              ),

              const SizedBox(height: 20),

              // 5. Nút Hành động
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _handleLogout,
                      child: const Text(
                        "Đăng xuất",
                        style: TextStyle(color: Colors.red, fontSize: 15),
                      ),
                    ),
                    Container(
                      height: 15,
                      width: 1,
                      color: Colors.grey[300],
                      margin: const EdgeInsets.symmetric(horizontal: 15),
                    ),
                    TextButton(
                      onPressed: _handleDeleteAccount,
                      child: const Text(
                        "Xóa tài khoản",
                        style: TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
