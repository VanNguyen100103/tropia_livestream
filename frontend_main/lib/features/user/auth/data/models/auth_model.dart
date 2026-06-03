class AuthModel {
  final String token;
  final String role;
  final String username;
  final int userId;
  final String fullName;
  final String phone;
  final String address;
  final String email;

  AuthModel({
    required this.token,
    required this.role,
    required this.username,
    required this.userId,
    required this.fullName,
    required this.phone,
    required this.address,
    required this.email,
  });

  factory AuthModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'];

    // Hàm helper nhỏ để lọc giá trị rác "0" hoặc null
    String cleanValue(dynamic value) {
      if (value == null) return "";
      String str = value.toString();
      if (str == "0") return ""; // Nếu là "0" thì trả về rỗng
      return str;
    }

    return AuthModel(
      token: json['token'] ?? '',
      role: user != null ? user['role'] ?? 'user' : 'user',
      username: user != null ? user['username'] ?? '' : '',
      userId: user != null ? user['id'] ?? 0 : 0,
      
      // Sử dụng hàm cleanValue để xử lý "0"
      fullName: user != null ? cleanValue(user['full_name']) : '',
      phone: user != null ? cleanValue(user['so_dien_thoai']) : '',
      address: user != null ? cleanValue(user['dia_chi']) : '',
      email: user != null ? cleanValue(user['email']) : '', 
    );
  }
}