import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';

class CartPaymentSection extends StatelessWidget {
  // Nhận dữ liệu từ CartPage truyền xuống
  final String currentPaymentMethod; // "cod" hoặc "bank_transfer"
  final Function(String) onPaymentChanged;

  const CartPaymentSection({
    super.key,
    required this.currentPaymentMethod,
    required this.onPaymentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("Hình thức thanh toán", style: TextStyle(fontSize: 15)),
              // Text("Đổi >", style: TextStyle(color: Colors.blue)),
            ],
          ),
          const SizedBox(height: 10),

          // Option 1: Chuyển khoản -> API value: "bank_transfer"
          _buildSelectableOption(
            value: "bank_transfer",
            title: "Chuyển khoản",
            badge: "x2 điểm VIP",
          ),

          const SizedBox(height: 10),

          // Option 2: Tiền mặt -> API value: "cod"
          _buildSelectableOption(
            value: "cod",
            title: "Tiền mặt khi nhận hàng",
          ),
        ],
      ),
    );
  }

  Widget _buildSelectableOption({
    required String value, 
    required String title, 
    String? badge
  }) {
    // So sánh chuỗi để biết cái nào đang được chọn
    bool isSelected = currentPaymentMethod == value;

    return GestureDetector(
      onTap: () {
        // Gọi callback để CartPage cập nhật state
        onPaymentChanged(value);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          // Viền: Chọn thì màu Cam, không thì Xám
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
          // Nền: Chọn thì Cam nhạt, không thì Trắng
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.05)
              : Colors.white,
        ),
        child: Row(
          children: [
            // Icon: Chọn thì Checked, không thì Off
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppColors.primary : Colors.grey,
            ),
            const SizedBox(width: 10),

            Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),

            if (badge != null) ...[
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(fontSize: 10, color: Colors.green),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}