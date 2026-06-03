import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/features/user/auth/presentation/auth_page.dart';

import 'package:tropia_mobile_app_android/features/admin/orders/presentation/pages/orders_list_screen.dart';
import '../../dashboard/presentation/pages/dashboard_screen.dart';
import '../../products/presentation/pages/product_list_screen.dart';
import '../../promotions/presentation/pages/promotion_list_screen.dart';
import '../../customers/presentation/pages/customer_list_screen.dart';

class AdminScaffold extends StatefulWidget {
  const AdminScaffold({super.key});

  @override
  State<AdminScaffold> createState() => _AdminScaffoldState();
}

class _AdminScaffoldState extends State<AdminScaffold> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const DashboardScreen(),
    const ProductListScreen(),
    const PromotionListScreen(),
    const OrdersListScreen(),
    const CustomersListScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // [MỚI] Hàm xử lý Đăng xuất
  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Đăng xuất"),
        content: const Text("Bạn có chắc chắn muốn đăng xuất khỏi Admin?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Hủy", style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "Đăng xuất",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // 1. Xóa Token
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('app_auth_token');

      // 2. Chuyển về màn hình Login (Xóa hết stack cũ)
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AuthPage()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        extendBody: true,

        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.eco, color: Colors.orange, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                "TROPIA Admin",
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          actions: [
            // [CẬP NHẬT] Đổi nút Notification thành Logout
            Container(
              margin: const EdgeInsets.only(right: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () => _handleLogout(context), // Gọi hàm logout
                icon: const Icon(
                  Icons.logout_rounded, // Icon Logout
                  color: Colors.redAccent, // Màu đỏ để cảnh báo
                  size: 20,
                ),
                tooltip: "Đăng xuất",
              ),
            ),
          ],
        ),

        // Sử dụng IndexedStack để giữ trạng thái các màn hình
        body: IndexedStack(index: _selectedIndex, children: _screens),

        // THANH NAVIGATION NỔI (Floating)
        bottomNavigationBar: SafeArea(
          bottom: true,
          child: Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildNavItem(0, Icons.bar_chart_rounded, "Tổng quan"),
                _buildNavItem(1, Icons.inventory_2_outlined, "Sản phẩm"),
                _buildNavItem(2, Icons.confirmation_number_outlined, "Voucher"),
                _buildNavItem(3, Icons.shopping_bag_outlined, "Đơn hàng"),
                _buildNavItem(4, Icons.people_outline, "Khách"),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;

    return GestureDetector(
      onTap: () => _onItemTapped(index),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: isSelected
            ? BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.orange[700] : Colors.grey[400],
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? Colors.orange[700] : Colors.grey[400],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
