import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/promotions/data/models/promotion_model.dart';
import 'package:tropia_mobile_app_android/features/admin/promotions/data/repositories/promotion_repository.dart';

class PromotionFormDialog extends StatefulWidget {
  final PromotionModel? promotion; // Nhận Model thay vì Map

  const PromotionFormDialog({super.key, this.promotion});

  @override
  State<PromotionFormDialog> createState() => _PromotionFormDialogState();
}

class _PromotionFormDialogState extends State<PromotionFormDialog> {
// Thêm FormKey để validate
  
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _valueController = TextEditingController();
  final _minOrderController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();

  String _discountType = 'fixed_amount'; // API dùng 'fixed_amount', UI cũ là 'amount'
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.promotion != null) {
      final p = widget.promotion!;
      _titleController.text = p.title;
      _descController.text = p.description;
      _valueController.text = p.discountValue.toStringAsFixed(0);
      _minOrderController.text = p.minOrderValue.toStringAsFixed(0);
      _startDateController.text = p.startDate;
      _endDateController.text = p.endDate;
      // Logic đoán loại giảm giá (tạm thời để fixed_amount vì Model chưa có field này)
      _discountType = 'fixed_amount'; 
    }
  }

  Future<void> _submit() async {
    // Validate cơ bản
    if (_titleController.text.isEmpty || _valueController.text.isEmpty || _startDateController.text.isEmpty) {
        // Show error...
        return;
    }

    setState(() => _isSaving = true);

    final dio = DioClient().dio;
    final repo = PromotionRepository(client: dio);

    // Chuẩn bị data gửi API
    // Lưu ý: Cần convert ngày từ dd/MM/yyyy (UI) sang yyyy-MM-dd (API) nếu cần
    // Ở đây giả sử UI đang nhập/chọn đúng format hoặc server chấp nhận yyyy-MM-dd
    
    final data = {
      "title": _titleController.text,
      "description": _descController.text,
      "discount_type": _discountType, // 'fixed_amount' hoặc 'percentage'
      "discount_value": double.tryParse(_valueController.text) ?? 0,
      "min_order_value": double.tryParse(_minOrderController.text) ?? 0,
      "start_date": _convertDate(_startDateController.text),
      "end_date": _convertDate(_endDateController.text),
    };

    bool success = false;
    if (widget.promotion == null) {
       // Tạo mới
       success = await repo.createPromotion(data);
    } else {
       // Cập nhật (Nếu API hỗ trợ update, hiện tại repo chưa có hàm update full info, chỉ có update status)
       // success = await repo.updatePromotion(widget.promotion!.id, data);
       // Tạm thời chỉ hỗ trợ tạo mới như yêu cầu
       success = false; 
    }

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        Navigator.pop(context, true); // Trả về true để báo thành công
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Thành công!"), backgroundColor: Colors.green));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Thất bại, vui lòng kiểm tra lại"), backgroundColor: Colors.red));
      }
    }
  }

  // Hàm helper convert ngày từ dd/MM/yyyy -> yyyy-MM-dd
  String _convertDate(String dateStr) {
    try {
      if (dateStr.contains('/')) {
        final parts = dateStr.split('/');
        if (parts.length == 3) {
          return "${parts[2]}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}";
        }
      }
      return dateStr; // Trả về nguyên gốc nếu đã đúng format
    } catch (e) {
      return dateStr;
    }
  }

  // Hàm chọn ngày (Giữ nguyên logic của bạn)
  Future<void> _selectDate(BuildContext context, TextEditingController controller) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFFF06F23)),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        // Hiển thị format dd/MM/yyyy cho người dùng dễ nhìn
        controller.text = "${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.promotion != null;

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
              // Header (Giữ nguyên)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing ? "Chỉnh sửa khuyến mãi" : "Tạo khuyến mãi mới",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.grey),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              Text("Điền thông tin khuyến mãi", style: TextStyle(color: Colors.grey[600], fontSize: 13)),
              const SizedBox(height: 24),

              // Form Fields (Giữ nguyên UI)
              _buildTextField("Tiêu đề *", _titleController),
              const SizedBox(height: 16),
              _buildTextField("Mô tả *", _descController),
              const SizedBox(height: 16),

              // Dropdown
              const Text("Loại giảm giá *", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _discountType,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'fixed_amount', child: Text("Số tiền cố định (đ)")), // Value khớp API
                      // DropdownMenuItem(value: 'percentage', child: Text("Phần trăm (%)")), // Tạm ẩn nếu API chưa hỗ trợ
                    ],
                    onChanged: (val) => setState(() => _discountType = val!),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              _buildTextField("Giá trị giảm *", _valueController, isNumber: true),
              const SizedBox(height: 16),
              _buildTextField("Đơn hàng tối thiểu (đ) *", _minOrderController, isNumber: true),
              const SizedBox(height: 16),

              _buildDatePicker("Ngày bắt đầu *", _startDateController),
              const SizedBox(height: 16),
              _buildDatePicker("Ngày kết thúc *", _endDateController),
              
              const SizedBox(height: 24),

              // Nút Submit
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _submit, // Gọi hàm submit
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF06F23),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: _isSaving 
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(
                        isEditing ? "Cập nhật" : "Tạo khuyến mãi",
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Widget helper _buildTextField và _buildDatePicker (Giữ nguyên của bạn)
  Widget _buildTextField(String label, TextEditingController controller, {bool isNumber = false, String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: isNumber ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF06F23), width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _buildDatePicker(String label, TextEditingController controller) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: true,
          onTap: () => _selectDate(context, controller),
          decoration: InputDecoration(
            hintText: "dd/mm/yyyy",
            suffixIcon: const Icon(Icons.calendar_today_outlined, size: 20, color: Colors.black54),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF06F23), width: 1.5)),
          ),
        ),
      ],
    );
  }
}