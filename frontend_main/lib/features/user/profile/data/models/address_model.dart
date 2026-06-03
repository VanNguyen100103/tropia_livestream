class AddressModel {
  final int? id; // Nên để nullable vì khi tạo mới chưa có ID
  final String receiverName;
  final String phone;
  final String fullAddress;
  final bool isDefault;
  final String type; // 'home', 'office', etc.

  AddressModel({
    this.id,
    required this.receiverName,
    required this.phone,
    required this.fullAddress,
    required this.isDefault,
    required this.type,
  });

  factory AddressModel.fromJson(Map<String, dynamic> json) {
    return AddressModel(
      id: json['id'],
      receiverName: json['receiver_name'] ?? '',
      phone: json['phone'] ?? '',
      fullAddress: json['full_address'] ?? '',
      // Xử lý an toàn: API có thể trả về true/false hoặc 1/0
      isDefault: json['is_default'] == true || json['is_default'] == 1,
      type: json['type'] ?? 'home',
    );
  }

  // [MỚI] Hàm chuyển đổi sang JSON để gửi lên API (POST)
  Map<String, dynamic> toJson() {
    return {
      'receiver_name': receiverName,
      'phone': phone,
      'full_address': fullAddress,
      'is_default': isDefault,
      'type': type,
      // Không gửi ID vì server sẽ tự tạo
    };
  }
}