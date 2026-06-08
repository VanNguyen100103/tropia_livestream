import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tropia_mobile_app_android/features/user/promotions/presentation/promotions_page.dart';
import 'package:tropia_mobile_app_android/features/user/ufresh/presentation/ufresh_page.dart';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/cart_badge_controller.dart';
import 'package:tropia_mobile_app_android/live_app/shell/live_tab_entry.dart';
import '../../home/presentation/home_page.dart';
import '../../cart/presentation/cart_page.dart';
import '../../profile/presentation/profile_page.dart';
import '../../home/presentation/widgets/home_header.dart';

// Import Controller vừa tạo
import 'package:tropia_mobile_app_android/core/utils/dashboard_controller.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key}); // Giữ đơn giản thế này thôi

  // Tab indexes (Define static để dùng chung)
  static const int tabHome = 0;
  static const int tabPromotions = 1;
  static const int tabUfresh = 2;
  static const int tabLive = 3; // Live module (lib/live_app)
  static const int tabCart = 4;
  static const int tabProfile = 5;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  int _currentIndex = 0;
  final CartBadgeController _cartBadge = CartBadgeController.instance;

  final List<Widget> _pages = [
    const HomePage(),
    const PromotionsPage(),
    const UfreshPage(),
    const LiveTabEntry(),
    const CartPage(),
    const ProfilePage(),
  ];

  @override
  void initState() {
    super.initState();
    _cartBadge.loadFromPrefs();
    _cartBadge.syncFromApi();

    // --- THÊM ĐOẠN NÀY: Đăng ký nhận lệnh từ Controller ---
    DashboardController.register((index) {
      // Chỉ chuyển nếu index hợp lệ
      if (index >= 0 && index < _pages.length) {
        setState(() {
          _currentIndex = index;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // ... (Phần UI bên dưới giữ nguyên y hệt code cũ của bạn)
    return AnnotatedRegion<SystemUiOverlayStyle>(
       // ... code cũ ...
       // (Copy nguyên phần build của bạn vào đây)
       value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Column(
          children: [
            // The Live tab is an immersive full-screen experience with its own
            // dark header — hide the shared white HomeHeader while it's active.
            if (_currentIndex != DashboardPage.tabLive) const HomeHeader(),
            Expanded(child: _pages[_currentIndex]),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _currentIndex,
          onDestinationSelected: (int index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          indicatorColor: const Color(0xFFFF5722).withValues(alpha: 0.2),
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home, color: Color(0xFFFF5722)),
              label: 'Trang chủ',
            ),
            const NavigationDestination(
              icon: Icon(Icons.local_offer_outlined),
              selectedIcon: Icon(Icons.local_offer, color: Color(0xFFFF5722)),
              label: 'Khuyến mãi',
            ),
            const NavigationDestination(
              icon: Icon(Icons.eco_outlined),
              selectedIcon: Icon(Icons.eco, color: Color(0xFFFF5722)),
              label: 'Ufresh',
            ),
            const NavigationDestination(
              icon: Icon(Icons.live_tv_outlined),
              selectedIcon: Icon(Icons.live_tv, color: Color(0xFFFF5722)),
              label: 'Live & Video',
            ),
            NavigationDestination(
              icon: _buildCartIcon(selected: false),
              selectedIcon: _buildCartIcon(selected: true),
              label: 'Giỏ hàng',
            ),
            const NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person, color: Color(0xFFFF5722)),
              label: 'Cá nhân',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCartIcon({required bool selected}) {
      // ... code cũ giữ nguyên
      final icon = selected ? Icons.shopping_cart : Icons.shopping_cart_outlined;
    final Color? iconColor = selected ? const Color(0xFFFF5722) : null;

    return ValueListenableBuilder<int>(
      valueListenable: _cartBadge.count,
      builder: (context, count, child) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(icon, color: iconColor),
            if (count > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}