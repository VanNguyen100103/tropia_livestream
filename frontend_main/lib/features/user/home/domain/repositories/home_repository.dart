import 'package:tropia_mobile_app_android/features/user/home/data/models/banner_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/category_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/flash_sale_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/product_model.dart';

import '../../data/models/featured_category_model.dart';
import '../../data/models/search_products_result.dart';
// Nếu bạn có các hàm khác (banner, category...) thì import thêm model tương ứng

abstract class HomeRepository {
    Future<SearchProductsResult> searchProductsWithMeta({
      String? keyword,
      String? categoryId,
      int page,
      int limit,
      String? id,
    });
  // Hàm lấy danh sách danh mục nổi bật
  Future<List<FeaturedCategoryModel>> getFeaturedCategories();
  Future<List<ProductModel>> searchProducts({
    String? keyword,
    String? categoryId,
    int page,
    int limit,
    String? id,
  });
  Future<List<CategoryModel>> getCategories();
  Future<List<BannerModel>> getBanners();
  Future<List<FlashSaleModel>> getFlashSales();
  Future<FlashSaleModel?> getFlashSale();
}
