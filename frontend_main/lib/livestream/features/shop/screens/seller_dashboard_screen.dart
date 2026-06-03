import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tropia_mobile_app_android/livestream/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/livestream/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/screens/live_setup_screen.dart';
import 'package:tropia_mobile_app_android/livestream/features/order/data/order_repository.dart';
import 'package:tropia_mobile_app_android/livestream/features/order/models/order_model.dart';
import 'package:tropia_mobile_app_android/livestream/features/product/data/product_repository.dart';
import 'package:tropia_mobile_app_android/livestream/features/product/models/product_model.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/models/shop_model.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/providers/shop_provider.dart';

const _tag = 'SellerDashboardScreen';

/// Dashboard quản lý của seller: thông tin shop, sản phẩm, đơn hàng.
class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  List<ProductModel> _products = [];
  List<OrderModel> _orders = [];
  bool _loadingProducts = true;
  bool _loadingOrders = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadProducts(), _loadOrders()]);
  }

  Future<void> _loadProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final result = await ProductRepository.instance.getSellerProducts();
      if (mounted) setState(() { _products = result.items; _loadingProducts = false; });
    } catch (e, st) {
      AppLogger.logError(_tag, 'loadProducts failed', e, st);
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  Future<void> _loadOrders() async {
    setState(() => _loadingOrders = true);
    try {
      final result = await OrderRepository.instance.myOrders();
      if (mounted) setState(() { _orders = result.items; _loadingOrders = false; });
    } catch (e, st) {
      AppLogger.logError(_tag, 'loadOrders failed', e, st);
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final shopProvider = context.watch<ShopProvider>();
    final shop = shopProvider.myShop;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverAppBar(
            title: const Text('Quản lý cửa hàng'),
            pinned: true,
            forceElevated: true,
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Chỉnh sửa shop',
                onPressed: shop != null ? () => _showEditShopDialog(context, shop) : null,
              ),
            ],
            bottom: TabBar(
              controller: _tabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Sản phẩm'),
                Tab(text: 'Đơn hàng'),
              ],
            ),
          ),
          SliverToBoxAdapter(child: _buildShopCard(shop)),
          SliverToBoxAdapter(child: _buildStatsRow()),
        ],
        body: TabBarView(
          controller: _tabCtrl,
          children: [
            _buildProductsTab(),
            _buildOrdersTab(),
          ],
        ),
      ),
      floatingActionButton: _tabCtrl.index == 0
          ? FloatingActionButton.extended(
              onPressed: () {
                AppLogger.logUserEvent(action: 'tap_add_product', context: _tag);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Tính năng thêm sản phẩm sắp ra mắt')),
                );
              },
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.add),
              label: const Text('Thêm sản phẩm'),
            )
          : null,
    );
  }

  Widget _buildShopCard(ShopModel? shop) {
    if (shop == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.all(AppSizes.md),
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.divider),
            ),
            clipBehavior: Clip.antiAlias,
            child: shop.logoUrl != null
                ? CachedNetworkImage(
                    imageUrl: shop.logoUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.storefront, color: AppColors.primary, size: 26),
                  )
                : const Icon(Icons.storefront, color: AppColors.primary, size: 26),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      shop.name,
                      style: const TextStyle(
                        fontSize: AppSizes.fontLg,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSizes.xs),
                    if (shop.isVerified)
                      const Icon(Icons.verified, color: AppColors.primary, size: 16),
                  ],
                ),
                if (shop.description != null && shop.description!.isNotEmpty)
                  Text(
                    shop.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: AppSizes.fontSm),
                  ),
              ],
            ),
          ),
          // Nút Tạo Live nhanh
          TextButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const LiveSetupScreen()),
              );
            },
            icon: const Icon(Icons.live_tv, size: 16),
            label: const Text('Live'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.liveRed,
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final pending = _orders.where((o) => o.isPending).length;
    final revenue = _orders
        .where((o) => o.isPaid)
        .fold<int>(0, (sum, o) => sum + o.finalPrice);

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.md, 0, AppSizes.md, AppSizes.md),
      child: Row(
        children: [
          _MiniStat(
            value: '${_products.length}',
            label: 'Sản phẩm',
            icon: Icons.inventory_2_outlined,
            color: AppColors.primary,
          ),
          const SizedBox(width: AppSizes.sm),
          _MiniStat(
            value: '$pending',
            label: 'Chờ xử lý',
            icon: Icons.hourglass_empty,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSizes.sm),
          _MiniStat(
            value: _formatPrice(revenue),
            label: 'Doanh thu',
            icon: Icons.payments_outlined,
            color: AppColors.secondary,
          ),
        ],
      ),
    );
  }

  // ── Tab sản phẩm ──────────────────────────────────────────────────────────

  Widget _buildProductsTab() {
    if (_loadingProducts) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_products.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.textHint),
            const SizedBox(height: AppSizes.md),
            const Text('Chưa có sản phẩm nào',
                style: TextStyle(color: AppColors.textSecondary, fontSize: AppSizes.fontMd)),
            const SizedBox(height: AppSizes.md),
            FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('Thêm sản phẩm đầu tiên'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSizes.md),
      itemCount: _products.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
      itemBuilder: (_, i) => _ProductRow(
        product: _products[i],
        onToggleStatus: () => _toggleProductStatus(_products[i]),
      ),
    );
  }

  Future<void> _toggleProductStatus(ProductModel product) async {
    final newStatus = product.status == 'active' ? 'inactive' : 'active';
    try {
      await ProductRepository.instance.changeStatus(product.id, newStatus);
      await _loadProducts();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không thể cập nhật trạng thái')),
        );
      }
    }
  }

  // ── Tab đơn hàng ──────────────────────────────────────────────────────────

  Widget _buildOrdersTab() {
    if (_loadingOrders) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_orders.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 56, color: AppColors.textHint),
            SizedBox(height: AppSizes.md),
            Text('Chưa có đơn hàng nào',
                style: TextStyle(color: AppColors.textSecondary, fontSize: AppSizes.fontMd)),
          ],
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(AppSizes.md),
      itemCount: _orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
      itemBuilder: (_, i) => _OrderRow(order: _orders[i]),
    );
  }

  // ── Edit shop dialog ──────────────────────────────────────────────────────

  void _showEditShopDialog(BuildContext context, ShopModel shop) {
    final nameCtrl = TextEditingController(text: shop.name);
    final descCtrl = TextEditingController(text: shop.description ?? '');
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Chỉnh sửa cửa hàng'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Tên cửa hàng'),
                  validator: (v) => (v == null || v.trim().length < 3) ? 'Tối thiểu 3 ký tự' : null,
                ),
                const SizedBox(height: AppSizes.md),
                TextFormField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Mô tả'),
                  maxLines: 3,
                  maxLength: 200,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Huỷ'),
            ),
            Consumer<ShopProvider>(
              builder: (_, sp, __) => FilledButton(
                onPressed: sp.isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        final ok = await sp.updateShop(
                          name: nameCtrl.text.trim(),
                          description: descCtrl.text.trim(),
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (!ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(sp.error ?? 'Lỗi khi cập nhật')),
                          );
                        }
                      },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: sp.isSaving
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Lưu'),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      nameCtrl.dispose();
      descCtrl.dispose();
    });
  }

  String _formatPrice(int price) {
    if (price >= 1000000) return '${(price / 1000000).toStringAsFixed(1)}Tr';
    if (price >= 1000) return '${(price / 1000).toStringAsFixed(0)}K';
    return '${price}đ';
  }
}

// ── Mini stat card ─────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  final String value;
  final String label;
  final IconData icon;
  final Color color;

  const _MiniStat({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.md, horizontal: AppSizes.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: AppSizes.iconSm),
            const SizedBox(height: AppSizes.xs),
            Text(
              value,
              style: TextStyle(
                fontSize: AppSizes.fontMd,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: AppSizes.fontXs, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Product row ────────────────────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onToggleStatus;

  const _ProductRow({required this.product, required this.onToggleStatus});

  @override
  Widget build(BuildContext context) {
    final isActive = product.status == 'active';
    return Container(
      padding: const EdgeInsets.all(AppSizes.sm),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            child: product.thumbnail != null
                ? CachedNetworkImage(
                    imageUrl: product.thumbnail!,
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 56, height: 56,
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.image_outlined, color: AppColors.textHint),
                    ),
                  )
                : Container(
                    width: 56, height: 56,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.image_outlined, color: AppColors.textHint),
                  ),
          ),
          const SizedBox(width: AppSizes.sm),
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
                    fontSize: AppSizes.fontSm,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSizes.xs),
                Row(
                  children: [
                    Text(
                      _formatPrice(product.basePrice),
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w700,
                        fontSize: AppSizes.fontSm,
                      ),
                    ),
                    const SizedBox(width: AppSizes.sm),
                    Text(
                      'Kho: ${product.totalStock}',
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: AppSizes.fontXs),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Switch(
                value: isActive,
                onChanged: (_) => onToggleStatus(),
                activeThumbColor: AppColors.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              Text(
                isActive ? 'Đang bán' : 'Đã ẩn',
                style: TextStyle(
                  fontSize: AppSizes.fontXs,
                  color: isActive ? AppColors.primary : AppColors.textHint,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf}đ';
  }
}

// ── Order row ──────────────────────────────────────────────────────────────

class _OrderRow extends StatelessWidget {
  final OrderModel order;
  const _OrderRow({required this.order});

  @override
  Widget build(BuildContext context) {
    final statusColor = order.isPaid
        ? AppColors.success
        : order.isCancelled
            ? AppColors.error
            : AppColors.warning;
    final statusLabel = order.isPaid
        ? 'Đã thanh toán'
        : order.isCancelled
            ? 'Đã huỷ'
            : 'Chờ xử lý';

    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.productName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: AppSizes.fontSm,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: AppSizes.fontXs,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.xs),
          Row(
            children: [
              Text(
                'SL: ${order.quantity}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: AppSizes.fontXs),
              ),
              const SizedBox(width: AppSizes.md),
              Text(
                'Người mua: ${order.buyerName.isEmpty ? 'Khách' : order.buyerName}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: AppSizes.fontXs),
              ),
              const Spacer(),
              Text(
                _formatPrice(order.finalPrice),
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontWeight: FontWeight.w700,
                  fontSize: AppSizes.fontSm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf}đ';
  }
}
