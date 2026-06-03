import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/core/utils/dashboard_controller.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/domain/repositories/cart_repository_impl.dart';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/cart_badge_controller.dart';
import 'package:tropia_mobile_app_android/features/user/dashboard/presentation/dashboard_page.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../data/datasources/home_remote_datasource.dart';
import '../../data/models/product_detail_model.dart';
import '../../data/models/product_model.dart';
import '../widgets/product_variant_sheet.dart';
import 'search_page.dart';

class ProductDetailPage extends StatefulWidget {
  final ProductModel product;
  final bool isFlashSale;

  const ProductDetailPage({
    super.key,
    required this.product,
    this.isFlashSale = false,
  });

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  int _currentImageIndex = 0;

  late List<String> _images;
  String _description = '';
  Future<ProductDetailModel?>? _detailFuture;

  // --- State cho nut mua ---
  int _quantity = 0;
  bool _isAddingToCart = false;
  bool? _hasOptions;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    final mainImage = widget.product.image.trim();
    if (mainImage.isEmpty || mainImage == '0') {
      _images = [];
    } else {
      _images = [mainImage];
    }

    _detailFuture = _fetchProductDetail();
    _detailFuture!.then((detail) {
      if (!mounted || detail == null) return;
      setState(() {
        if (detail.images.isNotEmpty) {
          _images = detail.images;
          _currentImageIndex = 0;
        }
        _description = detail.description.trim();
        _hasOptions = detail.hasOptions && detail.options.isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<ProductDetailModel?> _fetchProductDetail() {
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    return dataSource.getProductDetail(id: widget.product.id);
  }

  bool _hasValidMedia(String? value) {
    if (value == null) return false;
    final v = value.trim();
    return v.isNotEmpty && v != '0';
  }

  // --- Xu ly nut MUA ---

  Future<void> _onBuyPressed() async {
    if (_isAddingToCart) return;
    setState(() => _isAddingToCart = true);

    try {
      if (_hasOptions == null) {
        final dio = DioClient().dio;
        final dataSource = HomeRemoteDataSourceImpl(client: dio);
        final detail = await dataSource.getProductDetail(id: widget.product.id);
        _hasOptions =
            (detail != null && detail.hasOptions && detail.options.isNotEmpty);
      }

      if (!mounted) return;

      if (_hasOptions == true) {
        setState(() => _isAddingToCart = false);
        if (!mounted) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) => ProductVariantSheet(product: widget.product),
        );
      } else {
        await _addToCartDirectly();
        if (mounted) setState(() => _isAddingToCart = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAddingToCart = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Lỗi: $e"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }
    }
  }

  Future<void> _addToCartDirectly() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null || userId == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Vui lòng đăng nhập để mua hàng"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.fixed,
          ),
        );
      }
      return;
    }

    final dio = DioClient().dio;
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
      setState(() => _quantity = 1);
      unawaited(CartBadgeController.instance.syncFromApi());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Đã thêm vào giỏ hàng thành công!"),
          backgroundColor: Color(0xFF388E3C),
          behavior: SnackBarBehavior.fixed,
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.fixed,
        ),
      );
    }
  }

  void _onAdd() {
    setState(() => _quantity++);
    _debouncedUpdateCart();
  }

  void _onRemove() {
    if (_quantity <= 0) return;
    setState(() => _quantity--);
    _debouncedUpdateCart();
  }

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

      await cartRepo.updateCart(userId, widget.product.id, _quantity);
      unawaited(CartBadgeController.instance.syncFromApi());
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool showFlashSaleBanner =
        widget.isFlashSale &&
        widget.product.discount.isNotEmpty &&
        widget.product.originalPrice > widget.product.salePrice;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.white,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
        systemNavigationBarDividerColor: Colors.transparent,
      ),
      child: Scaffold(
        backgroundColor: AppColors.white,
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          backgroundColor: AppColors.primary,
          mini: true,
          child: const Icon(
            Icons.chat_bubble_outline,
            color: Colors.white,
            size: 20,
          ),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
        bottomNavigationBar: _buildBottomBar(),
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildImageSlider(),
                    if (showFlashSaleBanner) _buildFlashSaleBanner(),
                    _buildProductInfo(),
                    if (_description.isNotEmpty) _buildDescription(),
                    _buildUpsellSection(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- HEADER ---
  Widget _buildHeader() {
    final double paddingTop = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, paddingTop + 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(50),
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.arrow_back_ios, size: 22, color: Colors.black),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const SearchPage(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                    transitionDuration: const Duration(milliseconds: 500),
                  ),
                );
              },
              child: Hero(
                tag: 'search_bar_tag',
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F3F3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const TextField(
                      enabled: false,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        hintText: "Bạn muốn mua gì?",
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: Colors.black),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                        isDense: true,
                        fillColor: Colors.transparent,
                        filled: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          ValueListenableBuilder<int>(
            valueListenable: CartBadgeController.instance.count,
            builder: (context, count, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.of(context).popUntil((route) => route.isFirst);
                      DashboardController.switchTab(DashboardPage.tabCart);
                    },
                    borderRadius: BorderRadius.circular(50),
                    child: const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Icon(
                        Icons.shopping_cart_outlined,
                        color: Colors.black,
                        size: 26,
                      ),
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // --- BOTTOM BAR ---
  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: SizedBox(
          height: 48,
          child: _quantity > 0
              ? _buildQuantityBar()
              : ElevatedButton(
                  onPressed: _isAddingToCart ? null : _onBuyPressed,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    elevation: 0,
                  ),
                  child: _isAddingToCart
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          "MUA",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
        ),
      ),
    );
  }

  Widget _buildQuantityBar() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildQtyButton(Icons.remove, _onRemove, isAdd: false),
          Expanded(
            child: Text(
              "$_quantity",
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          _buildQtyButton(Icons.add, _onAdd, isAdd: true),
        ],
      ),
    );
  }

  Widget _buildQtyButton(
    IconData icon,
    VoidCallback onTap, {
    required bool isAdd,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: isAdd ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Icon(icon, size: 22, color: isAdd ? Colors.white : Colors.grey),
      ),
    );
  }

  // --- UI BUILDERS ---

  Widget _buildDescription() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.white,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Mô tả sản phẩm',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _description,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageSlider() {
    if (_images.isEmpty) {
      return Container(
        height: 300,
        width: double.infinity,
        color: AppColors.background,
        child: const Center(
          child: Icon(Icons.image, size: 80, color: Colors.grey),
        ),
      );
    }

    return Stack(
      children: [
        SizedBox(
          height: 300,
          width: double.infinity,
          child: PageView.builder(
            onPageChanged: (index) {
              setState(() {
                _currentImageIndex = index;
              });
            },
            itemCount: _images.length,
            itemBuilder: (context, index) {
              final img = _images[index];
              bool isNetwork = img.startsWith('http');
              return Container(
                color: AppColors.white,
                child: isNetwork
                    ? Image.network(
                        img,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                              child: Icon(
                                Icons.broken_image,
                                size: 50,
                                color: Colors.grey,
                              ),
                            ),
                      )
                    : Image.asset(
                        img,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) =>
                            const Center(
                              child: Icon(
                                Icons.image,
                                size: 50,
                                color: Colors.grey,
                              ),
                            ),
                      ),
              );
            },
          ),
        ),
        if (_images.length > 1)
          Positioned(
            bottom: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                "${_currentImageIndex + 1}/${_images.length}",
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildFlashSaleBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.accentLight, AppColors.accent],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.flash_on,
                    color: AppColors.redSale,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    "FLASH SALE",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: AppColors.redSale,
                    ),
                  ),
                  if (_hasValidMedia(widget.product.discount)) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.redSale,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        widget.product.discount,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (widget.product.sold > 0)
                Text(
                  "${widget.product.sold} khách đã đặt",
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProductInfo() {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'Đ');

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.product.name,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currencyFormat.format(widget.product.salePrice),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (widget.product.originalPrice > widget.product.salePrice)
                    Row(
                      children: [
                        Text(
                          currencyFormat.format(widget.product.originalPrice),
                          style: const TextStyle(
                            fontSize: 14,
                            decoration: TextDecoration.lineThrough,
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (widget.product.discount.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.redSale,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.flash_on,
                                  size: 10,
                                  color: Colors.white,
                                ),
                                Text(
                                  widget.product.discount,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                ],
              ),
              InkWell(
                onTap: () {},
                child: Row(
                  children: const [
                    Icon(Icons.link, size: 18, color: AppColors.blueLink),
                    SizedBox(width: 4),
                    Text(
                      "Link chia sẻ",
                      style: TextStyle(color: AppColors.blueLink, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildUpsellSection() {
    return const SizedBox.shrink();
  }
}
