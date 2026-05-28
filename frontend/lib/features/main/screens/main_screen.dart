// =============================================================================
// main_screen.dart
// =============================================================================
// Màn hình chính với Bottom Navigation Bar của Tropia.
//
// Cấu trúc tab:
//   Tab 0: Trang chủ   (HomeScreen)
//   Tab 1: Khuyến mãi  (PromoScreen – placeholder)
//   Tab 2: Live 🔴     (LiveTabScreen) ← tab trung tâm nổi bật
//   Tab 3: Giỏ hàng    (CartScreen – placeholder)
//   Tab 4: Cá nhân     (ProfileScreen – placeholder)
//
// TAB LIVE (tab 2) được thiết kế nổi bật hơn các tab khác:
//   - Icon to hơn (live_tv), đặt trong container tròn màu xanh
//   - Không có label "Live" mà thay bằng badge đỏ "LIVE"
//   - Tương tự cách Shopee highlight tab video/live
//
// SỬ DỤNG:
//   Đặt làm home của MaterialApp hoặc sau splash screen
// =============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/live/screens/live_tab_screen.dart';
import 'package:tropia/features/home/screens/home_screen.dart';
import 'package:tropia/features/cart/providers/cart_provider.dart';
import 'package:tropia/features/cart/screens/cart_screen.dart';
import 'package:tropia/features/live/providers/live_provider.dart';
import 'package:tropia/features/user/screens/profile_screen.dart';

const _tag = 'MainScreen';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  // ─── Danh sách các screen ────────────────────────────────────────────────
  // Dùng IndexedStack để giữ state của từng tab (không reload khi chuyển tab)
  static final List<Widget> _screens = [
    const HomeScreen(),    // Tab 0: Trang chủ
    const _PromoScreen(),  // Tab 1: Khuyến mãi
    const LiveTabScreen(), // Tab 2: Live
    const CartScreen(),    // Tab 3: Giỏ hàng
    const ProfileScreen(), // Tab 4: Cá nhân
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack giữ state của tất cả screen, tránh rebuild khi đổi tab
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),

      bottomNavigationBar: _buildBottomNavBar(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Bottom Navigation Bar
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.navBackground,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: AppSizes.bottomNavHeight,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildNavItem(
                index: 0,
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: AppStrings.navHome,
              ),
              _buildNavItem(
                index: 1,
                icon: Icons.local_offer_outlined,
                activeIcon: Icons.local_offer,
                label: AppStrings.navPromotion,
              ),

              // Tab Live: nổi bật hơn
              _buildLiveNavItem(),

              Consumer<CartProvider>(
                builder: (_, cart, __) => _buildNavItem(
                  index: 3,
                  icon: Icons.shopping_cart_outlined,
                  activeIcon: Icons.shopping_cart,
                  label: AppStrings.navCart,
                  badgeCount: cart.totalCount,
                ),
              ),
              _buildNavItem(
                index: 4,
                icon: Icons.person_outline,
                activeIcon: Icons.person,
                label: AppStrings.navProfile,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Nav item thường
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildNavItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
    int? badgeCount,
  }) {
    final isActive = _currentIndex == index;

    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabTapped(index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedSwitcher(
                  duration: AppDurations.fast,
                  child: Icon(
                    isActive ? activeIcon : icon,
                    key: ValueKey(isActive),
                    color: isActive
                        ? AppColors.navSelected
                        : AppColors.navUnselected,
                    size: AppSizes.iconMd,
                  ),
                ),
                // Badge count
                if (badgeCount != null && badgeCount > 0)
                  Positioned(
                    top: -4,
                    right: -6,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: AppColors.liveRed,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          badgeCount > 9 ? '9+' : '$badgeCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: AppDurations.fast,
              style: TextStyle(
                color: isActive
                    ? AppColors.navSelected
                    : AppColors.navUnselected,
                fontSize: AppSizes.fontXs,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Nav item LIVE (nổi bật)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLiveNavItem() {
    final isActive = _currentIndex == 2;

    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabTapped(2),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Container tròn đặc biệt cho Live
            AnimatedContainer(
              duration: AppDurations.normal,
              width: 48,
              height: 34,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.4),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Center(
                child: Icon(
                  isActive ? Icons.live_tv : Icons.live_tv_outlined,
                  color: isActive ? Colors.white : AppColors.primary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: AppDurations.fast,
              style: TextStyle(
                color: isActive ? AppColors.navSelected : AppColors.navUnselected,
                fontSize: AppSizes.fontXs,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              ),
              child: const Text(AppStrings.navLive),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Tab tap handler
  // ─────────────────────────────────────────────────────────────────────────

  void _onTabTapped(int index) {
    if (_currentIndex == index) return;

    setState(() => _currentIndex = index);

    // Refresh live list mỗi lần user quay về tab Live
    if (index == 2) {
      context.read<LiveProvider>().refresh();
    }
    // Refresh cart mỗi lần user quay về tab Giỏ hàng — cần thiết vì
    // CartScreen nằm trong IndexedStack (state preserved) nên
    // initState chỉ chạy 1 lần. Sau khi thanh toán MoMo/VNPay/ZaloPay
    // (mở tab mới), backend đã xoá cart_items qua MarkPaid; nếu không
    // reload ở đây user sẽ thấy giỏ hàng cũ với items đã thanh toán.
    if (index == 3) {
      context.read<CartProvider>().load();
    }

    final tabNames = [
      AppStrings.navHome,
      AppStrings.navPromotion,
      AppStrings.navLive,
      AppStrings.navCart,
      AppStrings.navProfile,
    ];
    AppLogger.logInfo(_tag, 'Tab changed to: ${tabNames[index]} (index: $index)');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder screens (sẽ được implement trong sprint sau)
// ─────────────────────────────────────────────────────────────────────────────

class _PromoScreen extends StatelessWidget {
  const _PromoScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.navPromotion)),
      body: const _PlaceholderContent(
        icon: Icons.local_offer,
        title: AppStrings.navPromotion,
        subtitle: 'Khuyến mãi và ưu đãi đặc biệt sẽ sớm ra mắt',
        color: AppColors.primary,
      ),
    );
  }
}


/// Widget placeholder chung cho các tab chưa implement
class _PlaceholderContent extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  const _PlaceholderContent({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: AppSizes.iconXl,
                color: color,
              ),
            ),
            const SizedBox(height: AppSizes.md),
            Text(
              title,
              style: const TextStyle(
                fontSize: AppSizes.fontXxl,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: AppSizes.fontMd,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSizes.xl),

            // Tropia branding
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.lg,
                vertical: AppSizes.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppSizes.radiusFull),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.eco, color: AppColors.primary, size: 16),
                  SizedBox(width: AppSizes.xs),
                  Text(
                    'Tropia – Thực phẩm tươi Việt Nam',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: AppSizes.fontSm,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
