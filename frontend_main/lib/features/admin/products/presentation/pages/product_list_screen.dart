import 'dart:async';
// Needed for CategoryManagementDialog
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
// Needed for CategoryManagementDialog
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/products/data/models/product_model.dart';
import 'package:tropia_mobile_app_android/features/admin/products/data/repositories/product_repository.dart';
import 'package:tropia_mobile_app_android/features/admin/products/presentation/pages/category_management_dialog.dart';
import 'package:tropia_mobile_app_android/features/admin/products/presentation/widgets/product_form_dialog.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
// Needed for CategoryManagementDialog

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  // State variables
  List<ProductModel> _products = [];
  bool _isLoading = false;
  bool _isMoreLoading = false; // Loading for pagination
  int _currentPage = 1;
  int _totalPages = 1;

  // Search
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce; // For search delay

  // Scroll Controller for pagination
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initData();

    // Listener for scroll events to load more products
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final position = _scrollController.position;
      const threshold = 200.0;
      final shouldLoadMore =
          position.pixels >= (position.maxScrollExtent - threshold) &&
          !position.outOfRange;
      if (shouldLoadMore) {
        _loadMoreProducts();
      }
    });
  }

  Future<void> _initData() async {
    final dio = DioClient().dio;
    final authRepo = AppAuthRepository(
      remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
    );
    await authRepo.authenticateApp();
    await _fetchProducts(refresh: true);
  }

  Future<void> _fetchProducts({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _isLoading = true;
        _isMoreLoading = false;
        _currentPage = 1; // Reset to page 1
        _products = [];
      });
    }

    final dio = DioClient().dio;
    final repo = ProductRepository(client: dio);

    try {
      final result = await repo.getProducts(
        page: _currentPage,
        limit: 10,
        keyword: _searchController.text,
      );

      if (mounted) {
        setState(() {
          _products =
              (result['items'] as List<ProductModel>?) ?? <ProductModel>[];
          _totalPages = (result['total_pages'] as int?) ?? 1;
          _currentPage = (result['page'] as int?) ?? 1;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadMoreProducts() async {
    if (_isLoading || _isMoreLoading) return;
    if (_currentPage >= _totalPages) return;
    setState(() => _isMoreLoading = true);

    final dio = DioClient().dio;
    final repo = ProductRepository(client: dio);
    final nextPage = _currentPage + 1;

    try {
      final result = await repo.getProducts(
        page: nextPage,
        limit: 10,
        keyword: _searchController.text,
      );

      if (mounted) {
        setState(() {
          _products.addAll(
            (result['items'] as List<ProductModel>?) ?? <ProductModel>[],
          );
          _currentPage = (result['page'] as int?) ?? nextPage;
          _totalPages = (result['total_pages'] as int?) ?? _totalPages;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isMoreLoading = false);
      }
    }
  }

  // Handle search with Debounce (wait for user to stop typing for 500ms)
  void _onSearchChanged(String value) {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchProducts(refresh: true);
    });
  }

  Future<void> _deleteProduct(ProductModel product) async {
    // Show confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: Text("Bạn có chắc chắn muốn xóa sản phẩm '${product.name}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Hủy"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Xóa", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final dio = DioClient().dio;
      final repo = ProductRepository(client: dio);
      final success = await repo.deleteProduct(product.id);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Đã xóa sản phẩm"),
              backgroundColor: Colors.green,
            ),
          );
          _fetchProducts(refresh: true); // Reload list
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Xóa thất bại"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // [UPDATED] Open ProductFormDialog for Creating Product
  Future<void> _navigateToCreate() async {
    // Show the dialog and wait for the result (Map<String, dynamic>)
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const ProductFormDialog(),
    );

    // If result is not null, call the create API
    if (result != null) {
      // Show loading indicator
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );
      }

      final dio = DioClient().dio;
      final repo = ProductRepository(client: dio);

      // Call Create Product API
      final success = await repo.createProduct(result);

      // Dismiss loading
      if (mounted) Navigator.pop(context);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Tạo sản phẩm thành công!"),
              backgroundColor: Colors.green,
            ),
          );
          _fetchProducts(refresh: true); // Refresh list
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Tạo sản phẩm thất bại"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // [UPDATED] Open ProductFormDialog for Editing Product
  Future<void> _navigateToEdit(ProductModel product) async {
    // Convert ProductModel to Map for the dialog (or modify dialog to accept ProductModel)
    // Here assuming dialog accepts Map based on your previous code
    final productMap = {
      'id': product.id,
      'name': product.name,
      'price': product.price,
      'unit': product.unit,
      'stock': product.stock,
      'description': product.description,
      'image_url': product.image,
      'category_id': product.categoryId, // Ensure ProductModel has this field
      'category': product.categoryName, // For initial text display if needed
    };

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => ProductFormDialog(product: productMap),
    );

    if (result != null) {
      // Show loading
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(child: CircularProgressIndicator()),
        );
      }

      final dio = DioClient().dio;
      final repo = ProductRepository(client: dio);

      // Call Update Product API
      final success = await repo.updateProduct(product.id, result);

      // Dismiss loading
      if (mounted) Navigator.pop(context);

      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Cập nhật thành công!"),
              backgroundColor: Colors.green,
            ),
          );
          _fetchProducts(refresh: true);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Cập nhật thất bại"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // [NEW] Show Options Bottom Sheet (Add Product or Manage Categories)
  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Option 1: Add Product
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_box, color: Colors.orange),
                ),
                title: const Text(
                  "Thêm sản phẩm mới",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text("Tạo sản phẩm và thêm vào kho"),
                onTap: () {
                  Navigator.pop(context); // Close BottomSheet
                  _navigateToCreate(); // Call existing create function
                },
              ),
              const Divider(indent: 16, endIndent: 16),

              // Option 2: Manage Categories
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.category, color: Colors.blue),
                ),
                title: const Text(
                  "Quản lý danh mục",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text("Xem danh sách và tạo danh mục mới"),
                onTap: () {
                  Navigator.pop(context); // Close BottomSheet
                  // Open Category Management Dialog
                  showDialog(
                    context: context,
                    builder: (_) => const CategoryManagementDialog(),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat("#,###", "vi_VN");
    return "${formatter.format(amount)}đ";
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: SafeArea(
        child: Column(
          children: [
            // --- HEADER & SEARCH ---
            Container(
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Row containing Search Bar + Add Button
                  Row(
                    children: [
                      // 1. Search Bar
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            decoration: const InputDecoration(
                              hintText: "Tìm tên sản phẩm...",
                              prefixIcon: Icon(
                                Icons.search,
                                color: Colors.grey,
                              ),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(width: 12), // Spacing
                      // 2. Add Button (Orange Square) - [UPDATED]
                      InkWell(
                        onTap:
                            _showAddOptions, // [UPDATED] Show Options BottomSheet
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          height: 48,
                          width: 48,
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.add, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- LIST PRODUCTS ---
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () => _fetchProducts(refresh: true),
                      color: Colors.orange,
                      child: _products.isEmpty
                          ? const Center(child: Text("Không tìm thấy sản phẩm"))
                          : ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                16,
                                16,
                                80,
                              ),
                              itemCount:
                                  _products.length + (_isMoreLoading ? 1 : 0),
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                if (index == _products.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(8),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                return _buildProductItem(_products[index]);
                              },
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductItem(ProductModel product) {
    bool isInactive = product.status == 'inactive';

    // Check valid image
    bool hasImage =
        product.image.isNotEmpty &&
        product.image != "0" &&
        product.image != "null";

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // --- IMAGE DISPLAY ---
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: hasImage
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      product.image,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.grey,
                          size: 30,
                        );
                      },
                    ),
                  )
                : const Icon(
                    Icons.inventory_2_outlined,
                    color: Colors.grey,
                    size: 30,
                  ),
          ),

          // ------------------------------------
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: isInactive ? Colors.grey : Colors.black87,
                    decoration: isInactive ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      _formatCurrency(product.price),
                      style: const TextStyle(
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Kho: ${product.stock}",
                      style: TextStyle(
                        color: product.stock == 0
                            ? Colors.red
                            : Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Actions: Edit / Delete
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.edit, color: Colors.blue, size: 20),
                onPressed: () => _navigateToEdit(product),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
                onPressed: () => _deleteProduct(product),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
