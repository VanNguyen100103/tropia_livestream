import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:tropia_mobile_app_android/core/utils/dashboard_controller.dart';
import 'package:tropia_mobile_app_android/features/user/home/domain/repositories/home_repository_impl.dart';
import '../../../../../core/network/dio_client.dart';
import '../../data/datasources/home_remote_datasource.dart';
import '../../domain/repositories/home_repository.dart';
import '../../data/models/banner_model.dart';

import '../../../dashboard/presentation/dashboard_page.dart';

class PromotionalBanner extends StatefulWidget {
  const PromotionalBanner({super.key});

  @override
  State<PromotionalBanner> createState() => _PromotionalBannerState();
}

class _PromotionalBannerState extends State<PromotionalBanner> {
  late Future<List<BannerModel>> _bannersFuture;
  int _currentIndex = 0; // Thêm biến để track banner hiện tại
  final CarouselSliderController _carouselController = CarouselSliderController(); // Controller để điều khiển carousel

  @override
  void initState() {
    super.initState();
    // Khởi tạo Repository & Gọi API
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    final HomeRepository repository = HomeRepositoryImpl(
      remoteDataSource: dataSource,
    );

    _bannersFuture = repository.getBanners();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<BannerModel>>(
      future: _bannersFuture,
      builder: (context, snapshot) {
        // 1. Đang tải: Hiện Loading hoặc khung xương (Shimmer)
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 150,
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        // 2. Có lỗi hoặc Không có dữ liệu: Ẩn Widget
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        // 3. Có dữ liệu: Hiển thị Slider
        final banners = snapshot.data!;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Tiêu đề
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.yellow[700],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        "ƯU ĐÃI ĐẶC BIỆT",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              // Carousel Slider
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: CarouselSlider(
                  carouselController: _carouselController,
                  options: CarouselOptions(
                    height: 150.0,
                    autoPlay: banners.length > 1,
                    autoPlayInterval: const Duration(seconds: 4), // Tăng thời gian giữa các slide
                    autoPlayAnimationDuration: const Duration(milliseconds: 800), // Làm chậm animation chuyển
                    autoPlayCurve: Curves.easeInOutCubic, // Easing curve mượt hơn
                    enlargeCenterPage: false,
                    viewportFraction: 1.0,
                    enableInfiniteScroll: banners.length > 1,
                    pauseAutoPlayOnTouch: true, // Tạm dừng khi người dùng chạm
                    pauseAutoPlayOnManualNavigate: true, // Tạm dừng khi manual navigate
                    onPageChanged: (index, reason) {
                      setState(() {
                        _currentIndex = index;
                      });
                    },
                  ),
                  items: banners.map((banner) {
                    return Builder(
                      builder: (BuildContext context) {
                        return InkWell(
                            onTap: () {
                              // Chuyển sang tab khuyến mãi
                              Navigator.of(context).maybePop();
                              Future.delayed(const Duration(milliseconds: 200), () {
                                // Đảm bảo pop xong mới chuyển tab (nếu đang ở màn khác)
                                // Nếu không có Navigator để pop thì vẫn chuyển tab
                                try {
                                 DashboardController.switchTab(DashboardPage.tabPromotions);
                                } catch (_) {}
                              });
                            },
                            child: Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              // Thêm bóng đổ nhẹ cho đẹp
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CachedNetworkImage(
                                imageUrl: banner.imageUrl,
                                fit: BoxFit.cover,
                                width: double.infinity,
                                height: 150,
                                placeholder: (context, url) => Shimmer.fromColors(
                                  baseColor: Colors.grey[200]!,
                                  highlightColor: Colors.grey[100]!,
                                  child: Container(color: Colors.white),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.grey[300],
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.broken_image, color: Colors.grey),
                                      SizedBox(height: 4),
                                      Text(
                                        "Lỗi ảnh",
                                        style: TextStyle(fontSize: 10, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),

              // Dots Indicator
              if (banners.length > 1) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: banners.asMap().entries.map((entry) {
                    return GestureDetector(
                      onTap: () => _carouselController.jumpToPage(entry.key),
                      child: Container(
                        width: 8.0,
                        height: 8.0,
                        margin: const EdgeInsets.symmetric(horizontal: 4.0),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _currentIndex == entry.key
                              ? Colors.yellow[700] // Màu active
                              : Colors.grey[400], // Màu inactive
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
