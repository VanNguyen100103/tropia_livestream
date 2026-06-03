class UserAddressModel {
  final int id;
  final String receiverName;
  final String phone;
  final String fullAddress;
  final bool isDefault;
  final String type; // 'home' hoặc 'office'

  UserAddressModel({
    required this.id,
    required this.receiverName,
    required this.phone,
    required this.fullAddress,
    required this.isDefault,
    required this.type,
  });

  factory UserAddressModel.fromJson(Map<String, dynamic> json) {
    return UserAddressModel(
      id: json['id'] ?? 0,
      receiverName: json['receiver_name'] ?? '',
      phone: json['phone'] ?? '',
      fullAddress: json['full_address'] ?? '',
      isDefault: json['is_default'] == true || json['is_default'] == 1,
      type: json['type'] ?? 'home',
    );
  }
}