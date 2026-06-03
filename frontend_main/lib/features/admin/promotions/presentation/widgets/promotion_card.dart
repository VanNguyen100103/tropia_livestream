import 'package:flutter/material.dart';

class PromotionCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle; // Nút Tạm dừng/Kích hoạt

  const PromotionCard({
    super.key,
    required this.data,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final bool isActive = data['status'] == 'active';
    final colorStatus = isActive ? const Color(0xFF00C853) : Colors.grey;
    final textStatus = isActive ? "Đang hoạt động" : "Tạm dừng";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header: Tiêu đề + Badge Trạng thái
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data['title'], // "TRÚNG 32 CHỈ VÀNG"
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data['description'], // "khi mua Blanc"
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorStatus,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  textStatus,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            ],
          ),
          const SizedBox(height: 16),

          // 2. Thông tin chi tiết (Giảm, Đơn tối thiểu, Ngày)
          _buildInfoRow("Giảm:", data['discountValue'], isHighlight: true),
          const SizedBox(height: 8),
          _buildInfoRow("Đơn tối thiểu:", data['minOrder']),
          const SizedBox(height: 8),
          Text(
            "${data['startDate']} - ${data['endDate']}",
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
          
          const SizedBox(height: 16),

          // 3. Hàng nút thao tác (Sửa | Tạm dừng | Xóa)
          Row(
            children: [
              // Nút Sửa
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.black87),
                  label: const Text("Sửa", style: TextStyle(color: Colors.black87, fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              
              // Nút Tạm dừng
              Expanded(
                child: OutlinedButton(
                  onPressed: onToggle,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12), // Height khớp với nút icon
                    side: BorderSide(color: Colors.grey.shade300),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text(
                    isActive ? "Tạm dừng" : "Kích hoạt",
                    style: const TextStyle(color: Colors.black87, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Nút Xóa (Icon thùng rác đỏ)
              InkWell(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF44336), // Màu đỏ
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.delete_outline, color: Colors.white, size: 20),
                ),
              ),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isHighlight = false}) {
    return Row(
      children: [
        Text("$label ", style: const TextStyle(fontSize: 14, color: Colors.black87)),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isHighlight ? FontWeight.bold : FontWeight.normal,
            color: isHighlight ? const Color(0xFFF06F23) : Colors.black87,
          ),
        ),
      ],
    );
  }
}