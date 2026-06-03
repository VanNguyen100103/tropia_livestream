import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';

// --- DASHBOARD FEATURE ---
import 'package:tropia_mobile_app_android/features/admin/dashboard/data/models/dashboard_stats_model.dart';
import 'package:tropia_mobile_app_android/features/admin/dashboard/data/models/chart_data_model.dart';
import 'package:tropia_mobile_app_android/features/admin/dashboard/data/models/order_model.dart';
import 'package:tropia_mobile_app_android/features/admin/dashboard/data/repositories/dashboard_repository.dart';

// --- AUTH FEATURE ---
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';

// --- WIDGETS ---
import '../widgets/summary_card.dart';
import '../widgets/revenue_chart.dart';
import '../widgets/recent_orders.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Biến trạng thái
  bool _isLoading = true;
  DashboardStatsModel? _stats;
  List<ChartDataModel> _chartData = [];
  List<OrderModel> _recentOrders = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  // --- QUY TRÌNH KHỞI TẠO DỮ LIỆU ---
  Future<void> _initData() async {
    final dio = DioClient().dio;

    try {
      // BƯỚC 1: LẤY TOKEN ADMIN
      final authRepo = AppAuthRepository(
        remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
      );
      await authRepo.authenticateApp();

      // BƯỚC 2: SAU KHI CÓ TOKEN, GỌI CÁC API DASHBOARD
      await _fetchStats();
    } catch (e) {
      debugPrint("Lỗi khởi tạo Dashboard: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Hàm này được gọi khi Init hoặc khi Kéo để refresh
  Future<void> _fetchStats() async {
    final dio = DioClient().dio;
    final repo = DashboardRepository(client: dio);

    // Gọi song song 3 API
    final results = await Future.wait([
      repo.getDashboardStats(), // Index 0
      repo.getRevenueChartData(), // Index 1
      repo.getRecentOrders(), // Index 2
    ]);

    if (mounted) {
      setState(() {
        _stats = results[0] as DashboardStatsModel?;
        _chartData = results[1] as List<ChartDataModel>;
        _recentOrders = results[2] as List<OrderModel>;
        _isLoading = false;
      });
    }
  }

  String _formatCurrency(num value) {
    final formatter = NumberFormat("#,###", "vi_VN");
    return "${formatter.format(value)}đ";
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final revenueVal = _stats?.revenue.value ?? 0;
    final revenueGrowth = _stats?.revenue.growth ?? 0;
    final ordersVal = _stats?.orders.value ?? 0;
    final ordersInc = _stats?.orders.increase ?? 0;
    final customerVal = _stats?.customers.value ?? 0;
    final customerInc = _stats?.customers.increase ?? 0;
    final productVal = _stats?.products.value ?? 0;
    final productStatus = _stats?.products.statusText ?? "Đang kinh doanh";

    // [CẬP NHẬT] Thêm RefreshIndicator
    return RefreshIndicator(
      onRefresh: _fetchStats, // Gọi lại hàm lấy dữ liệu khi kéo xuống
      color: Colors.orange, // Màu loading
      backgroundColor: Colors.white,
      child: SingleChildScrollView(
        // [QUAN TRỌNG] Luôn cho phép cuộn để kích hoạt kéo xuống
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 80.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hàng 1: Doanh thu & Đơn hàng
              Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      title: "Tổng doanh thu",
                      value: _formatCurrency(revenueVal),
                      subtitle: "+$revenueGrowth% tháng trước",
                      icon: Icons.attach_money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SummaryCard(
                      title: "Đơn hàng",
                      value: ordersVal.toString(),
                      subtitle: "+$ordersInc đơn hôm nay",
                      icon: Icons.inventory_2_outlined,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Hàng 2: Khách hàng & Sản phẩm
              Row(
                children: [
                  Expanded(
                    child: SummaryCard(
                      title: "Khách hàng",
                      value: customerVal.toString(),
                      subtitle: "+$customerInc người mới",
                      icon: Icons.people_outline,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SummaryCard(
                      title: "Sản phẩm",
                      value: productVal.toString(),
                      subtitle: productStatus,
                      icon: Icons.trending_up,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              RevenueChart(chartData: _chartData),

              const SizedBox(height: 16),

              RecentOrders(orders: _recentOrders),

              const SizedBox(height: 35),
            ],
          ),
        ),
      ),
    );
  }
}
