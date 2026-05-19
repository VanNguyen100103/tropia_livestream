import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/product/models/product_model.dart';
import 'package:tropia/features/product/data/product_repository.dart';
import 'package:tropia/features/shop/data/shop_repository.dart';
import 'package:tropia/features/shop/models/shop_model.dart';

const _tag = 'ShopDetailScreen';

/// Trang công khai của một shop — buyer xem được.
/// Truyền [shopId] hoặc [shopSlug] (ít nhất 1 cái).
class ShopDetailScreen extends StatefulWidget {
  final String? shopId;
  final String? shopSlug;

  const ShopDetailScreen({super.key, this.shopId, this.shopSlug})
      : assert(shopId != null || shopSlug != null);

  @override
  State<ShopDetailScreen> createState() => _ShopDetailScreenState();
}

class _ShopDetailScreenState extends State<ShopDetailScreen> {
  ShopModel? _shop;
  List<ProductModel> _products = [];
  bool _loadingShop = true;
  bool _loadingProducts = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final slug = widget.shopSlug ?? widget.shopId!;
      final shop = await ShopRepository.instance.getBySlug(slug);
      if (!mounted) return;
      setState(() {
        _shop = shop;
        _loadingShop = false;
      });
      _loadProducts(shop.id);
    } catch (e, st) {
      AppLogger.logError(_tag, 'loadShop failed', e, st);
      if (mounted) setState(() { _loadingShop = false; _error = 'Không thể tải thông tin cửa hàng'; });
    }
  }

  Future<void> _loadProducts(String shopId) async {
    setState(() => _loadingProducts = true);
    try {
      final result = await ProductRepository.instance.getByShop(shopId);
      if (mounted) setState(() { _products = result.items; _loadingProducts = false; });
    } catch (e, st) {
      AppLogger.logError(_tag, 'loadProducts failed', e, st);
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  Future<void> _toggleFollow() async {
    if (_shop == null) return;
    final wasFollowing = _shop!.isFollowing;
    setState(() {
      _shop = _shop!.copyWith(
        isFollowing: !wasFollowing,
        followerCount: _shop!.followerCount + (wasFollowing ? -1 : 1),
      );
    });
    try {
      if (wasFollowing) {
        await ShopRepository.instance.unfollow(_shop!.id);
      } else {
        await ShopRepository.instance.follow(_shop!.id);
      }
      AppLogger.logUserEvent(
        action: wasFollowing ? 'unfollow_shop' : 'follow_shop',
        context: _tag,
        metadata: {'shopId': _shop!.id},
      );
    } catch (_) {
      // rollback
      if (mounted) {
        setState(() {
          _shop = _shop!.copyWith(
            isFollowing: wasFollowing,
            followerCount: _shop!.followerCount + (wasFollowing ? 1 : -1),
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingShop) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _shop == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.textHint),
              const SizedBox(height: AppSizes.md),
              Text(_error ?? 'Không tìm thấy cửa hàng',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSizes.md),
              TextButton(onPressed: _load, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }

    final shop = _shop!;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(shop),
          SliverToBoxAdapter(child: _buildShopInfo(shop)),
          SliverToBoxAdapter(child: _buildStats(shop)),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(AppSizes.md, AppSizes.md, AppSizes.md, AppSizes.sm),
              child: Text(
                'Sản phẩm',
                style: TextStyle(
                  fontSize: AppSizes.fontLg,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
          _buildProductGrid(),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(ShopModel shop) {
    return SliverAppBar(
      expandedHeight: 180,
      pinned: true,
      flexibleSpace: FlexibleSpaceBar(
        background: shop.bannerUrl != null
            ? CachedNetworkImage(
                imageUrl: shop.bannerUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(color: AppColors.primaryContainer),
              )
            : Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primary, AppColors.primaryLight],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.share_outlined, color: Colors.white),
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _buildShopInfo(ShopModel shop) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
            ),
            clipBehavior: Clip.antiAlias,
            child: shop.logoUrl != null || shop.avatarUrl != null
                ? CachedNetworkImage(
                    imageUrl: (shop.logoUrl ?? shop.avatarUrl)!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const Icon(Icons.storefront, color: AppColors.primary, size: 30),
                  )
                : const Icon(Icons.storefront, color: AppColors.primary, size: 30),
          ),
          const SizedBox(width: AppSizes.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        shop.name,
                        style: const TextStyle(
                          fontSize: AppSizes.fontXl,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (shop.isVerified)
                      const Icon(Icons.verified, color: AppColors.primary, size: 18),
                  ],
                ),
                if (shop.description != null && shop.description!.isNotEmpty) ...[
                  const SizedBox(height: AppSizes.xs),
                  Text(
                    shop.description!,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: AppSizes.fontSm),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          // Follow button
          OutlinedButton(
            onPressed: _toggleFollow,
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                color: shop.isFollowing ? AppColors.textHint : AppColors.primary,
              ),
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.xs),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusFull),
              ),
            ),
            child: Text(
              shop.isFollowing ? 'Đã theo dõi' : 'Theo dõi',
              style: TextStyle(
                color: shop.isFollowing ? AppColors.textSecondary : AppColors.primary,
                fontSize: AppSizes.fontSm,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(ShopModel shop) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSizes.md),
      padding: const EdgeInsets.symmetric(vertical: AppSizes.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          _StatItem(
            value: _formatCount(shop.followerCount),
            label: 'Người theo dõi',
          ),
          _Divider(),
          _StatItem(
            value: _formatCount(shop.totalSales),
            label: 'Đã bán',
          ),
          _Divider(),
          _StatItem(
            value: shop.rating > 0 ? shop.rating.toStringAsFixed(1) : '--',
            label: 'Đánh giá',
            icon: shop.rating > 0 ? Icons.star : null,
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid() {
    if (_loadingProducts) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSizes.xl),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (_products.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.all(AppSizes.xl),
          child: Center(
            child: Text('Cửa hàng chưa có sản phẩm nào',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ),
      );
    }
    return SliverPadding(
      padding: const EdgeInsets.all(AppSizes.md),
      sliver: SliverGrid(
        delegate: SliverChildBuilderDelegate(
          (context, i) => _ProductCard(product: _products[i]),
          childCount: _products.length,
        ),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: AppSizes.sm,
          crossAxisSpacing: AppSizes.sm,
          childAspectRatio: 0.72,
        ),
      ),
    );
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}Tr';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;

  const _StatItem({required this.value, required this.label, this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: AppColors.gold),
                const SizedBox(width: 2),
              ],
              Text(
                value,
                style: const TextStyle(
                  fontSize: AppSizes.fontLg,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          Text(
            label,
            style: const TextStyle(fontSize: AppSizes.fontXs, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(width: 1, height: 32, color: AppColors.divider);
  }
}

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: product.thumbnail != null
                ? CachedNetworkImage(
                    imageUrl: product.thumbnail!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorWidget: (_, __, ___) => Container(
                      color: AppColors.surfaceVariant,
                      child: const Icon(Icons.image_outlined,
                          color: AppColors.textHint, size: 40),
                    ),
                  )
                : Container(
                    color: AppColors.surfaceVariant,
                    child: const Center(
                      child: Icon(Icons.image_outlined,
                          color: AppColors.textHint, size: 40),
                    ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSizes.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppSizes.fontSm,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSizes.xs),
                Text(
                  _formatPrice(product.basePrice),
                  style: const TextStyle(
                    fontSize: AppSizes.fontMd,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary,
                  ),
                ),
              ],
            ),
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
