import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/pages/search_page.dart';
import '../../data/models/featured_category_model.dart';
import 'product_card.dart';

class CategoryProductsSection extends StatelessWidget {
  final FeaturedCategoryModel categoryData;

  const CategoryProductsSection({super.key, required this.categoryData});

  @override
  Widget build(BuildContext context) {
    if (categoryData.products.isEmpty) {
      return const SizedBox.shrink();
    }

    Color headerColor = categoryData.color;
    String categoryName = categoryData.name;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      color: Colors.white,
      child: Column(
        children: [
          // --- HEADER GIỮ NGUYÊN ---
          Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                top: 20,
                left: 0,
                right: 0,
                child: Container(height: 2, color: headerColor),
              ),
              ClipPath(
                clipper: RibbonClipper(),
                child: Container(
                  width: 280,
                  height: 45,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: headerColor,
                    gradient: LinearGradient(
                      colors: [
                        headerColor,
                        headerColor.withValues(alpha: 0.8),
                        headerColor,
                      ],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Text(
                    categoryName.toUpperCase(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      shadows: [
                        Shadow(
                          color: Colors.black26,
                          offset: Offset(1, 1),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          // --- GRID SẢN PHẨM ---
          LayoutBuilder(
            builder: (context, constraints) {
              double screenWidth = constraints.maxWidth;
              int crossAxisCount = screenWidth < 600 ? 2 : 3;
              double padding = 20;
              double spacing = 10;
              double availableWidth =
                  screenWidth - padding - (spacing * (crossAxisCount - 1));
              double itemWidth = availableWidth / crossAxisCount;
              double targetItemHeight = 310;
              double childAspectRatio = itemWidth / targetItemHeight;

              return GridView.builder(
                padding: const EdgeInsets.all(10),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: childAspectRatio,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                ),
                itemCount: categoryData.products.length,
                itemBuilder: (context, index) {
                  return ProductCard(
                    product: categoryData.products[index],
                    isFlashSale: false,
                  );
                },
              );
            },
          ),

          // --- BUTTON XEM TẤT CẢ ---
          Padding(
            padding: const EdgeInsets.only(bottom: 15, top: 10),
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SearchPage(
                      initialCategoryId: categoryData.id.toString(),
                      initialCategoryName: categoryData.name,
                    ),
                  ),
                );
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Xem tất cả",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: headerColor,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded, size: 12, color: headerColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RibbonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width - 15, size.height / 2);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.lineTo(15, size.height / 2);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
