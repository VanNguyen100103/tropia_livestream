import 'product_model.dart';

class FlashSaleModel {
  final String id;
  final String title;
  final DateTime? startTime;
  final DateTime? endTime;
  final int? active;
  final String? activeLabel;
  final String? bannerImage;
  final List<ProductModel> products;

  FlashSaleModel({
    required this.id,
    required this.title,
    this.startTime,
    this.endTime,
    this.active,
    this.activeLabel,
    this.bannerImage,
    required this.products,
  });

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  factory FlashSaleModel.fromJson(Map<String, dynamic> json) {
    var list = json['items'] as List? ?? [];
    List<ProductModel> productsList = list
        .map((i) => ProductModel.fromJson(i))
        .toList();

    return FlashSaleModel(
      id: json['flash_sale_id']?.toString() ?? json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? 'Flash Sale',
      startTime: _parseDateTime(json['start_time'] ?? json['startTime']),
      endTime: _parseDateTime(json['end_time'] ?? json['endTime']),
      active: (json['active'] as num?)?.toInt(),
      activeLabel: json['active_label']?.toString(),
      bannerImage: json['banner_image']?.toString(),
      products: productsList,
    );
  }
}
