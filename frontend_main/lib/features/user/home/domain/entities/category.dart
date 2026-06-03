// lib/features/user/home/domain/entities/category.dart
class CategoryEntity {
  final String id;
  final String name;       // Map từ 'title'
  final String icon;       // Map từ 'icon'
  final String image;      // Map từ 'image' (nếu có)
  final List<CategoryEntity> children; // Danh sách danh mục con

  CategoryEntity({
    required this.id,
    required this.name,
    required this.icon,
    this.image = '',
    this.children = const [],
  });
}