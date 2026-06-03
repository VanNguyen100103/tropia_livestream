import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/products/data/repositories/product_repository.dart';
// Import Model & Repository
import 'package:tropia_mobile_app_android/features/user/home/data/models/category_model.dart';

class _CategoryOption {
  final String id;
  final String label;

  const _CategoryOption({required this.id, required this.label});
}

class ProductFormDialog extends StatefulWidget {
  final Map<String, dynamic>? product; // Nếu null là Thêm mới, có data là Sửa

  const ProductFormDialog({super.key, this.product});

  @override
  State<ProductFormDialog> createState() => _ProductFormDialogState();
}

class _ProductFormDialogState extends State<ProductFormDialog> {
  // Controller cho các trường nhập liệu
  late TextEditingController _nameController;
  late TextEditingController _priceController;
  late TextEditingController _unitController;
  late TextEditingController _stockController;
  late TextEditingController _descController;
  late TextEditingController _imageController;

  // Biến quản lý danh mục (Dropdown)
  List<CategoryModel> _categoryTree = [];
  List<_CategoryOption> _categoryOptions = [];
  String? _selectedCategoryId;
  bool _isLoadingCategories = true;

  List<_CategoryOption> _flattenCategories(
    List<CategoryModel> roots, {
    int level = 0,
  }) {
    final result = <_CategoryOption>[];

    for (final cat in roots) {
      final prefix = List.filled(level, '—').join(' ');
      final label = prefix.isEmpty ? cat.name : '$prefix ${cat.name}';
      result.add(_CategoryOption(id: cat.id, label: label));

      final children = cat.children;
      final childModels = children
          .cast<dynamic>()
          .whereType<CategoryModel>()
          .toList();
      if (childModels.isNotEmpty) {
        result.addAll(_flattenCategories(childModels, level: level + 1));
      }
    }

    return result;
  }

  @override
  void initState() {
    super.initState();
    final p = widget.product;

    // Khởi tạo giá trị ban đầu
    _nameController = TextEditingController(text: p?['name'] ?? '');
    _priceController = TextEditingController(
      text: p?['price']?.toString() ?? '',
    );
    _unitController = TextEditingController(text: p?['unit'] ?? 'kg');
    _stockController = TextEditingController(
      text: p?['stock']?.toString() ?? '0',
    );
    _descController = TextEditingController(text: p?['description'] ?? '');
    _imageController = TextEditingController(text: p?['image_url'] ?? '');

    // Nếu đang sửa, gán category_id ban đầu (nếu có)
    if (p != null && p['category_id'] != null) {
      _selectedCategoryId = p['category_id'].toString();
    }

    // Load danh sách danh mục từ API
    _loadCategories();
  }

  // Hàm load danh mục
  Future<void> _loadCategories() async {
    try {
      final dio = DioClient().dio;
      final repo = ProductRepository(client: dio);

      // 1. Lấy dữ liệu thô từ API
      final rawCategories = await repo.getCategories();

      if (mounted) {
        setState(() {
          _categoryTree = rawCategories;
          _categoryOptions = _flattenCategories(_categoryTree);
          _isLoadingCategories = false;

          // 3. Xử lý giá trị được chọn (Tránh crash nếu ID không tồn tại)
          if (_categoryOptions.isNotEmpty) {
            final exists = _categoryOptions.any(
              (opt) => opt.id == _selectedCategoryId,
            );
            if (!exists) _selectedCategoryId = _categoryOptions.first.id;
          } else {
            _selectedCategoryId = null;
          }
        });
      }
    } catch (e) {
      debugPrint("Lỗi load categories: $e");
      if (mounted) setState(() => _isLoadingCategories = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _unitController.dispose();
    _stockController.dispose();
    _descController.dispose();
    _imageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.product != null;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Popup
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? "Chỉnh sửa sản phẩm" : "Thêm sản phẩm",
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              Text(
                "Điền thông tin sản phẩm bên dưới",
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
              const SizedBox(height: 24),

              // Form
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 2,
                    child: _buildTextField("Tên sản phẩm *", _nameController),
                  ),
                  const SizedBox(width: 12),
                  // --- [MỚI] DROPDOWN DANH MỤC ---
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Danh mục *",
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _isLoadingCategories
                            ? const SizedBox(
                                height: 48,
                                child: Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                height: 48,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedCategoryId,
                                    isExpanded: true,
                                    hint: const Text("Chọn danh mục"),
                                    items: _categoryOptions.map((opt) {
                                      return DropdownMenuItem<String>(
                                        value: opt.id,
                                        child: Text(
                                          opt.label,
                                          style: const TextStyle(fontSize: 14),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (String? newValue) {
                                      setState(() {
                                        _selectedCategoryId = newValue;
                                      });
                                    },
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      "Giá (đ) *",
                      _priceController,
                      isNumber: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: _buildTextField("Đơn vị *", _unitController)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      "Tồn kho *",
                      _stockController,
                      isNumber: true,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildTextField("Mô tả", _descController, maxLines: 2),
              const SizedBox(height: 16),
              _buildTextField("URL hình ảnh", _imageController),

              const SizedBox(height: 24),

              // Button Action
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    // Validate sơ bộ
                    if (_nameController.text.isEmpty ||
                        _priceController.text.isEmpty ||
                        _selectedCategoryId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Vui lòng nhập tên, giá và chọn danh mục",
                          ),
                        ),
                      );
                      return;
                    }

                    // Đóng gói data trả về
                    final resultData = {
                      'name': _nameController.text,
                      'category_id': _selectedCategoryId, // Gửi ID danh mục
                      'price': double.tryParse(_priceController.text) ?? 0,
                      'unit': _unitController.text,
                      'stock': int.tryParse(_stockController.text) ?? 0,
                      'description': _descController.text,
                      'image_url': _imageController.text,
                    };

                    // Trả data về màn hình trước để gọi API
                    Navigator.pop(context, resultData);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF06F23),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    isEditing ? "Cập nhật" : "Tạo mới",
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(
                color: Color(0xFFF06F23),
                width: 1.5,
              ),
            ),
            filled: true,
            fillColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
