import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/orders/data/models/order_detail_model.dart';
import 'package:tropia_mobile_app_android/features/admin/orders/data/repositories/order_repository.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  bool _isLoading = true;
  bool _isUpdating = false; // Trạng thái khi đang bấm cập nhật
  OrderDetailModel? _orderDetail;

  // Danh sách trạng thái có thể chọn
  final Map<String, String> _statusMap = {
    'pending': 'Chờ xử lý',
    'processing': 'Đang xử lý',
    'completed': 'Hoàn thành',
    'cancelled': 'Đã hủy',
  };

  @override
  void initState() {
    super.initState();
    _fetchDetail();
  }

  Future<void> _fetchDetail() async {
    setState(() => _isLoading = true);
    final dio = DioClient().dio;
    final repo = OrderRepository(client: dio);

    final data = await repo.getOrderDetail(widget.orderId);

    if (mounted) {
      setState(() {
        _orderDetail = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStatus(String? newStatus) async {
    if (newStatus == null || newStatus == _orderDetail?.status) return;

    setState(() => _isUpdating = true);

    final dio = DioClient().dio;
    final repo = OrderRepository(client: dio);

    final success = await repo.updateOrderStatus(widget.orderId, newStatus);

    if (mounted) {
      setState(() => _isUpdating = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cập nhật trạng thái thành công!"),
            backgroundColor: Colors.green,
          ),
        );
        _fetchDetail(); // Load lại dữ liệu mới
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cập nhật thất bại, vui lòng thử lại."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatCurrency(double amount) {
    final formatter = NumberFormat("#,###", "vi_VN");
    return "${formatter.format(amount)}đ";
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text("Chi tiết đơn hàng"),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orderDetail == null
          ? const Center(child: Text("Không tìm thấy thông tin đơn hàng"))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. HEADER: ID & TRẠNG THÁI (Dropdown)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "#${_orderDetail!.id}",
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              _orderDetail!.createdAt,
                              style: TextStyle(
                                color: Colors.grey[500],
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          "Cập nhật trạng thái:",
                          style: TextStyle(color: Colors.grey),
                        ),
                        const SizedBox(height: 8),

                        // STATUS DROPDOWN
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: _getStatusColor(
                              _orderDetail!.status,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _getStatusColor(
                                _orderDetail!.status,
                              ).withValues(alpha: 0.3),
                            ),
                          ),
                          child: _isUpdating
                              ? const Padding(
                                  padding: EdgeInsets.all(12.0),
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
                              : DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value:
                                        _statusMap.containsKey(
                                          _orderDetail!.status,
                                        )
                                        ? _orderDetail!.status
                                        : null,
                                    isExpanded: true,
                                    icon: Icon(
                                      Icons.arrow_drop_down,
                                      color: _getStatusColor(
                                        _orderDetail!.status,
                                      ),
                                    ),
                                    items: _statusMap.entries.map((entry) {
                                      return DropdownMenuItem<String>(
                                        value: entry.key,
                                        child: Text(
                                          entry.value,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color:
                                                entry.key ==
                                                    _orderDetail!.status
                                                ? _getStatusColor(
                                                    _orderDetail!.status,
                                                  )
                                                : Colors.black87,
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: _updateStatus,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 2. THÔNG TIN KHÁCH HÀNG
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Thông tin giao hàng",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          Icons.person,
                          "Người nhận",
                          _orderDetail!.customerName,
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          Icons.location_on,
                          "Địa chỉ",
                          _orderDetail!.address.isEmpty
                              ? "Chưa cập nhật"
                              : _orderDetail!.address,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // 3. DANH SÁCH SẢN PHẨM
                  const Text(
                    "Danh sách sản phẩm",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _orderDetail!.products.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final product = _orderDetail!.products[index];
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Ảnh sản phẩm (Placeholder)
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(
                                Icons.image,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    product.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    "${_formatCurrency(product.price)} x ${product.quantity}",
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              _formatCurrency(product.total),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 20),

                  // 4. TỔNG TIỀN
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "Tổng thanh toán",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          _formatCurrency(_orderDetail!.totalAmount),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ],
    );
  }
}
