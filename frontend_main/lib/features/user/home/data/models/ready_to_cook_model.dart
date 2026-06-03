import 'product_model.dart';

class ReadyToCookModel {
  final String id;
  final String name;
  final String image;
  final String description;
  final double totalPriceEstimate;
  final List<ProductModel> ingredients;

  ReadyToCookModel({
    required this.id,
    required this.name,
    required this.image,
    required this.description,
    required this.totalPriceEstimate,
    required this.ingredients,
  });

  factory ReadyToCookModel.fromJson(Map<String, dynamic> json) {
    // 1. Parse list ingredients
    var rawIngredients = json['ingredients'] as List? ?? [];

    List<ProductModel> parsedIngredients = rawIngredients
        .whereType<Map>()
        .map((i) => ProductModel.fromJson(i.cast<String, dynamic>()))
        .toList();

    return ReadyToCookModel(
      id: json['id']?.toString() ?? '',
      name: json['name'] ?? '',
      image: json['image'] ?? '',
      description: json['description'] ?? '',
      totalPriceEstimate:
          (json['total_price_estimate'] as num?)?.toDouble() ?? 0,
      ingredients: parsedIngredients,
    );
  }
}
