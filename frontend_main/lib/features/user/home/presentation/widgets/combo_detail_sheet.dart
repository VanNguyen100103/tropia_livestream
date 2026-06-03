import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Import format tiền
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/domain/repositories/cart_repository_impl.dart';
import 'dart:async';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/cart_badge_controller.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../data/models/product_model.dart';
import '../../data/models/ready_to_cook_model.dart'; // 1. Import Model chính
import 'product_card.dart';

class ComboDetailSheet extends StatefulWidget {
  final ReadyToCookModel combo; // 2. Đổi từ Map sang Model
  const ComboDetailSheet({super.key, required this.combo});

  @override
  State<ComboDetailSheet> createState() => _ComboDetailSheetState();
}

class _ComboDetailSheetState extends State<ComboDetailSheet> {
  // 3. Tách biệt: List sản phẩm (tĩnh) và List số lượng (động)
  late List<ProductModel> _ingredients;
  late List<int> _quantities;

  double _totalPrice = 0;
  bool _isAddingToCart = false;

  @override
  void initState() {
    super.initState();
    // Lấy danh sách nguyên liệu đã có sẵn trong Model
    _ingredients = widget.combo.ingredients;

    // Khởi tạo số lượng mặc định là 1 cho tất cả nguyên liệu
    _quantities = List.filled(_ingredients.length, 1);

    _recalculateTotal();

    assert(_ingredients.length == _quantities.length);
  }

  // Recalculate only (no setState here)
  void _recalculateTotal() {
    double tempTotal = 0;
    for (int i = 0; i < _ingredients.length; i++) {
      tempTotal += (_ingredients[i].salePrice * _quantities[i]);
    }
    _totalPrice = tempTotal;
  }

  void _setQuantity(int index, int value) {
    if (!mounted) return;
    if (index < 0 || index >= _quantities.length) return; // guard
    setState(() {
      _quantities[index] = value < 0 ? 0 : value;
      _recalculateTotal();
    });
  }

  void _updateQuantity(int index, int delta) {
    final newQty = _quantities[index] + delta;
    _setQuantity(index, newQty);
  }

  Widget _buildIngredientCard(int index) {
    final product = _ingredients[index];
    final qty = _quantities[index];

    final card = ProductCard(
      product: product,
      isFlashSale: false,
      quantity: qty,
      onAdd: () => _updateQuantity(index, 1),
      onRemove: () => _updateQuantity(index, -1),
    );

    // If ProductCard shows "Chọn mua" at qty==0 and that button doesn't call onAdd,
    // this overlay lets user tap to restore qty=1.
    if (qty == 0) {
      return Stack(
        children: [
          card,
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _setQuantity(index, 1),
              ),
            ),
          ),
        ],
      );
    }

    return card;
  }

  Future<void> _handleAddComboToCart() async {
    if (_isAddingToCart) return;

    final itemsToAdd = <Map<String, dynamic>>[];
    for (int i = 0; i < _ingredients.length; i++) {
      final qty = _quantities[i];
      if (qty > 0) {
        itemsToAdd.add({'product': _ingredients[i], 'quantity': qty});
      }
    }

    if (itemsToAdd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng chọn số lượng ít nhất 1 nguyên liệu'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isAddingToCart = true);

    try {
      final dio = DioClient().dio;

      // Ensure app token exists
      final appAuthRepo = AppAuthRepository(
        remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
      );
      await appAuthRepo.authenticateApp();

      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');

      if (userId == null || userId == 0) {
        if (mounted) {
          setState(() => _isAddingToCart = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vui lòng đăng nhập để mua hàng'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      final cartRepo = CartRepositoryImpl(
        remoteDataSource: CartRemoteDataSourceImpl(client: dio),
      );

      for (final entry in itemsToAdd) {
        final product = entry['product'] as ProductModel;
        final qty = entry['quantity'] as int;

        final result = await cartRepo.addToCart(userId, product.id, qty);
        if (result != 'SUCCESS') {
          if (mounted) {
            setState(() => _isAddingToCart = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result), backgroundColor: Colors.red),
            );
          }
          return;
        }
      }

      if (!mounted) return;
      setState(() => _isAddingToCart = false);

      // Close sheet and notify
      unawaited(CartBadgeController.instance.syncFromApi());
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã thêm combo vào giỏ hàng!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isAddingToCart = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi hệ thống: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.background, // was Color(0xFFF5F5F5)
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 1. HEADER
          Container(
            padding: const EdgeInsets.fromLTRB(
              16,
              18,
              16,
              14,
            ), // thoáng hơn một chút
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Nguyên liệu món",
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.combo.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.grey),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey[100],
                  ),
                ),
              ],
            ),
          ),

          // 2. GRID DANH SÁCH
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12, top: 8),
                    child: Text(
                      "Tùy chỉnh số lượng thành phần:",
                      style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      const crossAxisCount = 2;
                      const spacing = 12.0;
                      const targetHeight = 300.0;
                      final itemWidth =
                          (constraints.maxWidth - spacing) / crossAxisCount;
                      final childAspectRatio = itemWidth / targetHeight;
                      return GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: crossAxisCount,
                              childAspectRatio: childAspectRatio,
                              crossAxisSpacing: spacing,
                              mainAxisSpacing: spacing,
                            ),
                        itemCount: _ingredients.length,
                        itemBuilder: (context, index) {
                          return _buildIngredientCard(index);
                        },
                      );
                    },
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),

          // 3. BOTTOM BUTTON
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black12,
                  blurRadius: 10,
                  offset: Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _isAddingToCart ? null : _handleAddComboToCart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.greenFresh,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.shopping_basket,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 10),
                            Text(
                              "THÊM VÀO GIỎ  •  ${currencyFormat.format(_totalPrice)}",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
