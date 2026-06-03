import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tropia_mobile_app_android/livestream/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/livestream/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/livestream/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/providers/shop_provider.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/screens/become_seller_screen.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/screens/seller_dashboard_screen.dart';
import 'package:tropia_mobile_app_android/livestream/features/user/models/user_model.dart';
import 'package:tropia_mobile_app_android/livestream/features/user/providers/user_provider.dart';
import 'package:tropia_mobile_app_android/livestream/features/user/screens/login_screen.dart';

const _tag = 'ProfileScreen';

/// Tab Cá nhân:
///   - Chưa đăng nhập → hiện nút đăng nhập
///   - Buyer          → thông tin, đơn hàng, nút "Trở thành Seller"
///   - Seller         → thông tin + truy cập SellerDashboard
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoadShop());
  }

  void _maybeLoadShop() {
    final user = context.read<UserProvider>().currentUser;
    if (user?.role == UserRole.seller) {
      context.read<ShopProvider>().loadMyShop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = context.watch<UserProvider>();

    if (!userProvider.isSignedIn) return _buildNotSignedIn(context);

    final user = userProvider.currentUser!;
    final isSeller = user.role == UserRole.seller;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        color: AppColors.primary,
        onRefresh: () async {
          if (isSeller) await context.read<ShopProvider>().loadMyShop();
        },
        child: CustomScrollView(
          slivers: [
            _buildSliverAppBar(context, user),
            SliverToBoxAdapter(child: _buildUserCard(context, user, isSeller)),
            if (isSeller) ...[
              const SliverToBoxAdapter(child: SizedBox(height: AppSizes.sm)),
              SliverToBoxAdapter(child: _buildSellerActions(context)),
            ] else ...[
              const SliverToBoxAdapter(child: SizedBox(height: AppSizes.sm)),
              SliverToBoxAdapter(child: _buildBecomeSellerBanner(context)),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: AppSizes.md)),
            SliverToBoxAdapter(child: _buildMenuSection(context, isSeller)),
            const SliverToBoxAdapter(child: SizedBox(height: AppSizes.xxl)),
          ],
        ),
      ),
    );
  }

  // ── Chưa đăng nhập ────────────────────────────────────────────────────────

  Widget _buildNotSignedIn(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.navProfile)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: const BoxDecoration(
                  color: AppColors.surfaceVariant,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_outline, size: 52, color: AppColors.textHint),
              ),
              const SizedBox(height: AppSizes.lg),
              const Text(
                'Chưa đăng nhập',
                style: TextStyle(
                  fontSize: AppSizes.fontXl,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: AppSizes.xs),
              const Text(
                'Đăng nhập để xem lịch sử đơn hàng,\ntheo dõi cửa hàng yêu thích và nhiều hơn nữa',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: AppSizes.xl),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size(double.infinity, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                ),
                child: const Text(
                  'Đăng nhập / Đăng ký',
                  style: TextStyle(fontSize: AppSizes.fontMd, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Sliver App Bar ─────────────────────────────────────────────────────────

  Widget _buildSliverAppBar(BuildContext context, UserModel user) {
    return SliverAppBar(
      title: const Text('Cá nhân'),
      pinned: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _showSettingsSheet(context),
        ),
      ],
    );
  }

  // ── User card ──────────────────────────────────────────────────────────────

  Widget _buildUserCard(BuildContext context, UserModel user, bool isSeller) {
    return Container(
      margin: const EdgeInsets.all(AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Avatar
          Stack(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundImage:
                    user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                backgroundColor:
                    isSeller ? AppColors.primaryContainer : AppColors.surfaceVariant,
                child: user.avatarUrl == null
                    ? Icon(
                        isSeller ? Icons.storefront : Icons.person,
                        size: 36,
                        color: AppColors.primary,
                      )
                    : null,
              ),
              if (isSeller)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.storefront, size: 11, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: const TextStyle(
                    fontSize: AppSizes.fontLg,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  user.email,
                  style: const TextStyle(
                    fontSize: AppSizes.fontSm,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSizes.xs),
                _RoleBadge(isSeller: isSeller, label: user.role.displayName),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Seller: shortcut đến dashboard ────────────────────────────────────────

  Widget _buildSellerActions(BuildContext context) {
    final shop = context.watch<ShopProvider>().myShop;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SellerDashboardScreen()),
        ),
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          ),
          child: Row(
            children: [
              const Icon(Icons.storefront, color: Colors.white, size: 28),
              const SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shop?.name ?? 'Cửa hàng của tôi',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: AppSizes.fontMd,
                      ),
                    ),
                    const Text(
                      'Quản lý sản phẩm, đơn hàng và phát Live',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: AppSizes.fontXs,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }

  // ── Buyer: banner mời trở thành seller ────────────────────────────────────

  Widget _buildBecomeSellerBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      child: InkWell(
        onTap: () async {
          AppLogger.logUserEvent(action: 'tap_become_seller', context: _tag);
          final result = await Navigator.of(context).push<bool>(
            MaterialPageRoute(builder: (_) => const BecomeSellerScreen()),
          );
          if (result == true && mounted) {
            await AuthService.instance.refreshUser();
            if (mounted) context.read<ShopProvider>().loadMyShop();
          }
        },
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        child: Container(
          padding: const EdgeInsets.all(AppSizes.md),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.storefront, color: AppColors.primary, size: 28),
              SizedBox(width: AppSizes.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Trở thành Người bán',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppSizes.fontMd,
                      ),
                    ),
                    Text(
                      'Tạo cửa hàng và bắt đầu livestream bán hàng',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: AppSizes.fontXs,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  // ── Menu chức năng ────────────────────────────────────────────────────────

  Widget _buildMenuSection(BuildContext context, bool isSeller) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          if (isSeller) ...[
            _MenuItem(
              icon: Icons.dashboard_outlined,
              label: 'Quản lý cửa hàng',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SellerDashboardScreen()),
              ),
            ),
            const Divider(height: 1, indent: 56),
          ],
          _MenuItem(
            icon: Icons.receipt_long_outlined,
            label: 'Đơn mua của tôi',
            onTap: () {
              AppLogger.logUserEvent(action: 'tap_my_orders', context: _tag);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng đơn hàng sắp ra mắt')),
              );
            },
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.favorite_border,
            label: 'Cửa hàng đã theo dõi',
            onTap: () {
              AppLogger.logUserEvent(action: 'tap_followed_shops', context: _tag);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng sắp ra mắt')),
              );
            },
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.person_outline,
            label: 'Chỉnh sửa hồ sơ',
            onTap: () {
              AppLogger.logUserEvent(action: 'tap_edit_profile', context: _tag);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng sắp ra mắt')),
              );
            },
          ),
          const Divider(height: 1, indent: 56),
          _MenuItem(
            icon: Icons.logout,
            label: 'Đăng xuất',
            labelColor: AppColors.error,
            iconColor: AppColors.error,
            onTap: () => _confirmLogout(context),
          ),
        ],
      ),
    );
  }

  // ── Settings bottom sheet ─────────────────────────────────────────────────

  void _showSettingsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppSizes.radiusLg)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSizes.md),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Cài đặt',
              style: TextStyle(fontSize: AppSizes.fontLg, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSizes.md),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('Thông báo'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Chính sách bảo mật'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('Trợ giúp'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  // ── Confirm logout ────────────────────────────────────────────────────────

  void _confirmLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc muốn đăng xuất?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              AppLogger.logUserEvent(action: 'logout', context: _tag);
              await AuthService.instance.logout();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}

// ── Role badge ─────────────────────────────────────────────────────────────

class _RoleBadge extends StatelessWidget {
  final bool isSeller;
  final String label;
  const _RoleBadge({required this.isSeller, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
      decoration: BoxDecoration(
        color: isSeller ? AppColors.primaryContainer : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        border: Border.all(
          color: isSeller ? AppColors.primary.withValues(alpha: 0.5) : AppColors.divider,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSeller ? Icons.storefront : Icons.person_outline,
            size: 11,
            color: isSeller ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
              color: isSeller ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Menu item ──────────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? labelColor;
  final Color? iconColor;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelColor,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.md),
        child: Row(
          children: [
            Icon(icon, size: AppSizes.iconSm + 4, color: iconColor ?? AppColors.textSecondary),
            const SizedBox(width: AppSizes.md),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: AppSizes.fontMd,
                  color: labelColor ?? AppColors.textPrimary,
                ),
              ),
            ),
            Icon(Icons.chevron_right, size: AppSizes.iconSm, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }
}
