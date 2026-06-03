class BannerModel {
  final String? id; // ID có thể null khi tạo mới, nhưng sẽ có khi get về
  final String title;
  final String imageUrl;
  final String actionType;
  final String actionValue;

  BannerModel({
    this.id,
    required this.title,
    required this.imageUrl,
    required this.actionType,
    required this.actionValue,
  });

  // Map từ JSON API trả về -> Dart Object
  factory BannerModel.fromJson(Map<String, dynamic> json) {
    return BannerModel(
      id: json['id'] as String?,
      title: json['title'] ?? '',
      imageUrl: json['image_url'] ?? '', // Map key 'image_url' từ API
      actionType: json['action_type'] ?? 'none', // Map key 'action_type'
      actionValue: json['action_value'] ?? '', // Map key 'action_value'
    );
  }

  Map<String, dynamic> toJson() {
    return {
      // 'id': id, // Thường create không gửi ID
      'title': title,
      'image_url': imageUrl,
      'action_type': actionType,
      'action_value': actionValue,
    };
  }
}