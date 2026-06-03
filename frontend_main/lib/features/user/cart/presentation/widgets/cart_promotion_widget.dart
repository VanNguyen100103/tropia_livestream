import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/voucher_model.dart';

class CartPromotionWidget extends StatelessWidget {
  final double subtotal;
  final TextEditingController voucherController;
  final List<VoucherModel> savedVouchers;
  final String? selectedVoucherCode;
  final void Function(VoucherModel) onApplyVoucher;
  final VoidCallback onClearVoucher;
  final Future<void> Function(String code)? onSaveCode;

  const CartPromotionWidget({
    super.key,
    required this.subtotal,
    required this.voucherController,
    required this.savedVouchers,
    required this.selectedVoucherCode,
    required this.onApplyVoucher,
    required this.onClearVoucher,
    this.onSaveCode,
  });

  @override
  Widget build(BuildContext context) {
    // Màu chủ đạo dựa trên hình ảnh bạn gửi
    const Color primaryBlack = Color(0xFF1F1F1F); // Đen nhám nhẹ cho sang
    const Color bgGrey = Color(0xFFF5F5F5);
    const Color textGrey = Colors.grey;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8), // Margin để tách biệt các khối
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        // Loại bỏ shadow đậm, chỉ để border nhẹ hoặc shadow rất mờ nếu cần
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Header ---
          const Row(
            children: [
              Icon(Icons.discount_outlined, color: primaryBlack, size: 20),
              SizedBox(width: 8),
              Text(
                'Mã ưu đãi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: primaryBlack),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // --- Input Nhập mã ---
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46, // Chiều cao vừa phải
                  child: TextField(
                    controller: voucherController,
                    cursorColor: primaryBlack,
                    style: const TextStyle(fontSize: 14),
                    textInputAction: TextInputAction.done,
                    onEditingComplete: () => FocusScope.of(context).unfocus(),
                    onTapOutside: (_) => FocusScope.of(context).unfocus(),
                    decoration: InputDecoration(
                      hintText: 'Nhập mã voucher',
                      hintStyle: const TextStyle(color: Colors.grey, fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                      filled: true,
                      fillColor: bgGrey, // Nền xám nhạt cho input
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none, // Bỏ viền mặc định cho sạch
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: primaryBlack, width: 1),
                      ),
                      suffixIcon: selectedVoucherCode != null
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
                              onPressed: () {
                                voucherController.clear();
                                onClearVoucher();
                              },
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                height: 46,
                child: ElevatedButton(
                  onPressed: () async {
                    final code = voucherController.text.trim();
                    if (code.isEmpty) return;
                    final matches = savedVouchers.where((v) => v.code == code);
                    if (matches.isEmpty) {
                      if (onSaveCode != null) {
                        await onSaveCode!(code);
                        return;
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Mã không hợp lệ'),
                          backgroundColor: primaryBlack,
                        ));
                        return;
                      }
                    }
                    onApplyVoucher(matches.first);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryBlack, // Nền đen
                    foregroundColor: Colors.white, // Chữ trắng
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  child: const Text('Áp dụng', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          
          if (savedVouchers.isNotEmpty) ...[
            const Text('Voucher của bạn', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: primaryBlack)),
            const SizedBox(height: 12),
          ],

          // --- Danh sách Voucher ---
          savedVouchers.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: Text('Chưa có mã giảm giá nào.', style: TextStyle(color: Colors.grey[400], fontSize: 13))),
                )
              : Column(
                  children: savedVouchers.map((v) {
                    final isSelected = v.code == selectedVoucherCode;
                    final canUse = subtotal >= v.minOrderValue;
                    
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          // Nếu được chọn: Viền đen. Không được chọn: Viền xám nhạt
                          color: isSelected ? primaryBlack : Colors.grey.shade200, 
                          width: isSelected ? 1.5 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: canUse ? () => onApplyVoucher(v) : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              // Icon Ticket
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: canUse ? Colors.black.withValues(alpha: 0.05) : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.confirmation_number_outlined, // Icon vé
                                  color: canUse ? primaryBlack : Colors.grey,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              
                              // Nội dung
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.title.isNotEmpty ? v.title : v.code,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: canUse ? primaryBlack : textGrey,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      v.description.isNotEmpty ? v.description : 'Đơn tối thiểu ${v.minOrderValue}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: canUse ? Colors.grey[600] : Colors.grey[400],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              // Radio Button giả lập
                              if (canUse)
                                Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? primaryBlack : Colors.grey.shade400,
                                      width: isSelected ? 5 : 1, // Nếu chọn thì viền dày lên tạo hiệu ứng dot
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }
}