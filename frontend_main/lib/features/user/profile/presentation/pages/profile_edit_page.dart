import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/datasources/profile_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/user_profile_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/profile_repository.dart';

class ProfileEditPage extends StatefulWidget {
  final UserProfileModel userProfile;

  const ProfileEditPage({super.key, required this.userProfile});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _phoneController;

  // Variables
  String _gender = "male";
  String _avatarUrl = ""; 
  bool _isUpdating = false;

  // --- THEME COLORS (Minimalist Black & White) ---
  final Color _primaryBlack = const Color(0xFF1A1A1A); // Đen mềm
  final Color _bgWhite = Colors.white;
  final Color _inputFill = const Color(0xFFF3F4F6); // Nền xám nhạt cho input
  // ignore: unused_field
  final Color _textGrey = const Color(0xFF757575); // Màu chữ phụ

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.userProfile.name);
    _phoneController = TextEditingController(text: widget.userProfile.phone);
    _avatarUrl = widget.userProfile.avatarUrl;
    
    // Set gender if available in profile, else default to male
    // (Logic này tùy thuộc dữ liệu trả về của bạn)
    // _gender = widget.userProfile.gender ?? "male"; 
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _handleUpdate() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isUpdating = true);

    try {
      final dio = DioClient().dio;
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null) return;

      final repo = ProfileRepository(
        remoteDataSource: ProfileRemoteDataSource(client: dio),
      );

      final updateBody = {
        "full_name": _nameController.text.trim(),
        "gender": _gender,
        "avatar": _avatarUrl,
        "phone": _phoneController.text.trim(),
      };

      final success = await repo.updateUserProfile(userId, updateBody);

      if (mounted) {
        setState(() => _isUpdating = false);
        if (success) {
          Navigator.pop(context, true); // Trả về true để reload trang trước
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Cập nhật thất bại"),
              backgroundColor: Colors.black, // Snackbar đen
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Lỗi: $e")));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgWhite,
      appBar: AppBar(
        title: Text(
          "CHỈNH SỬA HỒ SƠ", 
          style: TextStyle(
            fontSize: 16, 
            fontWeight: FontWeight.w900, 
            color: _primaryBlack, 
            letterSpacing: 0.5
          )
        ),
        centerTitle: true,
        backgroundColor: _bgWhite,
        foregroundColor: _primaryBlack,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: _inputFill, height: 1), // Divider mỏng
        ),
        actions: [
          TextButton(
            onPressed: _isUpdating ? null : _handleUpdate,
            style: TextButton.styleFrom(
              foregroundColor: _primaryBlack,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: _isUpdating
                ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _primaryBlack))
                : const Text("LƯU", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar Section (Optional - Giữ placeholder nếu muốn sau này thêm tính năng upload)
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: _inputFill,
                      backgroundImage: _avatarUrl.isNotEmpty ? NetworkImage(_avatarUrl) : null,
                      child: _avatarUrl.isEmpty 
                          ? Icon(Icons.person, size: 50, color: Colors.grey[400]) 
                          : null,
                    ),
                    Positioned(
                      bottom: 0, right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _primaryBlack,
                          shape: BoxShape.circle,
                          border: Border.all(color: _bgWhite, width: 2),
                        ),
                        child: const Icon(Icons.camera_alt, size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),

              // 1. Form Fields (Minimalist Style)
              _buildMinimalTextField("HỌ VÀ TÊN", _nameController, Icons.person_outline),
              const SizedBox(height: 24),

              _buildMinimalTextField(
                "SỐ ĐIỆN THOẠI",
                _phoneController,
                Icons.phone_outlined,
                inputType: TextInputType.phone,
              ),
              const SizedBox(height: 24),

              // 2. Giới tính (Custom Dropdown)
              Text(
                "GIỚI TÍNH",
                style: TextStyle(
                  fontSize: 12, 
                  fontWeight: FontWeight.bold, 
                  color: Colors.grey[500],
                  letterSpacing: 0.5
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: _inputFill, // Nền xám nhạt
                  borderRadius: BorderRadius.circular(12), // Bo góc mềm
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _gender,
                    isExpanded: true,
                    icon: Icon(Icons.keyboard_arrow_down, color: _primaryBlack),
                    dropdownColor: _bgWhite,
                    style: TextStyle(
                      color: _primaryBlack, 
                      fontWeight: FontWeight.w600, 
                      fontSize: 16,
                      fontFamily: 'Roboto' // Đảm bảo font không bị lỗi
                    ),
                    items: const [
                      DropdownMenuItem(value: "male", child: Text("Nam")),
                      DropdownMenuItem(value: "female", child: Text("Nữ")),
                      DropdownMenuItem(value: "other", child: Text("Khác")),
                    ],
                    onChanged: (val) => setState(() => _gender = val!),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- HELPER: Minimalist Text Field ---
  Widget _buildMinimalTextField(
    String label,
    TextEditingController controller,
    IconData icon, {
    TextInputType inputType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label nằm ngoài ô nhập liệu
        Text(
          label,
          style: TextStyle(
            fontSize: 12, 
            fontWeight: FontWeight.bold, 
            color: Colors.grey[500],
            letterSpacing: 0.5
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: inputType,
          style: TextStyle(color: _primaryBlack, fontWeight: FontWeight.w600, fontSize: 16),
          cursorColor: _primaryBlack,
          decoration: InputDecoration(
            // Filled Style
            filled: true,
            fillColor: _inputFill,
            
            // Icon
            prefixIcon: Icon(icon, color: Colors.grey[500], size: 22),
            
            // Border: Ẩn viền, chỉ bo góc
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: _primaryBlack, width: 1.5), // Focus hiện viền đen
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          ),
          validator: (value) {
            if (value == null || value.isEmpty) return "Vui lòng nhập thông tin";
            return null;
          },
        ),
      ],
    );
  }
}