import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// ... các import cũ ...
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/featured_category_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/domain/repositories/home_repository.dart';
import 'package:tropia_mobile_app_android/features/user/home/domain/repositories/home_repository_impl.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/category_products_section.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/daily_market_section.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/flash_sale_section.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/loyalty_card.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/promotional_banner.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/ready_to_cook_section.dart';
// Import Profile Feature
import 'package:tropia_mobile_app_android/features/user/profile/data/datasources/profile_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/profile_repository.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Biến cho Home Feature
  late final HomeRepository _homeRepository;
  late Future<List<FeaturedCategoryModel>> _featuredCategoriesFuture;

  // [MỚI] Biến cho Profile Feature (Loyalty)
  String _rankName = "Thành viên";
  int _currentPoints = 0;
  String _barcode = "";

  @override
  void initState() {
    super.initState();
    final dio = DioClient().dio;

    // 1. Init Home Repo
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    _homeRepository = HomeRepositoryImpl(remoteDataSource: dataSource);
    _featuredCategoriesFuture = _homeRepository.getFeaturedCategories();

    // 2. [MỚI] Gọi API Profile để lấy Loyalty
    _loadUserProfile(dio);
  }

  Future<void> _loadUserProfile(Dio dio) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null) return;

    // A. Load cache cũ trước (để UI không bị giật về 0)
    if (mounted) {
      setState(() {
        _rankName = prefs.getString('loyalty_rank') ?? "Thành viên";
        _currentPoints = prefs.getInt('loyalty_points') ?? 0;
        _barcode = prefs.getString('loyalty_barcode') ?? "";
      });
    }

    // B. Gọi API lấy mới nhất
    final profileRepo = ProfileRepository(
      remoteDataSource: ProfileRemoteDataSource(client: dio),
    );

    final userProfile = await profileRepo.getUserProfile(userId);

    if (userProfile != null && mounted) {
      setState(() {
        _rankName = userProfile.loyalty.rankName;
        _currentPoints = userProfile.loyalty.currentPoints;
        _barcode = userProfile.loyalty.barcode;
      });

      // C. Lưu cache mới
      await prefs.setString('loyalty_rank', _rankName);
      await prefs.setInt('loyalty_points', _currentPoints);
      await prefs.setString('loyalty_barcode', _barcode);
      // Lưu thêm avatar, name nếu cần cho Profile Page sau này
      await prefs.setString('user_avatar', userProfile.avatarUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),

              // [MỚI] Truyền dữ liệu vào LoyaltyCard
              LoyaltyCard(
                rankName: _rankName,
                points: _currentPoints,
                barcode: _barcode,
              ),

              const PromotionalBanner(),
              // const CategoryList(),
              const FlashSaleSection(),
              const SizedBox(height: 15),
              const ReadyToCookSection(),
              const DailyMarketSection(),
              const SizedBox(height: 15),

              // Danh mục sản phẩm (FutureBuilder cũ giữ nguyên)
              FutureBuilder<List<FeaturedCategoryModel>>(
                future: _featuredCategoriesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError ||
                      !snapshot.hasData ||
                      snapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Column(
                    children: snapshot.data!.map((categoryModel) {
                      return CategoryProductsSection(
                        categoryData: categoryModel,
                      );
                    }).toList(),
                  );
                },
              ),
              const SizedBox(height: 50),
            ],
          ),
        ),
      ),
    );
  }
}
