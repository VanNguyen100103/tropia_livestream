import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/category_model.dart';
// --- UPDATE 1: Import SearchPage ---
import 'package:tropia_mobile_app_android/features/user/home/presentation/pages/search_page.dart';

class CategoryList extends StatefulWidget {
  const CategoryList({super.key});

  @override
  State<CategoryList> createState() => _CategoryListState();
}

class _CategoryListState extends State<CategoryList> {
  late Future<List<CategoryModel>> _categoriesFuture;

  @override
  void initState() {
    super.initState();
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    _categoriesFuture = dataSource.getCategories();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 100,
      margin: const EdgeInsets.only(top: 10),
      child: FutureBuilder<List<CategoryModel>>(
        future: _categoriesFuture,
        builder: (context, snapshot) {
          // 1. Đang tải
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 2. Lỗi
          if (snapshot.hasError) {
            return Center(child: Text('Lỗi: ${snapshot.error}'));
          }

          // 3. Rỗng
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text("Không có danh mục"));
          }

          final categories = snapshot.data!;

          // 4. Hiển thị danh sách
          return ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            separatorBuilder: (context, index) => const SizedBox(width: 20),
            itemBuilder: (context, index) {
              final cat = categories[index];
              bool hasIconUrl = cat.icon.isNotEmpty;

              // --- UPDATE 2: Bọc InkWell để bắt sự kiện click ---
              return InkWell(
                borderRadius: BorderRadius.circular(
                  8,
                ), // Hiệu ứng ripple bo tròn
                onTap: () {
                  // Điều hướng sang SearchPage kèm ID và Tên
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SearchPage(
                        initialCategoryId: cat.id.toString(),
                        initialCategoryName: cat.name,
                      ),
                    ),
                  );
                },
                child: SizedBox(
                  width: 70,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Container(
                        width: 55,
                        height: 55,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: hasIconUrl
                            ? Image.network(
                                cat.icon,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    _buildDefaultIcon(),
                              )
                            : _buildDefaultIcon(),
                      ),
                      const SizedBox(height: 8),

                      Text(
                        cat.name,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Colors.black87,
                          height: 1.1,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildDefaultIcon() {
    return const Icon(Icons.category_outlined, color: Colors.green, size: 30);
  }
}
