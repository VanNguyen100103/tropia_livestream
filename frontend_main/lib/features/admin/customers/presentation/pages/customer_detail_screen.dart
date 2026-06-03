import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/admin/customers/data/models/customer_model.dart';
import 'package:tropia_mobile_app_android/features/admin/customers/data/repositories/customer_repository.dart';

class CustomerDetailScreen extends StatefulWidget {
  final CustomerModel customer;

  const CustomerDetailScreen({super.key, required this.customer});

  @override
  State<CustomerDetailScreen> createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> {
  bool _isUpdating = false;
  late String _currentStatus;

  // Map hiển thị trạng thái
  final Map<String, String> _statusMap = {
    'active': 'Hoạt động',
    'banned': 'Đã khóa (Banned)',
  };

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.customer.status;
  }

  Future<void> _updateStatus(String? newStatus) async {
    if (newStatus == null || newStatus == _currentStatus) return;

    setState(() => _isUpdating = true);

    final dio = DioClient().dio;
    final repo = CustomerRepository(client: dio);

    final success = await repo.updateCustomerStatus(widget.customer.id, newStatus);

    if (mounted) {
      setState(() => _isUpdating = false);
      if (success) {
        setState(() => _currentStatus = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cập nhật trạng thái thành công!"), backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Lỗi cập nhật trạng thái."), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        title: const Text("Chi tiết khách hàng"),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Avatar & Tên
            Center(
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.orange.withValues(alpha: 0.2),
                    child: Text(
                      widget.customer.name.isNotEmpty ? widget.customer.name[0].toUpperCase() : "K",
                      style: const TextStyle(fontSize: 30, color: Colors.orange, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.customer.name,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "#${widget.customer.id}",
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 30),

            // Card Thông tin
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
              ),
              child: Column(
                children: [
                  _buildInfoRow(Icons.email_outlined, "Email", widget.customer.email.isEmpty ? "Chưa cập nhật" : widget.customer.email),
                  const Divider(height: 24),
                  _buildInfoRow(Icons.location_on_outlined, "Khu vực", widget.customer.area),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Card Trạng thái (Dropdown)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Trạng thái tài khoản", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: _currentStatus == 'active' ? Colors.green.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _currentStatus == 'active' ? Colors.green : Colors.red,
                        width: 1
                      ),
                    ),
                    child: _isUpdating
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _statusMap.containsKey(_currentStatus) ? _currentStatus : null,
                              isExpanded: true,
                              icon: Icon(Icons.arrow_drop_down, color: _currentStatus == 'active' ? Colors.green : Colors.red),
                              items: _statusMap.entries.map((entry) {
                                return DropdownMenuItem<String>(
                                  value: entry.key,
                                  child: Text(
                                    entry.value,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: entry.key == 'active' ? Colors.green : Colors.red,
                                    ),
                                  ),
                                );
                              }).toList(),
                              onChanged: _updateStatus,
                            ),
                          ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Lưu ý: Tài khoản bị khóa sẽ không thể đăng nhập hoặc đặt hàng.",
                    style: TextStyle(color: Colors.grey[500], fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey, size: 20),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15)),
          ],
        )
      ],
    );
  }
}