import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../../core/constants/app_colors.dart';

class CartBottomBar extends StatelessWidget {
  final double totalPrice;
  final VoidCallback onOrderPressed;
  final int totalItems; // [MỚI] Thêm tham số tổng số lượng món
  final int? earnedPointsPreview;
  final bool isPointsPreviewLoading;

  const CartBottomBar({
    super.key,
    required this.totalPrice,
    required this.onOrderPressed,
    this.totalItems = 0, // Mặc định là 0 nếu không truyền
    this.earnedPointsPreview,
    this.isPointsPreviewLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    // Helper format tiền tệ chuẩn quốc tế (để dấu chấm ngăn cách hàng nghìn)
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isPointsPreviewLoading || earnedPointsPreview != null)
            _buildPointsPreviewBadge(currencyFormat),
          if (isPointsPreviewLoading || earnedPointsPreview != null)
            const SizedBox(height: 10),
          // Nút đặt hàng
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: onOrderPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Hiển thị số lượng món (Badge tròn)
                  if (totalItems > 0) ...[
                    CircleAvatar(
                      backgroundColor: Colors.white,
                      radius: 12,
                      child: Text(
                        "$totalItems",
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],

                  const Icon(Icons.shopping_cart, color: Colors.white),
                  const SizedBox(width: 8),

                  // Hiển thị tổng tiền
                  Text(
                    "Đặt hàng ${currencyFormat.format(totalPrice)}",
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointsPreviewBadge(NumberFormat currencyFormat) {
    final previewPoints = earnedPointsPreview ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7DD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE6A7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.monetization_on, color: Color(0xFFD4A106), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: isPointsPreviewLoading
                ? const Text(
                    'Đang tính điểm thưởng...',
                    style: TextStyle(fontSize: 12, color: Color(0xFF7A5B00)),
                  )
                : Text(
                    'Dự kiến cộng ${NumberFormat.decimalPattern('vi_VN').format(previewPoints)} điểm cho đơn hàng này',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF7A5B00),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
