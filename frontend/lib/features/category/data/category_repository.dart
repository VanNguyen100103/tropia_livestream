import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/features/category/models/category_model.dart';

class CategoryRepository {
  CategoryRepository._();
  static final instance = CategoryRepository._();

  get _public => AuthService.instance.authorizedDio();

  /// GET /api/categories
  Future<List<CategoryModel>> list() async {
    final res = await _public.get('/api/categories');
    return (res.data as List)
        .map((e) => CategoryModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// GET /api/categories/:slug
  Future<CategoryModel> getBySlug(String slug) async {
    final res = await _public.get('/api/categories/$slug');
    return CategoryModel.fromJson(res.data as Map<String, dynamic>);
  }
}
