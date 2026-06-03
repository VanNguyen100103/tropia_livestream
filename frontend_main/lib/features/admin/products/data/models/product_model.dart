class ProductModel {
  final String id;
  final String name;
  final String categoryName;
  final String categoryId; // [MỚI] Thêm ID danh mục
  final double price;
  final int stock;
  final String unit;
  final String image;
  final String status;
  final String description; // [MỚI] Thêm mô tả

  ProductModel({
    required this.id,
    required this.name,
    required this.categoryName,
    required this.categoryId,
    required this.price,
    required this.stock,
    required this.unit,
    required this.image,
    required this.status,
    required this.description,
  });

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    return ProductModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? 'Sản phẩm',
      categoryName: json['category_name'] ?? '',
      // Map từ field 'category_id' của API
      categoryId: json['category_id']?.toString() ?? '', 
      
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      stock: (json['stock'] as num?)?.toInt() ?? 0,
      unit: json['unit'] ?? 'kg', // Mặc định là kg nếu null
      
      // Logic ưu tiên lấy ảnh
      image: json['image']?.toString() ?? json['image_url']?.toString() ?? '',
      
      status: json['status'] ?? 'active',
      description: json['description'] ?? '', // Map field mô tả
    );
  }
}