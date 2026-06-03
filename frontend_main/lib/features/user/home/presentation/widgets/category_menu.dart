import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:tropia_mobile_app_android/core/constants/app_colors.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/category_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/domain/entities/category.dart'; // Import Entity
import 'package:tropia_mobile_app_android/features/user/home/presentation/pages/search_page.dart';

class CategoryMenu extends StatefulWidget {
  const CategoryMenu({super.key});

  @override
  State<CategoryMenu> createState() => _CategoryMenuState();
}

class _CategoryMenuState extends State<CategoryMenu> {
  late Future<List<CategoryModel>> _categoriesFuture;
  String? _versionLabel;

  bool _hasValidMedia(String? value) {
    if (value == null) return false;
    final v = value.trim();
    return v.isNotEmpty && v != '0';
  }

  Widget _buildLeading(
    CategoryEntity item, {
    IconData fallbackIcon = Icons.subdirectory_arrow_right,
  }) {
    if (_hasValidMedia(item.image)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.network(
          item.image,
          width: 24,
          height: 24,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Icon(fallbackIcon, size: 18, color: Colors.grey);
          },
        ),
      );
    }

    if (_hasValidMedia(item.icon)) {
      return Image.network(
        item.icon,
        width: 24,
        height: 24,
        errorBuilder: (context, error, stackTrace) {
          return Icon(fallbackIcon, size: 18, color: Colors.grey);
        },
      );
    }

    return Icon(fallbackIcon, size: 18, color: Colors.grey);
  }

  @override
  void initState() {
    super.initState();
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    _categoriesFuture = dataSource.getCategories();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      final label = build.isEmpty ? "v$version" : "v$version+$build";

      if (!mounted) return;
      setState(() => _versionLabel = label);
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = "v?");
    }
  }

  @override
  Widget build(BuildContext context) {
    final double statusBarHeight = MediaQuery.of(context).padding.top;

    return Container(
      margin: EdgeInsets.only(top: statusBarHeight),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(30),
          bottomRight: Radius.circular(0),
        ),
        child: Drawer(
          elevation: 0,
          backgroundColor: Colors.white,
          child: Column(
            children: [
              _buildModernHeader(),
              const SizedBox(height: 10),
              Expanded(
                child: FutureBuilder<List<CategoryModel>>(
                  future: _categoriesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(child: Text("Lỗi: ${snapshot.error}"));
                    }
                    if (!snapshot.hasData || snapshot.data!.isEmpty) {
                      return const Center(child: Text("Không có danh mục"));
                    }

                    final categories = snapshot.data!;
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemCount: categories.length,
                      itemBuilder: (context, index) {
                        return _buildCategoryGroup(context, categories[index]);
                      },
                    );
                  },
                ),
              ),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  // --- WIDGET HEADER (Giữ nguyên) ---
  Widget _buildModernHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 30),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.black, Color(0xFF424242)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomRight: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Icon(Icons.storefront, size: 30, color: AppColors.black),
          ),
          const SizedBox(height: 15),
          const Text(
            "Tropia Market",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            "Danh mục sản phẩm",
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // --- WIDGET ITEM: MENU ĐA CẤP (QUAN TRỌNG) ---
  Widget _buildCategoryGroup(BuildContext context, CategoryEntity parent) {
    // Nếu danh mục không có con, hiển thị như item thường
    if (parent.children.isEmpty) {
      return _buildSingleItem(context, parent);
    }

    // Nếu có con, dùng ExpansionTile
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: _buildLeading(
              parent,
              fallbackIcon: Icons.keyboard_arrow_right,
            ),
          ),
        ),
        title: Text(
          parent.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            color: Color(0xFF333333),
          ),
        ),
        children: parent.children.map((child) {
          return _buildSubCategoryItem(context, child);
        }).toList(),
      ),
    );
  }

  // Widget con (Level 2)
  Widget _buildSubCategoryItem(BuildContext context, CategoryEntity item) {
    // Level 2 có Level 3
    if (item.children.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(left: 16, right: 8),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.only(left: 16, right: 16),
          leading: SizedBox(
            width: 24,
            height: 24,
            child: Center(
              child: _buildLeading(
                item,
                fallbackIcon: Icons.keyboard_arrow_right,
              ),
            ),
          ),
          title: Text(
            item.name,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
          children: item.children
              .map((third) => _buildThirdCategoryItem(context, third))
              .toList(),
        ),
      );
    }

    // Level 2 leaf
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      leading: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: _buildLeading(
            item,
            fallbackIcon: Icons.subdirectory_arrow_right,
          ),
        ),
      ),
      title: Text(
        item.name,
        style: const TextStyle(fontSize: 14, color: Colors.black87),
      ),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SearchPage(
              initialCategoryId: item.id,
              initialCategoryName: item.name,
            ),
          ),
        );
      },
    );
  }

  // Widget con (Level 3)
  Widget _buildThirdCategoryItem(BuildContext context, CategoryEntity item) {
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 64, right: 16),
      leading: SizedBox(
        width: 24,
        height: 24,
        child: Center(
          child: _buildLeading(
            item,
            fallbackIcon: Icons.subdirectory_arrow_right,
          ),
        ),
      ),
      title: Text(
        item.name,
        style: const TextStyle(fontSize: 13, color: Colors.black87),
      ),
      onTap: () {
        Navigator.pop(context);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => SearchPage(
              initialCategoryId: item.id,
              initialCategoryName: item.name,
            ),
          ),
        );
      },
    );
  }

  // Widget cho item không có con (dự phòng)
  Widget _buildSingleItem(BuildContext context, CategoryEntity item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: SizedBox(
          width: 24,
          height: 24,
          child: Center(
            child: _buildLeading(
              item,
              fallbackIcon: Icons.keyboard_arrow_right,
            ),
          ),
        ),
        title: Text(
          item.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SearchPage(
                initialCategoryId: item.id,
                initialCategoryName: item.name,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Text(
        _versionLabel ?? "v...",
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }
}
