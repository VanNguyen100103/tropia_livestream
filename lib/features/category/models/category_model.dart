class CategoryModel {
  final String id;
  final String slug;
  final String name;
  final String? iconUrl;

  const CategoryModel({
    required this.id,
    required this.slug,
    required this.name,
    this.iconUrl,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> j) => CategoryModel(
        id: j['id'] as String,
        slug: j['slug'] as String,
        name: j['name'] as String,
        iconUrl: j['icon_url'] as String?,
      );
}
