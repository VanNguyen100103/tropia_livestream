import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/domain/repositories/cart_repository_impl.dart';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/cart_badge_controller.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/product_tile_card.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../data/models/product_model.dart';

class ProductVariantSheet extends StatefulWidget {
  final ProductModel product;

  const ProductVariantSheet({super.key, required this.product});

  @override
  State<ProductVariantSheet> createState() => _ProductVariantSheetState();
}

class _ProductVariantSheetState extends State<ProductVariantSheet> {
  late List<Map<String, dynamic>> variants;
  late List<Map<String, dynamic>> optionVariants;
  late List<Map<String, dynamic>> crossSellItems;

  double _defaultUnitPrice = 0;
  // ignore: unused_field
  String _defaultUnit = '';
  String _sheetImage = '';

  int selectedIndex = 0;
  int _selectedOptionIndex = -1;
  int quantity = 1;
  int _comboCount = 1;
  bool _isAddingToCart = false;
  bool _buyingOption = false;

  final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

  @override
  void initState() {
    super.initState();

    _sheetImage = widget.product.image;

    // --- KHỞI TẠO DỮ LIỆU ---
    variants = [
      {
        'name': widget.product.name,
        'price': widget.product.salePrice,
        'original_price': widget.product.originalPrice,
        'image': _sheetImage,
      },
    ];

    optionVariants = [];

    // Khởi tạo cross-sell từ optionsRecommend đã preload
    crossSellItems = widget.product.optionsRecommend.map((item) {
      return {
        ...item,
        'quantity': 0,
      };
    }).toList();

    _loadOptions();
  }

  Future<void> _loadOptions() async {
    try {
      final dio = DioClient().dio;
      final dataSource = HomeRemoteDataSourceImpl(client: dio);
      final detail = await dataSource.getProductDetail(id: widget.product.id);
      if (!mounted || detail == null) return;
      if (!detail.hasOptions || detail.options.isEmpty) return;

      final availableOptions = detail.options
          .where((o) => o.isAvailable)
          .toList(growable: false);
      if (availableOptions.isEmpty) return;

      final defaultIdx = availableOptions.indexWhere((o) => o.isDefault);
      // Options currently don't have their own images; reuse parent image.
      // Prefer detail.images.first (often a non-thumb URL) to avoid 404s.
      final String baseImage =
          (detail.images.isNotEmpty && detail.images.first.trim() != '0')
              ? detail.images.first.trim()
              : widget.product.image;

      setState(() {
        _defaultUnitPrice = detail.defaultPrice;
        _defaultUnit = detail.defaultUnit;
        _sheetImage = baseImage;

        // Update base variant image too (keeps UI consistent).
        if (variants.isNotEmpty) {
          variants[0]['image'] = _sheetImage;
        }

        optionVariants = availableOptions
            .map(
              (o) => {
                'option_id': o.id,
                'name': o.optionName,
                'price': o.totalPrice,
                'original_price': o.totalPrice,
                'image': _sheetImage,
                'combo_quantity': o.quantity,
                'combo_unit': o.unit,
                'unit_price': o.unitPrice,
                'stock_quantity': o.stockQuantity,
              },
            )
            .toList();
        _selectedOptionIndex = defaultIdx >= 0 ? defaultIdx : 0;
      });
    } catch (_) {
      // ignore
    }
  }

  // --- HÀM XỬ LÝ ADD TO CART ---
  Future<void> _handleAddToCart() async {
    if (_buyingOption) {
      if (optionVariants.isEmpty || _selectedOptionIndex < 0) {
        _showTopNotification(context, "Vui lòng chọn combo", isError: true);
        return;
      }
      if (_comboCount <= 0) {
        _showTopNotification(context, "Vui lòng chọn số lượng combo", isError: true);
        return;
      }
    } else {
      if (quantity <= 0) {
        _showTopNotification(context, "Vui lòng chọn số lượng", isError: true);
        return;
      }
    }

    setState(() => _isAddingToCart = true);

    try {
      final dio = DioClient().dio;

      // 1. App Token
      final appAuthRepo = AppAuthRepository(
        remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
      );
      await appAuthRepo.authenticateApp();

      // 2. User ID
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null || userId == 0) {
        if (mounted) {
          _showTopNotification(
            context,
            "Vui lòng đăng nhập để mua hàng",
            isError: true,
          );
          setState(() => _isAddingToCart = false);
        }
        return;
      }

      // 3. Call API
      final cartDataSource = CartRemoteDataSourceImpl(client: dio);
      final cartRepo = CartRepositoryImpl(remoteDataSource: cartDataSource);

        final int? optionId = _buyingOption
          ? (optionVariants[_selectedOptionIndex]['option_id'] as int?)
          : null;

        final int comboQty = _buyingOption
          ? ((optionVariants[_selectedOptionIndex]['combo_quantity'] as int?) ?? 0)
          : 0;
        final int qtyToSend = _buyingOption
          ? ((_comboCount) * (comboQty > 0 ? comboQty : 1))
          : quantity;

        if (qtyToSend <= 0) {
          if (mounted) {
            setState(() => _isAddingToCart = false);
            _showTopNotification(context, "Số lượng phải lớn hơn 0", isError: true);
          }
          return;
        }

      // Gửi sản phẩm chính
      final String result = await cartRepo.addToCart(
        userId,
        widget.product.id,
        qtyToSend,
        optionId: optionId,
      );

      if (result != "SUCCESS") {
        if (mounted) {
          setState(() => _isAddingToCart = false);
          _showTopNotification(context, result, isError: true);
        }
        return;
      }

      // Batch gửi cross-sell items đã chọn
      final selectedCrossSell = crossSellItems
          .where((item) => ((item['quantity'] as int?) ?? 0) > 0)
          .toList();
      for (final item in selectedCrossSell) {
        final crossId = item['id']?.toString() ?? item['product_id']?.toString();
        final crossQty = (item['quantity'] as int?) ?? 0;
        if (crossId != null && crossId.isNotEmpty && crossQty > 0) {
          await cartRepo.addToCart(userId, crossId, crossQty);
        }
      }

      if (mounted) {
        setState(() => _isAddingToCart = false);
        unawaited(CartBadgeController.instance.syncFromApi());
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Đã thêm vào giỏ hàng thành công!"),
            backgroundColor: const Color(0xFF388E3C),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isAddingToCart = false);
        _showTopNotification(context, "Lỗi hệ thống: $e", isError: true);
      }
    }
  }

  // --- [MỚI] HÀM HIỂN THỊ THÔNG BÁO TỪ TRÊN SỔ XUỐNG ---
  void _showTopNotification(
    BuildContext context,
    String message, {
    bool isError = true,
  }) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true, // Bấm ra ngoài để đóng
      barrierLabel: "Dismiss",
      barrierColor: Colors.transparent, // Không làm tối màn hình nền
      transitionDuration: const Duration(milliseconds: 400), // Tốc độ trượt
      pageBuilder: (context, anim1, anim2) {
        return Align(
          alignment: Alignment.topCenter, // Căn ở trên cùng màn hình
          child: Material(
            type: MaterialType.transparency,
            child: Container(
              // Cách lề trên (SafeArea) để không bị che bởi tai thỏ/status bar
              margin: EdgeInsets.only(
                top: MediaQuery.of(context).padding.top + 10,
                left: 16,
                right: 16,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isError
                    ? const Color(0xFFD32F2F)
                    : const Color(0xFF388E3C), // Đỏ đậm / Xanh đậm
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isError ? Icons.error_outline : Icons.check_circle_outline,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      message,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, anim1, anim2, child) {
        // Hiệu ứng trượt từ trên xuống (Offset 0,-1 -> 0,0)
        return SlideTransition(
          position: Tween(
            begin: const Offset(0, -1),
            end: const Offset(0, 0),
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutBack)),
          child: child,
        );
      },
    );

    // Tự động đóng sau 2.5 giây
    final navigator = Navigator.of(context, rootNavigator: true);
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      try {
        if (navigator.canPop()) {
          navigator.pop();
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double cardWidth = math.min(165, size.width * 0.42);
    const double cardHeight = 250;

    return Container(
      height: size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          // 1. HEADER
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    widget.product.name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF101828),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // 2. NỘI DUNG CUỘN
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A. Danh sách biến thể
                  SizedBox(
                    height: cardHeight,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: variants.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 12),
                      itemBuilder: (context, index) =>
                          _buildVariantCard(index, cardWidth: cardWidth),
                    ),
                  ),

                  const SizedBox(height: 20),

                  if (optionVariants.isNotEmpty) ...[
                    const Divider(thickness: 8, color: Color(0xFFF5F5F5)),
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "COMBO / TÙY CHỌN",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: cardHeight,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: optionVariants.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) =>
                                  _buildOptionCard(index, cardWidth: cardWidth),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (crossSellItems.isNotEmpty) ...[
                    const Divider(thickness: 8, color: Color(0xFFF5F5F5)),
                    // B. Mua kèm
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            "MUA KÈM TIẾT KIỆM HƠN",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 210,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: crossSellItems.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) =>
                                  _buildCrossSellItem(index),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),

          // 3. BOTTOM BAR
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  offset: const Offset(0, -4),
                  blurRadius: 10,
                ),
              ],
            ),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _isAddingToCart ? null : _handleAddToCart,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                child: _isAddingToCart
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        "THÊM VÀO GIỎ",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- CÁC WIDGET CON ---

  Widget _buildVariantCard(int index, {required double cardWidth}) {
    final variant = variants[index];
    final isSelected = selectedIndex == index;
    final double price = variant['price'];
    final double originalPrice = variant['original_price'];

    return SizedBox(
      width: cardWidth,
      child: ProductTileCard(
        image: variant['image']?.toString() ?? '',
        title: variant['name']?.toString() ?? '',
        titleMaxLines: 1,
        imageHeight: 84,
        contentPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        border: Border.all(
          color: isSelected ? AppColors.accent : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
        onTap: () {
          setState(() {
            selectedIndex = index;
            _buyingOption = false;
            _selectedOptionIndex = -1;
            _comboCount = 0;
          });
        },
        price: Text(
          currencyFormat.format(price),
          style: const TextStyle(
            color: AppColors.accent,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        originalPrice: (originalPrice > price)
            ? Text(
                currencyFormat.format(originalPrice),
                style: const TextStyle(
                  decoration: TextDecoration.lineThrough,
                  fontSize: 11,
                  color: Colors.grey,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              )
            : null,
        action: isSelected
            ? (quantity > 0
                ? _buildQuantityControl(
                    value: quantity,
                    onDecrement: () {
                      if (quantity > 0) setState(() => quantity--);
                    },
                    onIncrement: () => setState(() => quantity++),
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        quantity = 1;
                      }),
                      child: const Text("CHỌN MUA"),
                    ),
                  ))
            : SizedBox(
                width: double.infinity,
                height: 34,
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    selectedIndex = index;
                    _buyingOption = false;
                    _selectedOptionIndex = -1;
                    _comboCount = 0;
                    if (quantity <= 0) quantity = 1;
                  }),
                  child: const Text("CHỌN MUA"),
                ),
              ),
      ),
    );
  }

  Widget _buildOptionCard(int index, {required double cardWidth}) {
    final option = optionVariants[index];
    final bool isSelected = _buyingOption && _selectedOptionIndex == index;

    final double price = option['price'] as double;
    final int comboQty = (option['combo_quantity'] as int?) ?? 0;
    final String comboUnit = option['combo_unit']?.toString() ?? '';
    final double unitPrice = (option['unit_price'] is num)
        ? (option['unit_price'] as num).toDouble()
        : double.tryParse(option['unit_price']?.toString() ?? '0') ?? 0;
    final double baseUnitPrice = _defaultUnitPrice > 0
      ? _defaultUnitPrice
      : (unitPrice > 0 ? unitPrice : widget.product.salePrice);
    final int stockQty = (option['stock_quantity'] as int?) ?? 0;
    final double compareTotal = comboQty > 0 ? (comboQty * baseUnitPrice) : 0;
    final double savings = (compareTotal > 0 && compareTotal > price)
        ? (compareTotal - price)
        : 0;
    final String optionName = option['name']?.toString() ?? '';

    final String normalizedName = optionName.trim().toLowerCase();
    final String normalizedUnit = comboUnit.trim().toLowerCase();
    final bool showQtyLine = comboQty > 0 &&
      !(normalizedName.contains(comboQty.toString()) &&
        (normalizedUnit.isEmpty || normalizedName.contains(normalizedUnit)));

    final String displayImage =
      (_sheetImage.trim().isNotEmpty && _sheetImage.trim() != '0')
        ? _sheetImage.trim()
        : 'https://via.placeholder.com/150';

    return SizedBox(
      width: cardWidth,
      child: ProductTileCard(
        image: displayImage,
        title: optionName,
        titleMaxLines: 1,
        imageHeight: 84,
        contentPadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        border: Border.all(
          color: isSelected ? AppColors.accent : Colors.grey.shade200,
          width: isSelected ? 2 : 1,
        ),
        onTap: () {
          setState(() {
            if (isSelected) {
              _buyingOption = false;
              _selectedOptionIndex = -1;
              _comboCount = 0;
            } else {
              _selectedOptionIndex = index;
              _buyingOption = true;
              if (_comboCount <= 0) _comboCount = 1;
            }
          });
        },
        price: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currencyFormat.format(price),
              style: const TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (showQtyLine)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '$comboQty $comboUnit',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF667085),
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (comboQty > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '$comboQty × ${currencyFormat.format(baseUnitPrice)} = ${currencyFormat.format(compareTotal)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF98A2B3),
                    decoration: TextDecoration.lineThrough,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (savings > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Tiết kiệm ${currencyFormat.format(savings)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.greenFresh,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (stockQty > 0)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Còn: $stockQty',
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF667085),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        action: isSelected
            ? (_comboCount > 0
                ? _buildQuantityControl(
                    value: _comboCount,
                    onDecrement: () {
                      if (_comboCount > 0) setState(() => _comboCount--);
                    },
                    onIncrement: () => setState(() => _comboCount++),
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 34,
                    child: OutlinedButton(
                      onPressed: () => setState(() {
                        _comboCount = 1;
                      }),
                      child: const Text('CHỌN COMBO'),
                    ),
                  ))
            : SizedBox(
                width: double.infinity,
                height: 34,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.grey.shade300),
                    foregroundColor: const Color(0xFF101828),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => setState(() {
                    _selectedOptionIndex = index;
                    _buyingOption = true;
                    if (_comboCount <= 0) _comboCount = 1;
                  }),
                  child: const Text('CHỌN COMBO'),
                ),
              ),
      ),
    );
  }

  Widget _buildQuantityControl({
    required int value,
    required VoidCallback onDecrement,
    required VoidCallback onIncrement,
  }) {
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          _buildQtyBtn(Icons.remove, onDecrement),
          Expanded(
            child: Text(
              "$value",
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          _buildQtyBtn(Icons.add, onIncrement),
        ],
      ),
    );
  }

  Widget _buildQtyBtn(IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: 36,
      height: 36,
      child: IconButton(
        icon: Icon(icon, size: 16, color: Colors.black87),
        padding: EdgeInsets.zero,
        onPressed: onTap,
      ),
    );
  }

  Widget _buildCrossSellItem(int index) {
    final item = crossSellItems[index];
    final int qty = (item['quantity'] as int?) ?? 0;
    // options_recommend dùng product_name/option_name thay vì name
    final String name = item['product_name']?.toString().isNotEmpty == true
        ? item['product_name'].toString()
        : item['option_name']?.toString() ?? item['name']?.toString() ?? '';
    // options_recommend dùng unit_price/total_price thay vì final_price
    final double price = double.tryParse(
          item['unit_price']?.toString() ??
              item['total_price']?.toString() ??
              item['final_price']?.toString() ??
              item['price']?.toString() ??
              '0',
        ) ??
        0;
    // options_recommend thường không có ảnh — dùng ảnh sản phẩm cha nếu cần
    final String image = item['primary_image']?.toString().isNotEmpty == true
        ? item['primary_image'].toString()
        : item['image']?.toString() ?? '';

    return Container(
      width: 140,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: qty > 0 ? AppColors.accent : Colors.grey.shade200,
          width: qty > 0 ? 1.5 : 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Ảnh
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            child: image.isNotEmpty
                ? Image.network(
                    image,
                    height: 90,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 90,
                      color: Colors.grey.shade100,
                      child: Icon(Icons.eco,
                          color: Colors.green.shade300, size: 40),
                    ),
                  )
                : Container(
                    height: 90,
                    color: Colors.grey.shade100,
                    child:
                        Icon(Icons.eco, color: Colors.green.shade300, size: 40),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          if (price > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                currencyFormat.format(price),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: qty > 0
                ? _buildQuantityControl(
                    value: qty,
                    onDecrement: () => setState(
                        () => crossSellItems[index]['quantity'] = qty - 1),
                    onIncrement: () => setState(
                        () => crossSellItems[index]['quantity'] = qty + 1),
                  )
                : SizedBox(
                    width: double.infinity,
                    height: 30,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => setState(
                          () => crossSellItems[index]['quantity'] = 1),
                      child: const Text('+ Thêm',
                          style: TextStyle(fontSize: 12)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
