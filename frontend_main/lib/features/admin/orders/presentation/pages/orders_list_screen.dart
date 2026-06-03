import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';

// --- IMPORTS ---
import 'package:tropia_mobile_app_android/features/admin/dashboard/data/models/order_model.dart';
import 'package:tropia_mobile_app_android/features/admin/orders/data/repositories/order_repository.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';

// [QUAN TRỌNG] Import màn hình chi tiết (đảm bảo đường dẫn đúng)
import 'package:tropia_mobile_app_android/features/admin/orders/presentation/pages/order_detail_screen.dart';

class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key});

  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  // ... (Code logic initState, fetchOrders, filter... GIỮ NGUYÊN KHÔNG ĐỔI)
  bool _isLoading = true;
  List<OrderModel> _allOrders = [];
  List<OrderModel> _filteredOrders = [];

  final TextEditingController _searchController = TextEditingController();
  int _selectedFilterIndex = 0;
  final List<String> _filters = [
    "Tất cả",
    "Pending",
    "Processing",
    "Completed",
    "Cancelled",
  ];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final dio = DioClient().dio;
    final authRepo = AppAuthRepository(
      remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
    );
    await authRepo.authenticateApp();
    await _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    setState(() => _isLoading = true);
    final dio = DioClient().dio;
    final repo = OrderRepository(client: dio);

    final data = await repo.getAllOrders();

    if (mounted) {
      setState(() {
        _allOrders = data;
        _applyFilters();
        _isLoading = false;
      });
    }
  }

  void _applyFilters() {
    String query = _searchController.text.toLowerCase();
    String selectedStatus = _filters[_selectedFilterIndex].toLowerCase();

    setState(() {
      _filteredOrders = _allOrders.where((order) {
        bool matchesSearch =
            order.id.toLowerCase().contains(query) ||
            order.customerName.toLowerCase().contains(query);

        bool matchesStatus = true;
        if (selectedStatus != "tất cả") {
          matchesStatus = order.status.toLowerCase() == selectedStatus;
        }
        return matchesSearch && matchesStatus;
      }).toList();
    });
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

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return "Chờ xử lý";
      case 'processing':
        return "Đang xử lý";
      case 'completed':
        return "Hoàn thành";
      case 'cancelled':
        return "Đã hủy";
      default:
        return status;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ... (Code build Scaffold, Header GIỮ NGUYÊN KHÔNG ĐỔI)
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _fetchOrders,
              color: Colors.orange,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 100),
                itemCount: _filteredOrders.isEmpty
                    ? 2
                    : _filteredOrders.length + 1,
                separatorBuilder: (context, index) {
                  if (index == 0) return const SizedBox.shrink();
                  return const SizedBox(height: 12);
                },
                itemBuilder: (context, index) {
                  if (index == 0) return _buildHeader(context);

                  if (_filteredOrders.isEmpty) {
                    return Container(
                      height: MediaQuery.of(context).size.height * 0.6,
                      alignment: Alignment.center,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.assignment_outlined,
                            size: 60,
                            color: Colors.grey[300],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            "Không tìm thấy đơn hàng nào",
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                      
                    );
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _buildOrderItem(_filteredOrders[index - 1]),
                  );
                },
                
              ),
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final double topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding + 20, 20, 10),
      color: const Color(0xFFF7F8FA),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => _applyFilters(),
              decoration: const InputDecoration(
                hintText: "Tìm theo Mã đơn, Tên khách...",
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                prefixIcon: Icon(Icons.search, color: Colors.grey),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _filters.asMap().entries.map((entry) {
                int idx = entry.key;
                String text = entry.value;
                bool isSelected = idx == _selectedFilterIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedFilterIndex = idx;
                    });
                    _applyFilters();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.orange : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isSelected
                            ? Colors.transparent
                            : Colors.grey.shade300,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    child: Text(
                      text,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.grey[700],
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  // --- CẬP NHẬT PHẦN NÀY ĐỂ ĐIỀU HƯỚNG ---
  Widget _buildOrderItem(OrderModel order) {
    Color statusColor = _getStatusColor(order.status);
    String statusText = _getStatusText(order.status);

    // Bọc Container bằng GestureDetector để bắt sự kiện Tap
    return GestureDetector(
      onTap: () async {
        // Điều hướng sang màn hình chi tiết
        // Đợi kết quả trả về (await) để biết khi nào user quay lại
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => OrderDetailScreen(orderId: order.id),
          ),
        );

        // Sau khi quay lại từ màn hình chi tiết, reload lại danh sách
        // để cập nhật trạng thái mới (nếu có thay đổi)
        _fetchOrders();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "#${order.id}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.black87,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Divider(height: 1, thickness: 0.5),
            ),
            Row(
              children: [
                Icon(Icons.person_outline, size: 18, color: Colors.grey[400]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    order.customerName,
                    style: TextStyle(
                      color: Colors.grey[800],
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 18,
                  color: Colors.grey[400],
                ),
                const SizedBox(width: 8),
                Text(
                  order.createdAt,
                  style: TextStyle(color: Colors.grey[500], fontSize: 13),
                ),
                const Spacer(),
                Text(
                  _formatCurrency(order.totalAmount),
                  style: const TextStyle(
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
