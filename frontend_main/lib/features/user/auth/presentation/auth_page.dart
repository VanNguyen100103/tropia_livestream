import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/shared/widgets/admin_scaffold.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/dashboard/presentation/dashboard_page.dart';

// --- UPDATE 1: Import DataSource lấy App Token ---
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';

// --- THÊM IMPORT: NotificationService ---
import 'package:tropia_mobile_app_android/core/services/notification_service.dart';

// --- Bridge sang AuthService riêng của module Livestream (lib/livestream) ---
// Module Live có kho JWT riêng (flutter_secure_storage) và KHÔNG thấy login
// của app chính. Phải đăng nhập lại vào nó để nút "Live" (phát live của seller)
// hiện ra và hoạt động.
import 'package:tropia_mobile_app_android/livestream/core/services/auth_service.dart'
    as live_auth;

class AppColors {
  static const Color greenPrimary = Color(0xFF4CAF50);
  static const Color orangeAccent = Color(0xFFFF9800);
}

class AuthPage extends StatefulWidget {
  const AuthPage({super.key});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  // --- CONTROLLER ĐĂNG NHẬP ---
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // --- CONTROLLER ĐĂNG KÝ ---
  final TextEditingController _regUsernameController = TextEditingController();
  final TextEditingController _regFullNameController = TextEditingController();
  final TextEditingController _regPhoneController = TextEditingController();
  final TextEditingController _regPasswordController = TextEditingController();
  final TextEditingController _regConfirmPasswordController =
      TextEditingController();

  bool _isLoading = false;
  late AuthRepository _authRepository;

  @override
  void initState() {
    super.initState();
    // Khởi tạo Repository
    final dio = DioClient().dio;
    final dataSource = AuthRemoteDataSourceImpl(client: dio);
    _authRepository = AuthRepository(remoteDataSource: dataSource);

    // Gán giá trị mặc định login để test (Tùy chọn)
    _usernameController.text = "";
    _passwordController.text = "";
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _regUsernameController.dispose();
    _regFullNameController.dispose();
    _regPhoneController.dispose();
    _regPasswordController.dispose();
    _regConfirmPasswordController.dispose();
    super.dispose();
  }

  // --- LOGIC 1: XỬ LÝ ĐĂNG NHẬP ---
  Future<void> _handleLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showSnackBar("Vui lòng nhập tài khoản và mật khẩu");
      return;
    }

    setState(() => _isLoading = true);

    try {
      // BƯỚC 1: Đăng nhập User (User Token)
      final result = await _authRepository.login(username, password);

      if (result != null) {
        // 1. Lưu data user vào bộ nhớ máy (SharedPreferences)
        final prefs = await SharedPreferences.getInstance();

        // Lấy user_id cũ trước khi set mới
        final oldUserId = prefs.getInt('user_id');

        // Lưu thông tin User
        await prefs.setString('role', result.role);
        await prefs.setInt('user_id', result.userId);
        await prefs.setString('user_fullname', result.fullName);
        await prefs.setString('user_phone', result.phone);
        await prefs.setString('user_address', result.address);
        await prefs.setString('email', result.email);
        await prefs.setString('user_session_token', result.token);

        // Lưu User Token (Authorization Header)
        DioClient().dio.options.headers["Authorization"] =
            "Bearer ${result.token}";
        if (kDebugMode) {
          debugPrint("LOGIN USER SUCCESS: ID ${result.userId}");
        }

        // --- BRIDGE: đăng nhập module Livestream bằng cùng tài khoản ---
        // /api/auth/login trả UUID + role mà module Live cần (lưu vào
        // secure storage của nó). Nhờ vậy UserProvider.canHostLive nhận ra
        // seller → nút "Live" phát trực tiếp xuất hiện. Lỗi ở đây không chặn
        // luồng login chính.
        try {
          await live_auth.AuthService.instance
              .login(username: username, password: password);
          if (kDebugMode) {
            debugPrint(
                "✅ Live auth bridge OK — seller=${live_auth.AuthService.instance.currentUser?.isSeller}");
          }
        } catch (e) {
          if (kDebugMode) debugPrint("⚠️ Live auth bridge failed: $e");
        }

        // --- UPDATE 2: GỌI API LẤY APP TOKEN CHO CHỨC NĂNG SEARCH ---
        try {
          if (kDebugMode) debugPrint("🔄 Đang lấy App Auth Token...");
          final dio = DioClient().dio;
          final appAuthDataSource = AppAuthRemoteDataSourceImpl(client: dio);
          final appTokenModel = await appAuthDataSource.getAuthorToken();

          if (appTokenModel != null) {
            // Lưu APP TOKEN vào SharedPreferences với key 'app_auth_token'
            // Đây chính là key mà hàm searchProducts sẽ tìm kiếm
            await prefs.setString('app_auth_token', appTokenModel.token);
            if (kDebugMode) debugPrint("✅ Đã lưu App Token thành công");

            // --- UPDATE 3: CẬP NHẬT DEVICE REGISTER VỚI USER_ID MỚI (SAU KHI CÓ APP TOKEN) ---
            // Nếu user_id thay đổi (hoặc lần đầu), gọi lại registerDevice
            if (oldUserId != result.userId) {
              try {
                if (kDebugMode) debugPrint("🔄 Cập nhật device register với user_id mới: ${result.userId}");
                await NotificationService().registerDevice(userId: result.userId);
                if (kDebugMode) debugPrint("✅ Device register updated successfully");
              } catch (e) {
                if (kDebugMode) debugPrint("❌ Lỗi khi cập nhật device register: $e");
                // Không chặn luồng login nếu lỗi
              }
            } else {
              if (kDebugMode) debugPrint("ℹ️ User_id không thay đổi, bỏ qua device register");
            }
          } else {
            if (kDebugMode) debugPrint("⚠️ Không lấy được App Token (Null)");
          }
        } catch (e) {
          if (kDebugMode) debugPrint("❌ Lỗi khi lấy App Token: $e");
          // Có thể không cần chặn luồng login nếu app token lỗi, tùy logic dự án
        }
        // -----------------------------------------------------------

        if (mounted) setState(() => _isLoading = false);
        if (!mounted) return;

        // 2. Điều hướng dựa trên Role
        String role = result.role.toLowerCase();
        if (role == 'admin' || role == 'superadmin') {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const AdminScaffold()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => DashboardPage()),
          );
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
          _showSnackBar("Đăng nhập thất bại. Kiểm tra lại thông tin.");
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackBar(
          "Lỗi đăng nhập: ${e.toString().replaceAll('Exception: ', '')}",
        );
      }
    }
  }

  // --- LOGIC 2: XỬ LÝ ĐĂNG KÝ (Giữ nguyên) ---
  Future<void> _handleRegister() async {
    final username = _regUsernameController.text.trim();
    final fullName = _regFullNameController.text.trim();
    final phone = _regPhoneController.text.trim();
    final password = _regPasswordController.text.trim();
    final confirmPass = _regConfirmPasswordController.text.trim();

    if (username.isEmpty ||
        fullName.isEmpty ||
        phone.isEmpty ||
        password.isEmpty) {
      _showSnackBar("Vui lòng nhập đầy đủ thông tin");
      return;
    }

    final hasUppercase = password.contains(RegExp(r'[A-Z]'));
    final hasSpecialCharacters = password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'));

    if (!hasUppercase || !hasSpecialCharacters) {
      _showSnackBar("Mật khẩu phải chứa ít nhất 1 chữ hoa và 1 ký tự đặc biệt (VD: @, #...)");
      return;
    }

    if (password != confirmPass) {
      _showSnackBar("Mật khẩu nhập lại không khớp");
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await _authRepository.register(
        username: username,
        fullName: fullName,
        phone: phone,
        password: password,
        email: "",
      );

      if (mounted) setState(() => _isLoading = false);

      if (result != null) {
        _showSnackBar("Đăng ký thành công! Vui lòng đăng nhập.");
        _usernameController.text = username;
        _passwordController.text = password;

        _regUsernameController.clear();
        _regFullNameController.clear();
        _regPhoneController.clear();
        _regPasswordController.clear();
        _regConfirmPasswordController.clear();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String errorMsg = e.toString().replaceAll("Exception: ", "");
        _showSnackBar(errorMsg);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  // --- UI CODE (Giữ nguyên UI của bạn) ---
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Stack(
            children: [
              Column(
                children: [
                  const SizedBox(height: 30),
                  Center(
                    child: Image.asset(
                      'assets/images/logo.png',
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.store,
                        size: 80,
                        color: AppColors.greenPrimary,
                      ),
                    ),
                  ),
                  Text(
                    "Welcome to Tropia",
                    style: GoogleFonts.roboto(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: AppColors.greenPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TabBar(
                      indicator: BoxDecoration(
                        color: AppColors.greenPrimary,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.grey,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      tabs: const [
                        Tab(text: "Đăng nhập"),
                        Tab(text: "Đăng ký"),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildLoginForm(context), // Tab 1
                        _buildRegisterForm(context), // Tab 2
                      ],
                    ),
                  ),
                ],
              ),

              if (_isLoading)
                Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: const Center(child: CircularProgressIndicator()),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildTextField(
            controller: _usernameController,
            label: "Tài khoản / Username",
            icon: Icons.person,
          ),
          const SizedBox(height: 15),
          _buildTextField(
            controller: _passwordController,
            label: "Mật khẩu",
            icon: Icons.lock,
            isPassword: true,
          ),

          const SizedBox(height: 10),

          // Align(
          //   alignment: Alignment.centerRight,
          //   child: Text(
          //     "Quên mật khẩu?",
          //     style: TextStyle(color: Colors.grey[600]),
          //   ),
          // ),
          const SizedBox(height: 25),
          _buildButton(
            text: "ĐĂNG NHẬP",
            color: AppColors.greenPrimary,
            onPressed: _handleLogin,
          ),
          const SizedBox(height: 12),
          _buildZaloButton(
            text: 'Đăng nhập bằng Zalo',
            onPressed: () => _showSnackBar('Tính năng đang phát triển'),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          _buildTextField(
            controller: _regUsernameController,
            label: "Tên đăng nhập (Username)",
            icon: Icons.account_circle,
          ),
          const SizedBox(height: 15),
          _buildTextField(
            controller: _regFullNameController,
            label: "Họ và tên",
            icon: Icons.person,
          ),
          const SizedBox(height: 15),
          _buildTextField(
            controller: _regPhoneController,
            label: "Số điện thoại",
            icon: Icons.phone,
          ),
          const SizedBox(height: 15),
          _buildTextField(
            controller: _regPasswordController,
            label: "Mật khẩu",
            icon: Icons.lock,
            isPassword: true,
          ),
          const SizedBox(height: 15),
          _buildTextField(
            controller: _regConfirmPasswordController,
            label: "Nhập lại mật khẩu",
            icon: Icons.lock_outline,
            isPassword: true,
          ),

          const SizedBox(height: 25),
          _buildButton(
            text: "ĐĂNG KÝ NGAY",
            color: AppColors.orangeAccent,
            onPressed: _handleRegister,
          ),
          const SizedBox(height: 12),
          _buildZaloButton(
            text: 'Đăng ký bằng Zalo',
            onPressed: () => _showSnackBar('Tính năng đang phát triển'),
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required IconData icon,
    bool isPassword = false,
    TextEditingController? controller,
  }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.greenPrimary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.grey),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.orangeAccent, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }

  Widget _buildButton({
    required String text,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 5,
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildZaloButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          side: BorderSide(color: Colors.grey.shade300),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        icon: Image.asset(
          'assets/images/zalo.png',
          height: 22,
          width: 22,
          errorBuilder: (_, _, _) => const Icon(Icons.chat, color: Colors.blue),
        ),
        label: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
