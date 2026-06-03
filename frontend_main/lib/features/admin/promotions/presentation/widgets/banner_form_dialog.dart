import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/promotions/data/repositories/banner_repository.dart';

class BannerFormDialog extends StatefulWidget {
  const BannerFormDialog({super.key});

  @override
  State<BannerFormDialog> createState() => _BannerFormDialogState();
}

class _BannerFormDialogState extends State<BannerFormDialog> {
  final _titleController = TextEditingController();
  final _imgUrlController = TextEditingController();
  final _actionValueController = TextEditingController();

  // Mặc định là 'webview' theo logic API của bạn
  String _actionType = 'webview';
  bool _isSaving = false;

  Future<void> _submit() async {
    // Validate cơ bản
    if (_titleController.text.isEmpty || _imgUrlController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vui lòng nhập tiêu đề và link ảnh"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    final dio = DioClient().dio;
    final repo = BannerRepository(client: dio);

    // Chuẩn bị dữ liệu gửi API
    final data = {
      "title": _titleController.text,
      "image_url": _imgUrlController.text,
      "action_type": _actionType,
      "action_value": _actionValueController.text,
    };

    // Gọi API tạo banner
    final success = await repo.createBanner(data);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(
          context,
          true,
        ); // Trả về true để màn hình danh sách biết đường reload
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Tạo banner thành công!"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Lỗi khi tạo banner, vui lòng thử lại"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Tạo Banner Mới",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const Divider(height: 30),

              // Form Fields
              _buildTextField(
                "Tiêu đề banner *",
                _titleController,
                hint: "Nhập tiêu đề banner",
              ),
              const SizedBox(height: 16),

              _buildTextField(
                "Link ảnh (URL) *",
                _imgUrlController,
                hint: "https://example.com/image.png",
              ),
              const SizedBox(height: 16),

              // Dropdown Action Type
              const Text(
                "Loại hành động",
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _actionType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: 'webview',
                        child: Text("Mở WebView"),
                      ),
                      DropdownMenuItem(
                        value: 'product_detail',
                        child: Text("Chi tiết sản phẩm"),
                      ),
                      DropdownMenuItem(
                        value: 'category',
                        child: Text("Danh mục"),
                      ),
                      DropdownMenuItem(
                        value: 'none',
                        child: Text("Không có hành động"),
                      ),
                    ],
                    onChanged: (val) => setState(() => _actionType = val!),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _buildTextField(
                "Giá trị hành động",
                _actionValueController,
                hint: "Link web hoặc ID sản phẩm...",
              ),
              const SizedBox(height: 24),

              // Submit Button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(
                      0xFFF06F23,
                    ), // Màu cam chủ đạo của App
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          "Tạo Banner Ngay",
                          style: TextStyle(
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

  // Helper tạo TextField cho gọn code
  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
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
          ),
        ),
      ],
    );
  }
}
