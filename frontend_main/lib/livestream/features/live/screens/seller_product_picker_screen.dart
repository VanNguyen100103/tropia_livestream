// =============================================================================
// seller_product_picker_screen.dart – Shopee-style product picker
// =============================================================================
// AppBar: "Thêm sản phẩm liên quan"
// Tabs: "Shop của tôi (N)" | "Gần đây"
// Sort chips: Phổ biến / Mới nhất / Bán chạy / Giá↕
// Product rows: radio-circle select (left), image, name+sold+price, delete icon
// Bottom: "Chọn tất cả" (left) + "Thêm" orange button (right)
// =============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tropia_mobile_app_android/livestream/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/livestream/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/models/live_stream_model.dart';
import 'package:tropia_mobile_app_android/livestream/features/product/data/product_repository.dart';
import 'package:tropia_mobile_app_android/livestream/features/product/models/product_model.dart';

class SellerProductPickerScreen extends StatefulWidget {
  final List<LiveProduct> alreadySelected;

  const SellerProductPickerScreen({
    super.key,
    this.alreadySelected = const [],
  });

  @override
  State<SellerProductPickerScreen> createState() =>
      _SellerProductPickerScreenState();
}

class _SellerProductPickerScreenState
    extends State<SellerProductPickerScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  late final Set<String> _selectedIds;
  late TabController _tabController;

  // Sort options
  static const _sortOptions = ['Phổ biến', 'Mới nhất', 'Bán chạy', 'Giá'];
  String _activeSort = 'Phổ biến';
  bool _priceSortAsc = true;

  List<ProductModel> _myProducts = [];
  List<ProductModel> _recentProducts = [];
  // Products created on-the-spot (not fetched from server)
  final List<LiveProduct> _createdProducts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _selectedIds = widget.alreadySelected.map((p) => p.id).toSet();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
    _loadProducts();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await ProductRepository.instance.getSellerProducts(limit: 100);
      setState(() {
        _myProducts = result.items;
        // "Gần đây" = first 10 items returned from API
        _recentProducts = result.items.take(10).toList();
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.logError('SellerProductPicker', 'Load products failed', e, st);
      setState(() { _loading = false; _error = 'Không tải được sản phẩm. Thử lại.\n$e'; });
    }
  }

  // ─── Filtering & sorting ──────────────────────────────────────────────────────

  List<ProductModel> get _activeList =>
      _tabController.index == 0 ? _myProducts : _recentProducts;

  List<ProductModel> get _filtered {
    var list = _activeList;
    if (_searchQuery.isNotEmpty) {
      list = list
          .where((p) => p.name.toLowerCase().contains(_searchQuery))
          .toList();
    }
    list = List.from(list);
    switch (_activeSort) {
      case 'Bán chạy':
        // No soldCount on ProductModel; keep original order (API returns best-sellers first)
        break;
      case 'Mới nhất':
        // No createdAt on ProductModel; reverse to surface newest
        list = list.reversed.toList();
      case 'Giá':
        list.sort((a, b) {
          final cmp = a.basePrice.compareTo(b.basePrice);
          return _priceSortAsc ? cmp : -cmp;
        });
      default:
        break;
    }
    return list;
  }

  // ─── Selection helpers ────────────────────────────────────────────────────────

  void _toggle(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        if (_selectedIds.length >= 20) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tối đa 20 sản phẩm mỗi buổi live')),
          );
          return;
        }
        _selectedIds.add(id);
      }
    });
  }

  void _toggleSelectAll() {
    final visibleIds = _filtered.map((p) => p.id).toSet();
    final allSelected = visibleIds.every(_selectedIds.contains);
    setState(() {
      if (allSelected) {
        _selectedIds.removeAll(visibleIds);
      } else {
        final remaining = 20 - _selectedIds.length;
        final toAdd = visibleIds.difference(_selectedIds).take(remaining);
        _selectedIds.addAll(toAdd);
      }
    });
  }

  bool get _allVisibleSelected {
    final ids = _filtered.map((p) => p.id).toSet();
    return ids.isNotEmpty && ids.every(_selectedIds.contains);
  }

  List<LiveProduct> get _selectedLiveProducts {
    final seen = <String>{};
    final fromServer = [..._myProducts, ..._recentProducts]
        .where((p) => _selectedIds.contains(p.id) && seen.add(p.id))
        .map(_toLiveProduct)
        .toList();
    final fromCreated = _createdProducts.where((p) => _selectedIds.contains(p.id)).toList();
    return [...fromServer, ...fromCreated];
  }

  void _confirm() {
    Navigator.pop(context, _selectedLiveProducts);
  }

  LiveProduct _toLiveProduct(ProductModel p) {
    final variants = p.variants;
    final skus = variants.map((v) => ProductSku(
      skuId: v.id,
      selections: v.attributes.map((k, val) => MapEntry(k.toString(), val.toString())),
      originalPrice: v.price.toDouble(),
      salePrice: v.price.toDouble(),
      stockLeft: v.stock,
      imageUrl: v.images.isNotEmpty ? v.images.first : null,
    )).toList();

    return LiveProduct(
      id: p.id,
      productId: p.id,
      name: p.name,
      imageUrl: p.thumbnail ?? AppUrls.placeholderProduct,
      originalPrice: p.basePrice.toDouble(),
      salePrice: p.basePrice.toDouble(),
      discountPercent: 0,
      stockLeft: variants.isNotEmpty
          ? variants.fold(0, (s, v) => s + v.stock)
          : p.totalStock,
      soldCount: 0,
      unit: 'cái',
      category: p.category?.name ?? '',
      skus: skus,
    );
  }

  String _fmtPrice(double price) {
    if (price >= 1000000) return '${(price / 1000000).toStringAsFixed(1)}tr';
    if (price >= 1000) return '${(price / 1000).toInt()}K';
    return '${price.toInt()}';
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildTabBar(),
          _buildSortChips(),
          const Divider(height: 1),
          Expanded(child: _buildProductList()),
          _buildBottomBar(),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Thêm sản phẩm liên quan'),
      backgroundColor: Colors.white,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.divider),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.xs),
      child: TextField(
        controller: _searchCtrl,
        decoration: InputDecoration(
          hintText: 'Tìm sản phẩm...',
          hintStyle: const TextStyle(color: AppColors.textHint, fontSize: AppSizes.fontSm),
          prefixIcon: const Icon(Icons.search, color: AppColors.textHint, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18, color: AppColors.textHint),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: AppColors.surfaceVariant,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.radiusFull),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        onTap: (_) => setState(() {}),
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: AppSizes.fontSm),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w400, fontSize: AppSizes.fontSm),
        indicatorColor: AppColors.primary,
        indicatorWeight: 2,
        tabs: [
          Tab(text: 'Shop của tôi (${_myProducts.length})'),
          const Tab(text: 'Gần đây'),
        ],
      ),
    );
  }

  Widget _buildSortChips() {
    return Container(
      color: Colors.white,
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: 6),
        itemCount: _sortOptions.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSizes.xs),
        itemBuilder: (_, i) {
          final label = _sortOptions[i];
          final isActive = label == _activeSort;
          return GestureDetector(
            onTap: () {
              setState(() {
                if (label == 'Giá' && _activeSort == 'Giá') {
                  _priceSortAsc = !_priceSortAsc;
                } else {
                  _activeSort = label;
                }
              });
            },
            child: AnimatedContainer(
              duration: AppDurations.fast,
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 4),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primaryContainer : AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                border: Border.all(
                  color: isActive ? AppColors.primary : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: AppSizes.fontXs,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                      color: isActive ? AppColors.primary : AppColors.textSecondary,
                    ),
                  ),
                  if (label == 'Giá') ...[
                    const SizedBox(width: 2),
                    Icon(
                      _activeSort == 'Giá' && !_priceSortAsc
                          ? Icons.arrow_downward
                          : Icons.arrow_upward,
                      size: 12,
                      color: isActive ? AppColors.primary : AppColors.textHint,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProductList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null && _createdProducts.isEmpty) return _buildError();
    final list = _error != null ? <ProductModel>[] : _filtered;
    final created = _createdProducts;
    // Total: create-button + created products + server products
    final totalCount = 1 + created.length + list.length;
    return RefreshIndicator(
      onRefresh: _loadProducts,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
        itemCount: totalCount,
        separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
        itemBuilder: (_, i) {
          if (i == 0) return _buildCreateProductButton();
          // Created products come first (after the button)
          if (i <= created.length) {
            final lp = created[i - 1];
            return _ProductPickerRow(
              product: lp,
              isSelected: _selectedIds.contains(lp.id),
              onTap: () => _toggle(lp.id),
              formatPrice: _fmtPrice,
            );
          }
          final p = list[i - 1 - created.length];
          final lp = _toLiveProduct(p);
          return _ProductPickerRow(
            product: lp,
            isSelected: _selectedIds.contains(p.id),
            onTap: () => _toggle(p.id),
            formatPrice: _fmtPrice,
          );
        },
      ),
    );
  }

  Widget _buildCreateProductButton() {
    return GestureDetector(
      onTap: _showCreateProductDialog,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
        child: Row(
          children: [
            Container(
              width: 46, height: 46,
              decoration: BoxDecoration(
                color: AppColors.primaryContainer,
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1.5),
              ),
              child: const Icon(Icons.add, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: AppSizes.sm),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tạo sản phẩm mới',
                    style: TextStyle(
                      fontSize: AppSizes.fontMd,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  Text(
                    'Thêm sản phẩm chưa có trong shop',
                    style: TextStyle(
                      fontSize: AppSizes.fontXs,
                      color: AppColors.textHint,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateProductDialog() async {
    final newProduct = await showDialog<LiveProduct>(
      context: context,
      builder: (_) => const _QuickCreateProductDialog(),
    );
    if (newProduct != null && mounted) {
      setState(() {
        _createdProducts.add(newProduct);
        _selectedIds.add(newProduct.id);
      });
    }
  }

  Widget _buildBottomBar() {
    final selectedCount = _selectedIds.length;
    final allSelected = _allVisibleSelected;

    return Container(
      // Scaffold(resizeToAvoidBottomInset: true) already shrinks the body
      // when the keyboard opens, so we MUST NOT add viewInsets.bottom here
      // — that would double-count the keyboard and overflow the Column.
      // We only need padding.bottom (gesture nav bar / home indicator).
      padding: EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.md,
        AppSizes.sm + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Row(
        children: [
          // Chọn tất cả
          GestureDetector(
            onTap: _toggleSelectAll,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: AppDurations.fast,
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: allSelected ? AppColors.primary : Colors.white,
                    border: Border.all(
                      color: allSelected ? AppColors.primary : AppColors.divider,
                      width: 2,
                    ),
                  ),
                  child: allSelected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
                const SizedBox(width: 6),
                const Text('Chọn tất cả',
                  style: TextStyle(fontSize: AppSizes.fontSm, color: AppColors.textSecondary)),
              ],
            ),
          ),

          const Spacer(),

          // Thêm button
          SizedBox(
            height: 44,
            child: ElevatedButton(
              onPressed: selectedCount > 0 ? _confirm : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                disabledBackgroundColor: AppColors.surfaceVariant,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppSizes.lg),
                elevation: 0,
              ),
              child: Text(
                selectedCount > 0 ? 'Thêm ($selectedCount)' : 'Thêm',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: AppSizes.fontMd),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: AppColors.error),
          const SizedBox(height: AppSizes.sm),
          Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: AppSizes.md),
          TextButton.icon(
            onPressed: _loadProducts,
            icon: const Icon(Icons.refresh),
            label: const Text('Thử lại'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product row – radio-circle on left, image, info, remove icon
// ─────────────────────────────────────────────────────────────────────────────

class _ProductPickerRow extends StatelessWidget {
  final LiveProduct product;
  final bool isSelected;
  final VoidCallback onTap;
  final String Function(double) formatPrice;

  const _ProductPickerRow({
    required this.product,
    required this.isSelected,
    required this.onTap,
    required this.formatPrice,
  });

  // Render local file hoặc network URL
  Widget _buildProductImage(String url, double size) {
    final isLocal = !url.startsWith('http');
    if (isLocal) {
      return Image.file(
        File(url),
        width: size, height: size, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size, height: size, color: AppColors.surfaceVariant,
          child: const Icon(Icons.broken_image_outlined, color: AppColors.textHint, size: 24),
        ),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      width: size, height: size, fit: BoxFit.cover,
      placeholder: (_, __) => Container(
        width: size, height: size, color: AppColors.surfaceVariant,
        child: const Icon(Icons.image_outlined, color: AppColors.textHint, size: 24),
      ),
      errorWidget: (_, __, ___) => Container(
        width: size, height: size, color: AppColors.surfaceVariant,
        child: const Icon(Icons.broken_image_outlined, color: AppColors.textHint, size: 24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSizes.md, vertical: AppSizes.sm),
        child: Row(
          children: [
            // Radio circle (left)
            AnimatedContainer(
              duration: AppDurations.fast,
              width: 22, height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppColors.primary : Colors.white,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.divider,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 14)
                  : null,
            ),

            const SizedBox(width: AppSizes.sm),

            // Product image — hỗ trợ cả local file (tạo mới) và network URL
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              child: _buildProductImage(product.imageUrl, 64),
            ),

            const SizedBox(width: AppSizes.sm),

            // Info
            Expanded(
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
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đã bán ${product.soldCount}',
                    style: const TextStyle(
                      fontSize: AppSizes.fontXs,
                      color: AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '${formatPrice(product.salePrice)}đ',
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppSizes.fontSm,
                        ),
                      ),
                      if (product.originalPrice > product.salePrice) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${formatPrice(product.originalPrice)}đ',
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: AppSizes.fontXs,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Remove / reorder icon (visible when selected)
            if (isSelected) ...[
              const SizedBox(width: AppSizes.xs),
              GestureDetector(
                onTap: onTap,
                child: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick product creation dialog
// ─────────────────────────────────────────────────────────────────────────────

class _QuickCreateProductDialog extends StatefulWidget {
  const _QuickCreateProductDialog();

  @override
  State<_QuickCreateProductDialog> createState() => _QuickCreateProductDialogState();
}

class _QuickCreateProductDialogState extends State<_QuickCreateProductDialog> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  XFile? _pickedImage;
  bool _pickingImage = false;
  bool _submitting = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _pickingImage = true);
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 800,
      );
      if (file != null && mounted) {
        setState(() => _pickedImage = file);
      }
    } catch (e) {
      AppLogger.logError('QuickCreateProduct', 'Image pick failed', e, null);
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
      final stock = int.tryParse(_stockCtrl.text.trim()) ?? 0;
      final name  = _nameCtrl.text.trim();
      final desc  = _descCtrl.text.trim();

      // 1. Upload ảnh nếu có
      String? imageUrl;
      if (_pickedImage != null) {
        imageUrl = await ProductRepository.instance.uploadTempImage(
          File(_pickedImage!.path),
        );
      }

      // 2. Tạo sản phẩm trên Supabase
      final product = await ProductRepository.instance.quickCreate(
        name:        name,
        description: desc.isEmpty ? null : desc,
        price:       price,
        stock:       stock,
        imageUrl:    imageUrl,
      );

      if (!mounted) return;
      Navigator.pop(
        context,
        LiveProduct(
          id:              product.id,
          productId:       product.id,
          name:            product.name,
          imageUrl:        product.thumbnail ?? imageUrl ?? AppUrls.placeholderProduct,
          originalPrice:   product.basePrice.toDouble(),
          salePrice:       product.basePrice.toDouble(),
          discountPercent: 0,
          stockLeft:       stock,
          soldCount:       0,
          unit:            'cái',
          category:        '',
          skus:            [],
        ),
      );
    } catch (e) {
      AppLogger.logError('QuickCreateProduct', 'Create failed', e, null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tạo sản phẩm thất bại: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Tạo sản phẩm mới',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
              // ── Image picker ──────────────────────────────────────────────
              GestureDetector(
                onTap: _pickingImage ? null : _pickImage,
                child: Container(
                  width: double.infinity,
                  height: 160,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    border: Border.all(
                      color: _pickedImage != null
                          ? AppColors.primary.withValues(alpha: 0.4)
                          : AppColors.divider,
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _pickedImage != null
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              File(_pickedImage!.path),
                              fit: BoxFit.cover,
                            ),
                            // Overlay tap to change
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                color: Colors.black.withValues(alpha: 0.45),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text(
                                      'Thay ảnh',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: AppSizes.fontXs,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _pickingImage
                                ? const CircularProgressIndicator()
                                : const Icon(
                                    Icons.add_photo_alternate_outlined,
                                    size: 40,
                                    color: AppColors.textHint,
                                  ),
                            const SizedBox(height: AppSizes.xs),
                            const Text(
                              'Chọn ảnh từ điện thoại',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: AppSizes.fontSm,
                              ),
                            ),
                            const Text(
                              'Nhấn để mở thư viện ảnh',
                              style: TextStyle(
                                color: AppColors.textHint,
                                fontSize: AppSizes.fontXs,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: AppSizes.sm),

              // ── Tên sản phẩm ──────────────────────────────────────────────
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Tên sản phẩm *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Vui lòng nhập tên';
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.sm),

              // ── Mô tả ─────────────────────────────────────────────────────
              TextFormField(
                controller: _descCtrl,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Mô tả sản phẩm',
                  border: OutlineInputBorder(),
                  isDense: true,
                  hintText: 'Xuất xứ, thành phần, đặc điểm...',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: AppSizes.sm),

              // ── Giá + tồn kho (2 cột) ─────────────────────────────────────
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá bán *',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixText: 'đ',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Nhập giá';
                        if (double.tryParse(v.trim()) == null) return 'Không hợp lệ';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: AppSizes.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _stockCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Tồn kho',
                        border: OutlineInputBorder(),
                        isDense: true,
                        hintText: '0',
                        suffixText: 'cái',
                      ),
                    ),
                  ),
                    ],
                  ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Huỷ'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      child: _submitting
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Tạo & Chọn'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
