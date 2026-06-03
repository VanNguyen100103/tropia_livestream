import 'package:flutter/foundation.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/banner_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/category_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/flash_sale_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/product_model.dart';

import '../../domain/repositories/home_repository.dart';
import '../../data/models/featured_category_model.dart';
import '../../data/models/search_products_result.dart';

class HomeRepositoryImpl implements HomeRepository {
    @override
    Future<SearchProductsResult> searchProductsWithMeta({
      String? keyword,
      String? categoryId,
      int page = 1,
      int limit = 10,
      String? id,
    }) async {
      return await remoteDataSource.searchProductsWithMeta(
        keyword: keyword,
        categoryId: categoryId,
        page: page,
        limit: limit,
        id: id,
      );
    }
  final HomeRemoteDataSource remoteDataSource;

  HomeRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<FeaturedCategoryModel>> getFeaturedCategories() async {
    try {
      // Gọi DataSource để lấy dữ liệu từ API
      return await remoteDataSource.getFeaturedCategories();
    } catch (e) {
      // Nếu có lỗi, trả về list rỗng (hoặc xử lý lỗi tùy ý)
      debugPrint("Lỗi Repository: $e");
      return [];
    }
  }

  @override
  Future<List<ProductModel>> searchProducts({
    String? keyword,
    String? categoryId,
    int page = 1,
    int limit = 10,
    String? id,
  }) async {
    try {
      return await remoteDataSource.searchProducts(
        keyword: keyword,
        categoryId: categoryId,
        page: page,
        limit: limit,
        id: id,
      );
    } catch (e) {
      debugPrint("Lỗi Search Repository: $e");
      return [];
    }
  }

  @override
  Future<List<CategoryModel>> getCategories() async {
    try {
      return await remoteDataSource.getCategories();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<BannerModel>> getBanners() async {
    try {
      return await remoteDataSource.getBanners();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<List<FlashSaleModel>> getFlashSales() async {
    try {
      return await remoteDataSource.getFlashSales();
    } catch (e) {
      debugPrint("Lỗi Repository FlashSales: $e");
      return [];
    }
  }

  @override
  Future<FlashSaleModel?> getFlashSale() async {
    try {
      return await remoteDataSource.getFlashSale();
    } catch (e) {
      debugPrint("Lỗi Repository FlashSale: $e");
      return null;
    }
  }
}
