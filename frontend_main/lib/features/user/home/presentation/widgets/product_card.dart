import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Thư viện format tiền
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/domain/repositories/cart_repository_impl.dart';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/cart_badge_controller.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import '../../data/models/product_model.dart'; // Import Model
import '../pages/product_detail_page.dart';
import 'product_variant_sheet.dart';
import '../../../../../core/constants/app_colors.dart';
import 'product_tile_card.dart';

class ProductCard extends StatefulWidget {
  final ProductModel product;
  final bool isFlashSale;
  final int? quantity;
  final VoidCallback? onAdd;
  final VoidCallback? onRemove;

  const ProductCard({
    super.key,
    required this.product,
    required this.isFlashSale,
    this.quantity,
    this.onAdd,
    this.onRemove,
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  // --- State nội bộ cho sản phẩm không có option ---
  int _internalQuantity = 0;
  bool _isLoading = false;
  bool? _hasOptions; // null = chưa kiểm tra
  Timer? _debounce;

  /// true nếu widget cha KHÔNG quản lý quantity (hầu hết các màn)
  bool get _useSelfManaged =>
      widget.quantity == null &&
      widget.onAdd == null &&
      widget.onRemove == null;

  /// Số lượng hiển thị thực tế
  int get _effectiveQuantity =>
      _useSelfManaged ? _internalQuantity : (widget.quantity ?? 0);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  // --- Helpers ---

  bool _showDiscountBadge(ProductModel product, int qty) {
    if (qty > 0) return false;
    if (product.discount.isEmpty) return false;
    if (product.discount == '0' ||
        product.discount == '0.0' ||
        product.discount == '0%') {
      return false;
    }
    return true;
  }

  String _getDiscountText(ProductModel product) {
    final value = product.discount.toString();
    if (value.isNotEmpty && RegExp(r'^\d+ ?$').hasMatch(value)) {
      return '$value%';
    }
    return value;
  }

  // --- Xử lý nhấn nút CHỌN MUA ---

  Future<void> _onBuyPressed() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      // 1. Kiểm tra sản phẩm có option không (cache kết quả)
      if (_hasOptions == null) {
        final dio = DioClient().dio;
        final dataSource = HomeRemoteDataSourceImpl(client: dio);
        final detail = await dataSource.getProductDetail(id: widget.product.id);
        _hasOptions =
            (detail != null && detail.hasOptions && detail.options.isNotEmpty);
      }

      if (!mounted) return;

      if (_hasOptions == true) {
        // --- CÓ OPTION  mở VariantSheet như cũ ---
        setState(() => _isLoading = false);
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => ProductVariantSheet(product: widget.product),
        );
      } else {
        // --- KHÔNG CÓ OPTION  thêm thẳng vào giỏ ---
        await _addToCartDirectly();
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Lỗi: $e"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// Thêm 1 sản phẩm vào giỏ hàng (lần đầu, không option)
  Future<void> _addToCartDirectly() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null || userId == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Vui lòng đăng nhập để mua hàng"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final dio = DioClient().dio;

    // Authenticate
    final appAuthRepo = AppAuthRepository(
      remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
    );
    await appAuthRepo.authenticateApp();

    final cartRepo = CartRepositoryImpl(
      remoteDataSource: CartRemoteDataSourceImpl(client: dio),
    );

    final result = await cartRepo.addToCart(userId, widget.product.id, 1);

    if (!mounted) return;

    if (result == "SUCCESS") {
      setState(() => _internalQuantity = 1);
      unawaited(CartBadgeController.instance.syncFromApi());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Đã thêm vào giỏ hàng thành công!"),
          backgroundColor: Color(0xFF388E3C),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // --- Tăng / giảm số lượng nội bộ (debounce API) ---

  void _onInternalAdd() {
    setState(() => _internalQuantity++);
    _debouncedUpdateCart();
  }

  void _onInternalRemove() {
    if (_internalQuantity <= 0) return;
    setState(() => _internalQuantity--);
    _debouncedUpdateCart();
  }

  /// Debounce 800ms để gom nhiều lần nhấn liên tiếp thành 1 API call
  void _debouncedUpdateCart() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 800), () async {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      if (userId == null || userId == 0) return;

      final dio = DioClient().dio;
      final cartRepo = CartRepositoryImpl(
        remoteDataSource: CartRemoteDataSourceImpl(client: dio),
      );

      await cartRepo.updateCart(userId, widget.product.id, _internalQuantity);

      unawaited(CartBadgeController.instance.syncFromApi());
    });
  }

  // --- BUILD ---

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
    final qty = _effectiveQuantity;

    return ProductTileCard(
      image: widget.product.image,
      title: widget.product.name,
      onTap: () {
        FocusScope.of(context).unfocus();
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ProductDetailPage(
            product: widget.product,
            isFlashSale: widget.isFlashSale,
          ),
          ),
        );
      },
      imageOverlay: _showDiscountBadge(widget.product, qty)
          ? Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.redSale,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _getDiscountText(widget.product),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          : null,
      price: Text(
        currencyFormat.format(widget.product.salePrice),
        style: const TextStyle(
          color: AppColors.accent,
          fontWeight: FontWeight.bold,
          fontSize: 14,
        ),
      ),
      originalPrice:
          (widget.product.originalPrice > widget.product.salePrice)
          ? Text(
              currencyFormat.format(widget.product.originalPrice),
              style: const TextStyle(
                color: Colors.grey,
                fontSize: 11,
                decoration: TextDecoration.lineThrough,
              ),
            )
          : null,
      action: _buildActionButtons(context),
    );
  }

  Widget _buildLowStockBanner() {
    final stock = widget.product.stock;
    if (stock <= 0 || stock >= 20) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.inventory_2_outlined, size: 12, color: Color(0xFFE65100)),
          const SizedBox(width: 4),
          Text(
            'Còn $stock sản phẩm',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Color(0xFFE65100),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final qty = _effectiveQuantity;

    // --- Hiển thị thanh +/- khi đã có quantity ---
    if (qty > 0) {
      final VoidCallback? removeCb = _useSelfManaged
          ? _onInternalRemove
          : widget.onRemove;
      final VoidCallback? addCb = _useSelfManaged
          ? _onInternalAdd
          : widget.onAdd;

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLowStockBanner(),
          Container(
            height: 32,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade200),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _buildQtyIcon(Icons.remove, removeCb),
                Expanded(
                  child: Text(
                    "$qty",
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
                _buildQtyIcon(Icons.add, addCb, isAdd: true),
              ],
            ),
          ),
        ],
      );
    }

    // --- Hết hàng ---
    if (widget.product.isOutOfStock) {
      return SizedBox(
        width: double.infinity,
        height: 32,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Center(
            child: Text(
              "Tạm hết hàng",
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }

    // --- Nút CHỌN MUA ---
    Widget buyButton = SizedBox(
      width: double.infinity,
      height: 32,
      child: ElevatedButton(
        onPressed: _isLoading
            ? null
            : () {
                if (_useSelfManaged) {
                  // Tự quản lý: kiểm tra option rồi quyết định
                  _onBuyPressed();
                } else {
                  // Widget cha quản lý (ComboDetailSheet): mở sheet như cũ
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (ctx) =>
                        ProductVariantSheet(product: widget.product),
                  ).then((result) {
                    if (result != null && widget.onAdd != null) {
                      widget.onAdd!();
                    }
                  });
                }
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.background,
          foregroundColor: AppColors.accent,
          padding: EdgeInsets.zero,
          elevation: 0,
          side: const BorderSide(color: AppColors.accent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: _isLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text(
                "CHỌN MUA",
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
      ),
    );

    if (widget.isFlashSale) {
      final totalSlots = widget.product.discountSlotsTotal;
      final leftSlots = widget.product.discountSlotsLeft;

      int? soldSlots;
      if (totalSlots != null && leftSlots != null) {
        final raw = totalSlots - leftSlots;
        soldSlots = raw.clamp(0, totalSlots);
      }

      final progress =
          (totalSlots != null && totalSlots > 0 && soldSlots != null)
          ? (soldSlots / totalSlots)
          : 0.0;

      final soldPart = (totalSlots != null && soldSlots != null)
          ? "Đã bán $soldSlots/$totalSlots"
          : "Đã bán ${widget.product.sold}";

      final remainingPart = (leftSlots != null)
          ? (totalSlots != null
                ? "Còn $leftSlots/$totalSlots"
                : "Còn $leftSlots")
          : null;

      final displayText = remainingPart == null
          ? soldPart
          : "$soldPart  $remainingPart";

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildLowStockBanner(),
          Container(
            height: 16,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.accentLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Stack(
              children: [
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        displayText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(color: Colors.black26, blurRadius: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  left: 4,
                  top: 2,
                  bottom: 2,
                  child: Icon(
                    Icons.local_fire_department,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          buyButton,
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildLowStockBanner(),
        buyButton,
      ],
    );
  }

  Widget _buildQtyIcon(
    IconData icon,
    VoidCallback? onTap, {
    bool isAdd = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isAdd ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 16, color: isAdd ? Colors.white : Colors.grey),
      ),
    );
  }
}
