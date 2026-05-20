// =============================================================================
// user_model.dart
// =============================================================================
// Model người dùng Tropia với hệ thống phân quyền role.
//
// Role:
//   - [UserRole.buyer]  : Người mua – chỉ xem live, mua hàng, tương tác chat
//   - [UserRole.seller] : Người bán – có thêm quyền tạo & host buổi livestream
// =============================================================================

/// Phân loại quyền của tài khoản.
enum UserRole {
  /// Người mua – không thể host live
  buyer,

  /// Người bán – có thể tạo và host livestream
  seller,
}

extension UserRoleX on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.buyer:
        return 'Người mua';
      case UserRole.seller:
        return 'Người bán';
    }
  }

  String get description {
    switch (this) {
      case UserRole.buyer:
        return 'Xem live, mua hàng, tương tác chat';
      case UserRole.seller:
        return 'Tạo & host buổi livestream bán hàng';
    }
  }

  bool get canHostLive => this == UserRole.seller;
}

/// Thông tin tài khoản người dùng.
class UserModel {
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final UserRole role;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.role,
  });

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? avatarUrl,
    UserRole? role,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
    );
  }

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id:        j['id']         as String,
        name:      j['name']       as String? ?? j['email'] as String,
        email:     j['email']      as String,
        avatarUrl: j['avatar_url'] as String?,
        role: (j['role'] as String?) == 'seller'
            ? UserRole.seller
            : UserRole.buyer,
      );
}
