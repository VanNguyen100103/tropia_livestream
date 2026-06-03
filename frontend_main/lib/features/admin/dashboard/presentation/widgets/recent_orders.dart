import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/order_model.dart'; // Import Model

class RecentOrders extends StatelessWidget {
  final List<OrderModel> orders; // [MỚI] Nhận dữ liệu từ ngoài

  const RecentOrders({super.key, required this.orders});

  // Helper function: Chọn màu theo trạng thái
  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
        return Colors.green;
      case 'processing':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Helper function: Dịch trạng thái sang tiếng Việt
  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'completed': return "Hoàn thành";
      case 'processing': return "Đang xử lý";
      case 'pending': return "Chờ xử lý";
      case 'cancelled': return "Đã hủy";
      default: return status;
    }
  }
  
  // Helper function: Format tiền
  String _formatCurrency(double amount) {
    final formatter = NumberFormat("#,###", "vi_VN");
    return "${formatter.format(amount)}đ";
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "Đơn hàng gần đây",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        
        if (orders.isEmpty)
          const Center(child: Text("Chưa có đơn hàng nào", style: TextStyle(color: Colors.grey)))
        else
          ...orders.map((order) => _buildOrderItem(order)),
      ],
    );
  }

  Widget _buildOrderItem(OrderModel order) {
    final statusColor = _getStatusColor(order.status);
    final statusText = _getStatusText(order.status);
    final price = _formatCurrency(order.totalAmount);
    // Nếu địa chỉ rỗng thì hiển thị ngày tạo
    final subText = order.address.isNotEmpty ? order.address : "Ngày tạo: ${order.createdAt}";

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Colors.grey[100],
            child: const Icon(Icons.shopping_bag_outlined, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "#${order.id} - ${order.customerName}",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                price,
                style: TextStyle(
                  color: Colors.orange[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}