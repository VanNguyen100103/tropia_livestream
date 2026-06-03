import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/datasources/order_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/order/domain/repositories/order_repository.dart';
import 'package:tropia_mobile_app_android/features/user/order/domain/repositories/order_repository_impl.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/models/user_orders.dart';
import '../../../../../core/constants/app_colors.dart';
import 'widgets/order_card.dart';

class OrderPage extends StatefulWidget {
  final bool showAppBar;

  const OrderPage({super.key, this.showAppBar = true});

  @override
  State<OrderPage> createState() => _OrderPageState();
}

class _OrderPageState extends State<OrderPage> {
  // Tabs hiển thị
  final List<String> _tabs = ["Tất cả", "Chờ", "Đang xử lý", "Hoàn thành"];
  int _selectedTab = 0;

  // Logic API
  late OrderRepository _orderRepository;
  bool _isLoading = true;
  String? _errorMessage;
  List<UserOrder> _allOrders = [];
  List<UserOrder> _filteredOrders = [];

  @override
  void initState() {
    super.initState();
    // 1. Khởi tạo Repository (Sửa lỗi: Bỏ tham số client nếu class không hỗ trợ)
    // DioClient sẽ được gọi ngầm bên trong OrderRemoteDataSourceImpl nếu bạn code đúng chuẩn Singleton
    _orderRepository = OrderRepositoryImpl(
      remoteDataSource: OrderRemoteDataSourceImpl(),
    );

    // 2. Gọi hàm tải dữ liệu
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // BƯỚC 1: Lấy SharedPreferences bên trong hàm async
      final prefs = await SharedPreferences.getInstance();

      // BƯỚC 2: Lấy User ID thật từ bộ nhớ
      final userId = prefs.getInt('user_id');

      debugPrint("DEBUG ORDER: Đang tải đơn hàng cho User ID: $userId");

      if (userId == null || userId == 0) {
        setState(() {
          _errorMessage =
              "Không tìm thấy thông tin người dùng. Vui lòng đăng nhập lại.";
          _isLoading = false;
        });
        return;
      }

      // BƯỚC 3: Gọi API
      final orders = await _orderRepository.getUserOrders(userId);

      if (mounted) {
        setState(() {
          _allOrders = orders;
          _isLoading = false;
        });
        _filterOrders(); // Lọc dữ liệu lần đầu
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              "Lỗi tải dữ liệu: ${e.toString().replaceAll('Exception: ', '')}";
          _isLoading = false;
        });
      }
    }
  }

  // --- HÀM LỌC DANH SÁCH ---
  void _filterOrders() {
    setState(() {
      if (_selectedTab == 0) {
        _filteredOrders = List.from(_allOrders);
      } else {
        String filterKey = "";
        if (_selectedTab == 1) filterKey = "pending";
        if (_selectedTab == 2) filterKey = "processing";
        if (_selectedTab == 3) filterKey = "success";

        _filteredOrders = _allOrders.where((order) {
          // SỬA LỖI: Thêm (order.status ?? "") để xử lý null trước khi toLowerCase
          final status = (order.status ?? "").toLowerCase();

          if (_selectedTab == 3) {
            return status.contains("success") ||
                status.contains("completed") ||
                status.contains("hoàn thành");
          }
          if (_selectedTab == 2) {
            return status.contains("processing") ||
                status.contains("đang xử lý");
          }
          return status.contains(filterKey);
        }).toList();
      }
    });
  }

  void _onTabSelected(int index) {
    setState(() {
      _selectedTab = index;
    });
    _filterOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text('Đơn hàng'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0.5,
            )
          : null,
      body: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 10),
            // Thanh Tab
            SizedBox(
              height: 35,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 0,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: _tabs.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  bool isSelected = _selectedTab == index;
                  return GestureDetector(
                    onTap: () => _onTabSelected(index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        _tabs[index],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? AppColors.primary
                              : Colors.grey[600],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            // Nội dung danh sách
            Expanded(child: _buildListContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildListContent() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 40),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center),
            TextButton(onPressed: _fetchOrders, child: const Text("Thử lại")),
          ],
        ),
      );
    }

    if (_filteredOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 60, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              "Không có đơn hàng nào ở mục này",
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchOrders,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _filteredOrders.length,
        itemBuilder: (context, index) {
          final order = _filteredOrders[index];
          return OrderCard(
            order: order,
            onReorder: () {
              debugPrint("Mua lại đơn: ${order.id}");
            },
            onCancelled: _fetchOrders,
          );
        },
      ),
    );
  }
}
