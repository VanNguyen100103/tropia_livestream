class NotificationModel {
  final int id;
  final String title;
  final String content; // JSON trả về là 'body' nhưng ta map sang 'content'
  final String? deepLink;
  final String type; // promotion, order, system...
  bool isRead;
  final String createdAt;

  NotificationModel({
    required this.id,
    required this.title,
    required this.content,
    this.deepLink,
    this.type = 'system',
    this.isRead = false,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: int.tryParse(json['id'].toString()) ?? 0,
      title: json['title'] ?? 'Thông báo',
      content: json['content'] ?? '',
      deepLink: json['deep_link'],
      type: json['action_type'] ?? 'system',
      // API trả về 0 hoặc 1, hoặc true/false
      isRead: (json['is_read'] == 1 || json['is_read'] == true),
      createdAt: json['sent_at'] ?? json['created_at'] ?? '',
    );
  }
}