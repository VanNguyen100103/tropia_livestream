import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/products/data/models/product_model.dart';
import 'package:tropia_mobile_app_android/features/admin/products/data/repositories/product_repository.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/category_model.dart';

class _CategoryOption {
  final String id;
  final String label;

  const _CategoryOption({required this.id, required this.label});
}

class ProductEditScreen extends StatefulWidget {
  // [SỬA] Cho phép product là null để dùng cho chế độ Tạo Mới
  final ProductModel? product;

  const ProductEditScreen({super.key, this.product});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  late TextEditingController _nameCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _unitCtrl;
  late TextEditingController _descCtrl; // [MỚI] Mô tả
  late TextEditingController _imageCtrl;

  List<_CategoryOption> _categoryOptions = [];
  String? _selectedCategoryId;
  bool _isLoadingCategories = true;

  bool _isSaving = false;

  // Getter kiểm tra xem đang ở chế độ nào
  bool get _isEditing => widget.product != null;

  @override
  void initState() {
    super.initState();
    // Nếu là Edit thì lấy dữ liệu cũ, nếu Create thì để rỗng
    _nameCtrl = TextEditingController(text: widget.product?.name ?? "");
    _selectedCategoryId = widget.product?.categoryId.isNotEmpty == true
        ? widget.product!.categoryId
        : null;
    _priceCtrl = TextEditingController(
      text: widget.product?.price.toStringAsFixed(0) ?? "",
    );
    _stockCtrl = TextEditingController(
      text: widget.product?.stock.toString() ?? "",
    );
    _unitCtrl = TextEditingController(text: widget.product?.unit ?? "");
    _descCtrl = TextEditingController(text: widget.product?.description ?? "");

    String currentImage = widget.product?.image ?? "";
    if (currentImage == "0" || currentImage == "null") currentImage = "";
    _imageCtrl = TextEditingController(text: currentImage);

    _loadCategories();
  }

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

  Future<void> _loadCategories() async {
    try {
      final dio = DioClient().dio;
      final repo = ProductRepository(client: dio);
      final tree = await repo.getCategories();

      if (!mounted) return;
      setState(() {
        _categoryOptions = _flattenCategories(tree);
        _isLoadingCategories = false;

        if (_categoryOptions.isEmpty) {
          _selectedCategoryId = null;
          return;
        }

        final exists = _categoryOptions.any((o) => o.id == _selectedCategoryId);
        if (!exists) {
          _selectedCategoryId = _categoryOptions.first.id;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingCategories = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedCategoryId == null || _selectedCategoryId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vui lòng chọn danh mục"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final dio = DioClient().dio;
    final repo = ProductRepository(client: dio);

    // Chuẩn bị dữ liệu (Dùng chung cho cả Create và Update)
    final dataPayload = {
      "name": _nameCtrl.text,
      "category_id": _selectedCategoryId,
      "price": double.tryParse(_priceCtrl.text) ?? 0,
      "stock": int.tryParse(_stockCtrl.text) ?? 0,
      "unit": _unitCtrl.text,
      "description": _descCtrl.text,
      "image_url": _imageCtrl.text,
      "status": "active",
    };

    bool success;
    if (_isEditing) {
      // Gọi API Update
      success = await repo.updateProduct(widget.product!.id, dataPayload);
    } else {
      // Gọi API Create [MỚI]
      success = await repo.createProduct(dataPayload);
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isEditing ? "Cập nhật thành công!" : "Tạo mới thành công!",
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context); // Quay về danh sách
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEditing ? "Lỗi cập nhật" : "Lỗi tạo mới"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _unitCtrl.dispose();
    _descCtrl.dispose();
    _imageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? "Sửa sản phẩm" : "Thêm sản phẩm mới",
        ), // [SỬA] Tiêu đề động
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFFF7F8FA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildImagePreview(),
              const SizedBox(height: 20),

              _buildTextField(
                "Link ảnh (URL)",
                _imageCtrl,
                hintText: "https://example.com/image.png",
                onChanged: (val) => setState(() {}),
              ),
              const SizedBox(height: 16),

              _buildTextField("Tên sản phẩm", _nameCtrl),
              const SizedBox(height: 16),

              // [MỚI] Trường Danh mục
              _buildCategoryDropdown(),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      "Giá bán",
                      _priceCtrl,
                      isNumber: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      "Đơn vị",
                      _unitCtrl,
                      hintText: "kg, hộp...",
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildTextField("Tồn kho", _stockCtrl, isNumber: true),
              const SizedBox(height: 16),

              // [MỚI] Trường Mô tả (Multiline)
              _buildTextField("Mô tả", _descCtrl, isMultiline: true),

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          _isEditing ? "Lưu thay đổi" : "Tạo sản phẩm",
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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

  Widget _buildCategoryDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Danh mục", style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        _isLoadingCategories
            ? const SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator()),
              )
            : DropdownButtonFormField<String>(
                initialValue: _selectedCategoryId,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
                items: _categoryOptions
                    .map(
                      (opt) => DropdownMenuItem<String>(
                        value: opt.id,
                        child: Text(opt.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  setState(() => _selectedCategoryId = v);
                },
              ),
      ],
    );
  }

  Widget _buildImagePreview() {
    return Center(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: _imageCtrl.text.isNotEmpty
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  _imageCtrl.text,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.broken_image, color: Colors.grey),
                      Text("Lỗi ảnh", style: TextStyle(fontSize: 10)),
                    ],
                  ),
                ),
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_photo_alternate, size: 40, color: Colors.grey),
                  Text(
                    "Thêm ảnh",
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    bool isNumber = false,
    String? hintText,
    Function(String)? onChanged,
    bool isMultiline = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: isNumber
              ? TextInputType.number
              : (isMultiline ? TextInputType.multiline : TextInputType.text),
          maxLines: isMultiline
              ? 3
              : 1, // [MỚI] Cho phép nhập nhiều dòng cho mô tả
          onChanged: onChanged,
          validator: (value) {
            if (label.contains("Link") || label.contains("Mô tả")) {
              return null; // Không bắt buộc
            }
            return value == null || value.isEmpty
                ? "Vui lòng nhập thông tin"
                : null;
          },
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(color: Colors.grey[400]),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
          ),
        ),
      ],
    );
  }
}
