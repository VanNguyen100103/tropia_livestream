import 'package:flutter/material.dart';
// Thay đổi đường dẫn import bên dưới cho đúng với cấu trúc thư mục của bạn
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/products/data/repositories/product_repository.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/category_model.dart';

class CategoryManagementDialog extends StatefulWidget {
  const CategoryManagementDialog({super.key});

  @override
  State<CategoryManagementDialog> createState() =>
      _CategoryManagementDialogState();
}

class _CategoryManagementDialogState extends State<CategoryManagementDialog> {
  List<CategoryModel> _categories = [];
  bool _isLoading = true;

  List<CategoryModel> _extractChildModels(CategoryModel category) {
    final children = category.children;
    return children.cast<dynamic>().whereType<CategoryModel>().toList();
  }

  List<CategoryModel> _level1Categories() => _categories;

  List<CategoryModel> _level2Categories() {
    return _categories.expand(_extractChildModels).toList();
  }

  bool _hasChildren(CategoryModel category) {
    final children = category.children;
    return children.isNotEmpty;
  }

  Widget _buildLeading(CategoryModel category, {required int level}) {
    final iconUrl = category.icon;
    final hasIcon = iconUrl.isNotEmpty && iconUrl.startsWith('http');

    if (level == 0) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: hasIcon
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  iconUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) {
                    return const Icon(Icons.category, color: Colors.orange);
                  },
                ),
              )
            : const Icon(Icons.category, color: Colors.orange),
      );
    }

    return Icon(
      _hasChildren(category)
          ? Icons.folder_outlined
          : Icons.subdirectory_arrow_right,
      color: Colors.grey[700],
      size: 20,
    );
  }

  Widget _buildCategoryNode(CategoryModel category, {required int level}) {
    final leftPad = 16.0 * level;
    final children = category.children;
    final childModels = children
        .cast<dynamic>()
        .whereType<CategoryModel>()
        .toList();
    final hasChildren = childModels.isNotEmpty;

    final title = Text(
      category.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: level == 0 ? FontWeight.w600 : FontWeight.w500,
        fontSize: level == 0 ? 14 : 13,
      ),
    );

    final subtitle = Text(
      hasChildren ? "${childModels.length} mục con" : "ID: ${category.id}",
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12),
    );

    if (!hasChildren) {
      return ListTile(
        dense: level > 0,
        contentPadding: EdgeInsets.only(left: 16 + leftPad, right: 8),
        leading: _buildLeading(category, level: level),
        title: title,
        subtitle: subtitle,
      );
    }

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.only(left: 16 + leftPad, right: 8),
        childrenPadding: EdgeInsets.zero,
        leading: _buildLeading(category, level: level),
        title: title,
        subtitle: subtitle,
        children: childModels
            .map((child) => _buildCategoryNode(child, level: level + 1))
            .toList(),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    final dio = DioClient().dio;
    final repo = ProductRepository(client: dio);
    final data = await repo.getCategories();

    final unique = <CategoryModel>[];
    final seen = <String>{};
    for (var item in data) {
      if (!seen.contains(item.id)) {
        unique.add(item);
        seen.add(item.id);
      }
    }

    if (mounted) {
      setState(() {
        _categories = unique;
        _isLoading = false;
      });
    }
  }

  void _showAddDialog() {
    final nameController = TextEditingController();
    final iconController = TextEditingController();
    final sortOrderController = TextEditingController(text: '1');

    int selectedLevel = 1;
    String? selectedParentId;
    bool isActive = true;
    bool isStatus = true;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Thêm danh mục mới"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StatefulBuilder(
                builder: (context, setInnerState) {
                  final level1 = _level1Categories();
                  final level2 = _level2Categories();
                  final parentOptions = selectedLevel == 2
                      ? level1
                      : (selectedLevel == 3 ? level2 : const <CategoryModel>[]);

                  if (selectedLevel == 1) {
                    selectedParentId = null;
                  } else {
                    final stillValid = parentOptions.any(
                      (e) => e.id == selectedParentId,
                    );
                    if (!stillValid) selectedParentId = null;
                  }

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: selectedLevel,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: "Tầng danh mục",
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text("Tầng 1")),
                          DropdownMenuItem(value: 2, child: Text("Tầng 2")),
                          DropdownMenuItem(value: 3, child: Text("Tầng 3")),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setInnerState(() {
                            selectedLevel = value;
                            selectedParentId = null;
                          });
                        },
                      ),
                      if (selectedLevel > 1) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedParentId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: selectedLevel == 2
                                ? "Danh mục cha (Tầng 1)"
                                : "Danh mục cha (Tầng 2)",
                            border: const OutlineInputBorder(),
                          ),
                          items: parentOptions
                              .map(
                                (c) => DropdownMenuItem<String>(
                                  value: c.id,
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: Text(
                                      "${c.name} (ID: ${c.id})",
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setInnerState(() {
                              selectedParentId = value;
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 12),
                      TextField(
                        controller: sortOrderController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: "Thứ tự hiển thị (sort_order)",
                          hintText: "1",
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.format_list_numbered),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Status"),
                                Switch.adaptive(
                                  value: isStatus,
                                  onChanged: (v) {
                                    setInnerState(() => isStatus = v);
                                  },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text("Active"),
                                Switch.adaptive(
                                  value: isActive,
                                  onChanged: (v) {
                                    setInnerState(() => isActive = v);
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: "Tên danh mục",
                  hintText: "Ví dụ: Hải sản...",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.category_outlined),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: iconController,
                decoration: const InputDecoration(
                  labelText: "Link ảnh (Icon URL)",
                  hintText: "https://...",
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Hủy"),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Vui lòng nhập tên danh mục!"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              if (selectedLevel > 1 && (selectedParentId == null)) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Vui lòng chọn danh mục cha (ref_code)!"),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              Navigator.pop(ctx);

              final dio = DioClient().dio;
              final repo = ProductRepository(client: dio);

              if (mounted) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text("Đang tạo...")));
              }

              String iconUrl = iconController.text.trim();
              if (iconUrl.isEmpty) {
                iconUrl =
                    "https://cdn-icons-png.flaticon.com/512/263/263142.png";
              }

              final sortOrder =
                  int.tryParse(sortOrderController.text.trim()) ?? 1;
              final refCode = selectedParentId == null
                  ? null
                  : int.tryParse(selectedParentId!);

              final success = await repo.createCategory(
                name: nameController.text.trim(),
                icon: iconUrl,
                level: selectedLevel,
                refCode: refCode,
                sortOrder: sortOrder,
                status: isStatus ? 1 : 0,
                active: isActive ? 1 : 0,
              );

              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Tạo thành công!"),
                    backgroundColor: Colors.green,
                  ),
                );
                _loadCategories();
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Tạo thất bại"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text("Tạo"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: 500,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Quản lý danh mục",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _categories.isEmpty
                  ? const Center(child: Text("Chưa có danh mục nào"))
                  : ListView.separated(
                      itemCount: _categories.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final cat = _categories[index];
                        return _buildCategoryNode(cat, level: 0);
                      },
                    ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showAddDialog,
                icon: const Icon(Icons.add),
                label: const Text("Thêm danh mục mới"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
