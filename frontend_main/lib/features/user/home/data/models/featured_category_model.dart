import 'dart:ui';
import 'product_model.dart';

class FeaturedCategoryModel {
  final String id;
  final String name;
  final String headerColorHex; // Lưu mã màu dạng String (#2E7D32)
  final List<ProductModel> products;

  FeaturedCategoryModel({
    required this.id,
    required this.name,
    required this.headerColorHex,
    required this.products,
  });

  factory FeaturedCategoryModel.fromJson(Map<String, dynamic> json) {
    var list = json['items'] as List? ?? [];
    List<ProductModel> productsList = list
        .whereType<Map>()
        .map((i) => ProductModel.fromJson(i.cast<String, dynamic>()))
        .toList();

    return FeaturedCategoryModel(
      id: json['category_id'] ?? '',
      name: json['category_name'] ?? '',
      headerColorHex: json['header_color'] ?? '#2E7D32',
      products: productsList,
    );
  }

  // Helper chuyển Hex String (#2E7D32) thành Color Flutter
  Color get color {
    try {
      final buffer = StringBuffer();
      if (headerColorHex.length == 6 || headerColorHex.length == 7) buffer.write('ff');
      buffer.write(headerColorHex.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return const Color(0xFF2E7D32); // Màu mặc định nếu lỗi
    }
  }
}