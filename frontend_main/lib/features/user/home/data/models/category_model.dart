// lib/features/user/home/data/models/category_model.dart
import '../../domain/entities/category.dart';

class CategoryModel extends CategoryEntity {
  CategoryModel({
    required super.id,
    required super.name,
    required super.icon,
    super.image,
    super.children,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    // 1. Xử lý danh sách con (children) nếu có
    List<CategoryModel> parsedChildren = [];
    if (json['children'] != null) {
      parsedChildren = (json['children'] as List)
          .map((item) => CategoryModel.fromJson(item))
          .toList();
    }

    // 2. Map dữ liệu
    final rawName =
        json['title'] ?? json['name'] ?? json['category_name'] ?? '';

    return CategoryModel(
      id: json['id']?.toString() ?? '',
      name: rawName.toString(),
      icon: (json['icon'] ?? '').toString(),
      image: (json['image'] ?? '').toString(),
      children: parsedChildren,
    );
  }
}
