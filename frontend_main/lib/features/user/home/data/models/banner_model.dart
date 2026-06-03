class BannerModel {
  final String id;
  final String imageUrl;
  final String title;
  final String actionType;
  final String actionValue;

  BannerModel({
    required this.id,
    required this.imageUrl,
    required this.title,
    required this.actionType,
    required this.actionValue,
  });

  factory BannerModel.fromJson(Map<String, dynamic> json) {
    String rawUrl = json['image_url'] ?? '';
    
    // XỬ LÝ QUAN TRỌNG: Đổi localhost thành 10.0.2.2 cho Android Emulator
    // Nếu bạn chạy máy thật thì cần thay bằng IP máy tính (VD: 192.168.1.x)
    if (rawUrl.contains('localhost')) {
      rawUrl = rawUrl.replaceFirst('localhost', '10.0.2.2');
    }

    return BannerModel(
      id: json['id']?.toString() ?? '',
      imageUrl: rawUrl,
      title: json['title'] ?? '',
      actionType: json['action_type'] ?? 'none',
      actionValue: json['action_value'] ?? '',
    );
  }
}