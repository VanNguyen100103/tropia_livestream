import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/livestream/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/livestream/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/livestream/features/product/data/product_repository.dart';
import 'package:tropia_mobile_app_android/livestream/features/product/models/product_model.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/data/shop_repository.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/models/shop_model.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/widgets/follow_button.dart';

const _tag = 'ProductDetailScreen';

class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    this.product,
    this.slug,
  }) : assert(product != null || slug != null, 'product or slug required');

  final ProductModel? product;
  final String? slug;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  ProductModel? _product;
  ShopModel? _shop;
  bool _loadingProduct = false;
  bool _loadingShop = false;
  String? _error;

  int _selectedVariantIndex = 0;
  int _quantity = 1;
  final PageController _pageController = PageController();
  int _currentImagePage = 0;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    if (_product != null) {
      _loadShop(_product!.shopId);
    } else {
      _loadProduct(widget.slug!);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadProduct(String slug) async {
    setState(() => _loadingProduct = true);
    try {
      final product = await ProductRepository.instance.getBySlug(slug);
      if (mounted) {
        setState(() {
          _product = product;
          _loadingProduct = false;
        });
        _loadShop(product.shopId);
      }
    } catch (e, st) {
      AppLogger.logError(_tag, 'Failed to load product', e, st);
      if (mounted) setState(() { _error = 'Không thể tải sản phẩm'; _loadingProduct = false; });
    }
  }

  Future<void> _loadShop(String shopId) async {
    setState(() => _loadingShop = true);
    try {
      final shop = await ShopRepository.instance.getBySlug(shopId);
      if (mounted) setState(() { _shop = shop; _loadingShop = false; });
    } catch (e, st) {
      AppLogger.logError(_tag, 'Failed to load shop', e, st);
      if (mounted) setState(() => _loadingShop = false);
    }
  }

  List<String> get _images {
    final product = _product;
    if (product == null) return [];
    if (product.variants.isNotEmpty &&
        product.variants[_selectedVariantIndex].images.isNotEmpty) {
      return product.variants[_selectedVariantIndex].images;
    }
    if (product.thumbnail != null) return [product.thumbnail!];
    return [];
  }

  int get _selectedPrice {
    final product = _product;
    if (product == null) return 0;
    if (product.variants.isEmpty) return product.basePrice;
    return product.variants[_selectedVariantIndex].price;
  }

  int get _selectedStock {
    final product = _product;
    if (product == null) return 0;
    if (product.variants.isEmpty) return 0;
    return product.variants[_selectedVariantIndex].stock;
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingProduct) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.surface, elevation: 0),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _product == null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: AppColors.surface, elevation: 0),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.textHint),
              const SizedBox(height: AppSizes.sm),
              Text(_error ?? 'Không tìm thấy sản phẩm',
                  style: const TextStyle(color: AppColors.textSecondary)),
              const SizedBox(height: AppSizes.md),
              ElevatedButton(
                onPressed: () => _loadProduct(widget.slug ?? _product!.slug),
                child: const Text('Thử lại'),
              ),
            ],
          ),
        ),
      );
    }

    final product = _product!;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                _buildImageSliver(product),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPriceSection(product),
                      const Divider(height: 8, thickness: 8, color: AppColors.background),
                      _buildVariantsSection(product),
                      if (product.variants.isNotEmpty) ...[
                        const Divider(height: 8, thickness: 8, color: AppColors.background),
                        _buildQuantitySection(),
                      ],
                      const Divider(height: 8, thickness: 8, color: AppColors.background),
                      _buildShopSection(),
                      const Divider(height: 8, thickness: 8, color: AppColors.background),
                      _buildDescriptionSection(product),
                      const SizedBox(height: AppSizes.xxl),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildBottomBar(product),
        ],
      ),
    );
  }

  Widget _buildImageSliver(ProductModel product) {
    final images = _images;
    return SliverAppBar(
      expandedHeight: 340,
      pinned: true,
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          children: [
            if (images.isEmpty)
              Container(
                color: AppColors.primaryContainer,
                child: const Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      size: 64, color: AppColors.textHint),
                ),
              )
            else
              PageView.builder(
                controller: _pageController,
                itemCount: images.length,
                onPageChanged: (i) => setState(() => _currentImagePage = i),
                itemBuilder: (context, i) => CachedNetworkImage(
                  imageUrl: images[i],
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(color: AppColors.primaryContainer),
                  errorWidget: (_, __, ___) => Container(
                    color: AppColors.primaryContainer,
                    child: const Icon(Icons.broken_image_outlined,
                        size: 48, color: AppColors.textHint),
                  ),
                ),
              ),
            if (images.length > 1)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(images.length, (i) => AnimatedContainer(
                    duration: AppDurations.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: _currentImagePage == i ? 16 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _currentImagePage == i
                          ? AppColors.primary
                          : Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  )),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceSection(ProductModel product) {
    final minPrice = product.variants.isEmpty
        ? product.basePrice
        : product.variants.map((v) => v.price).reduce((a, b) => a < b ? a : b);
    final maxPrice = product.variants.isEmpty
        ? product.basePrice
        : product.variants.map((v) => v.price).reduce((a, b) => a > b ? a : b);

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                _formatPrice(_selectedPrice > 0 ? _selectedPrice : minPrice),
                style: const TextStyle(
                  color: AppColors.secondary,
                  fontSize: AppSizes.fontXxl,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (minPrice != maxPrice && _selectedPrice == 0) ...[
                const Text(' – ', style: TextStyle(color: AppColors.secondary, fontSize: AppSizes.fontLg)),
                Text(
                  _formatPrice(maxPrice),
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: AppSizes.fontLg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSizes.xs),
          Text(
            product.name,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppSizes.fontLg,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
          if (product.category != null) ...[
            const SizedBox(height: AppSizes.xs),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              ),
              child: Text(
                product.category!.name,
                style: const TextStyle(
                  color: AppColors.primary,
                  fontSize: AppSizes.fontXs,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantsSection(ProductModel product) {
    if (product.variants.isEmpty) return const SizedBox.shrink();
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Phân loại',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppSizes.fontMd,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Wrap(
            spacing: AppSizes.sm,
            runSpacing: AppSizes.sm,
            children: List.generate(product.variants.length, (i) {
              final v = product.variants[i];
              final selected = _selectedVariantIndex == i;
              return GestureDetector(
                onTap: () {
                  setState(() { _selectedVariantIndex = i; _currentImagePage = 0; });
                  _pageController.jumpToPage(0);
                  AppLogger.logUserEvent(
                    action: 'select_variant',
                    context: _tag,
                    metadata: {'productId': product.id, 'variantId': v.id},
                  );
                },
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.md, vertical: AppSizes.sm),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primaryContainer : AppColors.surface,
                    border: Border.all(
                      color: selected ? AppColors.primary : AppColors.divider,
                      width: selected ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                  ),
                  child: Text(
                    v.name,
                    style: TextStyle(
                      color: selected ? AppColors.primary : AppColors.textPrimary,
                      fontSize: AppSizes.fontSm,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }),
          ),
          if (_selectedStock > 0) ...[
            const SizedBox(height: AppSizes.sm),
            Text(
              'Còn lại: $_selectedStock sản phẩm',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppSizes.fontXs,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuantitySection() {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md, vertical: AppSizes.sm),
      child: Row(
        children: [
          const Text(
            'Số lượng',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppSizes.fontMd,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          _QuantityControl(
            value: _quantity,
            max: _selectedStock > 0 ? _selectedStock : 99,
            onChange: (v) => setState(() => _quantity = v),
          ),
        ],
      ),
    );
  }

  Widget _buildShopSection() {
    if (_loadingShop) {
      return Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(AppSizes.md),
        child: const Center(child: SizedBox(
          height: 60,
          child: CircularProgressIndicator(strokeWidth: 2),
        )),
      );
    }

    final shop = _shop;
    if (shop == null) {
      return Container(
        color: AppColors.surface,
        padding: const EdgeInsets.all(AppSizes.md),
        child: Row(
          children: [
            const Icon(Icons.store_outlined, color: AppColors.textHint),
            const SizedBox(width: AppSizes.sm),
            Text(
              _product?.shopName ?? 'Cửa hàng',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: AppSizes.fontMd,
              ),
            ),
          ],
        ),
      );
    }

    final avatarUrl = shop.avatarUrl ?? shop.logoUrl;

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        children: [
          Row(
            children: [
              // Avatar
              ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.avatarLg / 2),
                child: avatarUrl != null
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl,
                        width: AppSizes.avatarLg,
                        height: AppSizes.avatarLg,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            _shopAvatarFallback(shop.name),
                      )
                    : _shopAvatarFallback(shop.name),
              ),
              const SizedBox(width: AppSizes.md),
              // Name + status
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            shop.name,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: AppSizes.fontMd,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (shop.isVerified) ...[
                          const SizedBox(width: AppSizes.xs),
                          const Icon(Icons.verified,
                              size: 16, color: AppColors.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: AppColors.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          'Đang hoạt động',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: AppSizes.fontXs,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Follow button
              FollowButton(shop: shop, compact: true),
            ],
          ),
          const SizedBox(height: AppSizes.md),
          // Stats row
          IntrinsicHeight(
            child: Row(
              children: [
                _shopStat(
                  label: 'Đánh giá',
                  value: shop.rating > 0
                      ? shop.rating.toStringAsFixed(1)
                      : '–',
                  icon: Icons.star_rounded,
                  iconColor: AppColors.gold,
                ),
                const VerticalDivider(color: AppColors.divider, width: 1),
                _shopStat(
                  label: 'Đã bán',
                  value: _formatCount(shop.totalSales),
                ),
                const VerticalDivider(color: AppColors.divider, width: 1),
                _shopStat(
                  label: 'Theo dõi',
                  value: _formatCount(shop.followerCount),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.md),
          // Xem shop button
          OutlinedButton.icon(
            onPressed: () {
              AppLogger.logUserEvent(
                action: 'view_shop',
                context: _tag,
                metadata: {'shopId': shop.id, 'shopSlug': shop.slug},
              );
              // TODO: navigate to ShopScreen when it exists
            },
            icon: const Icon(Icons.store_outlined, size: 16),
            label: const Text('Xem Shop'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              minimumSize: const Size(double.infinity, 40),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shopAvatarFallback(String name) {
    return Container(
      width: AppSizes.avatarLg,
      height: AppSizes.avatarLg,
      color: AppColors.primaryContainer,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : 'S',
          style: const TextStyle(
            color: AppColors.primary,
            fontSize: AppSizes.fontXl,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _shopStat({
    required String label,
    required String value,
    IconData? icon,
    Color? iconColor,
  }) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null)
                Icon(icon, size: 14, color: iconColor ?? AppColors.textSecondary),
              if (icon != null) const SizedBox(width: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: AppSizes.fontMd,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppSizes.fontXs,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDescriptionSection(ProductModel product) {
    if (product.description == null || product.description!.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.all(AppSizes.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Mô tả sản phẩm',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: AppSizes.fontMd,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSizes.sm),
          Text(
            product.description!,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppSizes.fontMd,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ProductModel product) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: EdgeInsets.only(
        left: AppSizes.md,
        right: AppSizes.md,
        top: AppSizes.sm,
        bottom: AppSizes.sm + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _selectedStock == 0
                  ? null
                  : () {
                      AppLogger.logUserEvent(
                        action: 'add_to_cart',
                        context: _tag,
                        metadata: {
                          'productId': product.id,
                          'variantIndex': _selectedVariantIndex,
                          'quantity': _quantity,
                        },
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text(AppStrings.notifAddedToCart)),
                      );
                    },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
              ),
              child: const Text(AppStrings.productAddToCart,
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: AppSizes.sm),
          Expanded(
            child: ElevatedButton(
              onPressed: _selectedStock == 0
                  ? null
                  : () {
                      AppLogger.logUserEvent(
                        action: 'buy_now',
                        context: _tag,
                        metadata: {
                          'productId': product.id,
                          'variantIndex': _selectedVariantIndex,
                          'quantity': _quantity,
                        },
                      );
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
              ),
              child: Text(
                _selectedStock == 0 ? 'Hết hàng' : AppStrings.productBuyNow,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPrice(int price) {
    if (price <= 0) return '–';
    final str = price.toString();
    final buffer = StringBuffer();
    final offset = str.length % 3;
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (i - offset) % 3 == 0) buffer.write('.');
      buffer.write(str[i]);
    }
    return '$bufferđ';
  }

  String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}k';
    return n.toString();
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.value,
    required this.max,
    required this.onChange,
  });

  final int value;
  final int max;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _btn(
          icon: Icons.remove,
          onTap: value > 1 ? () => onChange(value - 1) : null,
        ),
        Container(
          width: 40,
          alignment: Alignment.center,
          child: Text(
            '$value',
            style: const TextStyle(
              fontSize: AppSizes.fontMd,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        _btn(
          icon: Icons.add,
          onTap: value < max ? () => onChange(value + 1) : null,
        ),
      ],
    );
  }

  Widget _btn({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: onTap != null ? AppColors.primaryContainer : AppColors.background,
          borderRadius: BorderRadius.circular(AppSizes.radiusSm),
          border: Border.all(
            color: onTap != null ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Icon(
          icon,
          size: 16,
          color: onTap != null ? AppColors.primary : AppColors.textHint,
        ),
      ),
    );
  }
}
