// =============================================================================
// home_screen.dart
// =============================================================================
// Màn hình Trang chủ của Tropia – placeholder đơn giản.
//
// Trong dự án thực tế, màn hình này sẽ được mở rộng với:
//   - Banner carousel
//   - Danh mục sản phẩm
//   - Flash sale section
//   - Gợi ý sản phẩm
//   - v.v.
//
// Hiện tại chỉ hiển thị UI demo để project có thể chạy đầy đủ.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/product/screens/product_detail_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Search bar ──────────────────────────────────────────────
            _buildSearchBar(context),

            const SizedBox(height: AppSizes.md),

            // ── Banner placeholder ──────────────────────────────────────
            _buildBannerPlaceholder(),

            const SizedBox(height: AppSizes.md),

            // ── Categories ──────────────────────────────────────────────
            _buildSectionTitle('Danh mục'),
            const SizedBox(height: AppSizes.sm),
            _buildCategories(),

            const SizedBox(height: AppSizes.md),

            // ── Flash sale ──────────────────────────────────────────────
            _buildSectionTitle('Flash Sale 🔥'),
            const SizedBox(height: AppSizes.sm),
            _buildFlashSaleGrid(),

            const SizedBox(height: AppSizes.md),

            // ── Recommended ─────────────────────────────────────────────
            _buildSectionTitle('Dành cho bạn'),
            const SizedBox(height: AppSizes.sm),
            _buildRecommendedGrid(),

            const SizedBox(height: AppSizes.xxl),
          ],
        ),
      ),
    );
  }

  void _openProductDetail(BuildContext context, String productName) {
    AppLogger.logUserEvent(
      action: 'open_product',
      context: 'HomeScreen',
      metadata: {'name': productName},
    );
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ProductDetailScreen(
        slug: productName.toLowerCase().replaceAll(' ', '-'),
      ),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Search bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSearchBar(BuildContext context) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: AppSizes.md),
          const Icon(
            Icons.search,
            color: AppColors.textHint,
            size: AppSizes.iconSm + 4,
          ),
          const SizedBox(width: AppSizes.sm),
          const Expanded(
            child: Text(
              'Tìm kiếm rau củ, thực phẩm...',
              style: TextStyle(
                color: AppColors.textHint,
                fontSize: AppSizes.fontMd,
              ),
            ),
          ),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(AppSizes.radiusFull),
                bottomRight: Radius.circular(AppSizes.radiusFull),
              ),
            ),
            child: const Center(
              child: Text(
                'Tìm',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: AppSizes.fontSm,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Banner placeholder
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBannerPlaceholder() {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryLight],
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusXl),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            right: 20,
            bottom: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
            ),
          ),

          // Content
          Padding(
            padding: const EdgeInsets.all(AppSizes.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  '🥦 Rau Củ Tươi Ngon',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.fontXxl,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSizes.xs),
                const Text(
                  'Giao hàng trong 2 giờ\nTừ nông trại đến tay bạn',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: AppSizes.fontSm,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: AppSizes.sm),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.md,
                    vertical: AppSizes.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  ),
                  child: const Text(
                    'Đặt ngay →',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.fontSm,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Section title
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSectionTitle(String title) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: AppSizes.fontLg,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Text(
          'Xem tất cả',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: AppSizes.fontSm,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Categories
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCategories() {
    final categories = [
      ('🥦', 'Rau củ'),
      ('🍎', 'Trái cây'),
      ('🥩', 'Thịt cá'),
      ('🥛', 'Sữa'),
      ('🍳', 'Gia vị'),
      ('🧴', 'Chăm sóc'),
      ('🍜', 'Thực phẩm'),
      ('🛒', 'Tiện dụng'),
    ];

    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSizes.sm),
        itemBuilder: (context, index) {
          final cat = categories[index];
          return Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppSizes.radiusLg),
                ),
                child: Center(
                  child: Text(
                    cat.$1,
                    style: const TextStyle(fontSize: 26),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                cat.$2,
                style: const TextStyle(
                  fontSize: AppSizes.fontXs,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Flash sale grid
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFlashSaleGrid() {
    final products = [
      ('Cải xanh organic', '28.000đ', '35.000đ', '-20%', '🥦'),
      ('Cà chua bi đỏ', '38.000đ', '45.000đ', '-16%', '🍅'),
      ('Táo Fuji Nhật', '85.000đ', '120.000đ', '-29%', '🍎'),
      ('Thịt heo nạc vai', '125.000đ', '160.000đ', '-22%', '🥩'),
    ];

    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: products.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSizes.sm),
        itemBuilder: (context, index) {
          final p = products[index];
          return _ProductCard(
            emoji: p.$5,
            name: p.$1,
            salePrice: p.$2,
            originalPrice: p.$3,
            discount: p.$4,
            onTap: () => _openProductDetail(context, p.$1),
          );
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Recommended grid (2 columns)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRecommendedGrid() {
    final products = [
      ('Bắp cải trắng', '22.000đ', '28.000đ', '🥬'),
      ('Khoai tây Đà Lạt', '32.000đ', '40.000đ', '🥔'),
      ('Cam sành Vĩnh Long', '55.000đ', '70.000đ', '🍊'),
      ('Dưa leo baby', '25.000đ', '30.000đ', '🥒'),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSizes.sm,
        crossAxisSpacing: AppSizes.sm,
        childAspectRatio: 0.75,
      ),
      itemCount: products.length,
      itemBuilder: (context, index) {
        final p = products[index];
        return _ProductCard(
          emoji: p.$4,
          name: p.$1,
          salePrice: p.$2,
          originalPrice: p.$3,
          onTap: () => _openProductDetail(context, p.$1),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ProductCard – card sản phẩm đơn giản
// ─────────────────────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final String emoji;
  final String name;
  final String salePrice;
  final String originalPrice;
  final String? discount;
  final VoidCallback? onTap;

  const _ProductCard({
    required this.emoji,
    required this.name,
    required this.salePrice,
    required this.originalPrice,
    this.discount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: _buildCard(),
    );
  }

  Widget _buildCard() {
    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image placeholder
          Stack(
            children: [
              Container(
                height: 110,
                color: AppColors.primaryContainer,
                child: Center(
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 48),
                  ),
                ),
              ),
              if (discount != null)
                Positioned(
                  top: AppSizes.xs,
                  left: AppSizes.xs,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.xs,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.liveRed,
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    ),
                    child: Text(
                      discount!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.all(AppSizes.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: AppSizes.fontSm,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  salePrice,
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: AppSizes.fontMd,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  originalPrice,
                  style: const TextStyle(
                    color: AppColors.textHint,
                    fontSize: AppSizes.fontXs,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
