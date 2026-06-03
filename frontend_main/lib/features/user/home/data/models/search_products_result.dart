import 'product_model.dart';

class SearchProductsResult {
  final List<ProductModel> products;
  final int total;

  SearchProductsResult({required this.products, required this.total});
}