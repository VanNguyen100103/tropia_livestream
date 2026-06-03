import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/domain/repositories/cart_repository_impl.dart';
import '../../data/models/cart_model.dart';

class CartItemWidget extends StatefulWidget {
  final CartItemModel item;
  final Function(int newQty, double priceDiff, int qtyDiff) onQuantityChanged;
  final Future<void> Function()? onCartUpdated;

  const CartItemWidget({
    super.key,
    required this.item,
    required this.onQuantityChanged,
    this.onCartUpdated,
  });

  @override
  State<CartItemWidget> createState() => _CartItemWidgetState();
}

class _CartItemWidgetState extends State<CartItemWidget> {
  late int _quantity;
  Timer? _debounce;
  late CartRepositoryImpl _cartRepo;

  @override
  void initState() {
    super.initState();
    _quantity = widget.item.quantity;
    _cartRepo = CartRepositoryImpl(
      remoteDataSource: CartRemoteDataSourceImpl(client: DioClient().dio),
    );
  }

  // Cập nhật số lượng (+/-)
  void _updateQuantity(int change) {
    if (widget.item.option != null) return;
    final newQty = _quantity + change;
    if (newQty < 1) return;

    double price = widget.item.price;
    double diff = (newQty - _quantity) * price;
    final int qtyDiff = newQty - _quantity;

    setState(() => _quantity = newQty);
    widget.onQuantityChanged(newQty, diff, qtyDiff);

    if (_debounce?.isActive ?? false) _debounce!.cancel();

    _debounce = Timer(const Duration(milliseconds: 800), () async {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id') ?? 0;
      final success = await _cartRepo.updateCart(
        userId,
        widget.item.productId,
        newQty,
        optionId: widget.item.option?.optionId,
      );

      if (success) {
        await widget.onCartUpdated?.call();
      }
    });
  }

  // [MỚI] Hàm xóa sản phẩm
  Future<void> _deleteItem() async {
    // 1. Hủy timer cũ nếu đang chạy
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    // 2. Tính tiền cần trừ (toàn bộ giá trị của món hàng này)
    final bool isOptionItem = widget.item.option != null;
    double diff = isOptionItem
        ? -(widget.item.totalLinePrice)
        : -(_quantity * widget.item.price);

    // 3. Gọi API xóa ngay lập tức (không cần debounce)
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;

    // Gọi ngầm
    _cartRepo
        .updateCart(
          userId,
          widget.item.productId,
          0,
          optionId: widget.item.option?.optionId,
        )
        .then((success) {
          if (success) {
            debugPrint("🗑️ Đã xóa ${widget.item.name} trên server");
            widget.onCartUpdated?.call();
          }
        });

    // 4. Báo lên cha để xóa khỏi UI ngay lập tức
    // Truyền quantity = 0 là tín hiệu để xóa
    widget.onQuantityChanged(0, diff, -_quantity);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'vi_VN', symbol: 'đ');
    bool hasImage = widget.item.image.isNotEmpty && widget.item.image != "0";
    final option = widget.item.option;
    final bool isOptionItem = option != null;

    final double displayTotalPrice = isOptionItem
        ? widget.item.totalLinePrice
        : (_quantity * widget.item.price);
    final double displayUnitPrice = isOptionItem
        ? option.unitPrice
        : widget.item.price;

    final int packQty = option?.quantity ?? 0;
    final int comboCount = (isOptionItem && packQty > 0)
        ? (_quantity / packQty).floor()
        : 0;
    final bool isFullPacks = (isOptionItem && packQty > 0)
        ? (_quantity % packQty == 0)
        : false;
    final String comboLabel;
    if (isOptionItem) {
      final opt = option;
      comboLabel = (isFullPacks && comboCount > 0)
          ? '${opt.optionName} ×$comboCount'
          : opt.optionName;
    } else {
      comboLabel = '';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [CẬP NHẬT] Nút xóa (Dấu X)
          GestureDetector(
            onTap: _deleteItem, // Gọi hàm xóa
            child: const Padding(
              padding: EdgeInsets.only(right: 8, bottom: 8), // Tăng vùng bấm
              child: Icon(Icons.cancel, color: Colors.grey, size: 22),
            ),
          ),

          // Ảnh sản phẩm
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: hasImage
                ? Image.network(
                    widget.item.image,
                    width: 70,
                    height: 70,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => _buildPlaceholderImage(),
                  )
                : _buildPlaceholderImage(),
          ),
          const SizedBox(width: 12),

          // Thông tin chi tiết
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.item.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (isOptionItem) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1E8),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'COMBO',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepOrange,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          comboLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          currencyFormat.format(displayTotalPrice),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Colors.red,
                          ),
                        ),
                        Text(
                          '$_quantity × ${currencyFormat.format(displayUnitPrice)}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.grey,
                          ),
                        ),
                        if (widget.item.originalPrice != null &&
                            widget.item.originalPrice! > 0)
                          Text(
                            currencyFormat.format(widget.item.originalPrice),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                    if (!isOptionItem)
                      Container(
                        height: 30,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            _buildQtyBtn(
                              Icons.remove,
                              () => _updateQuantity(-1),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: Text(
                                "$_quantity",
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            _buildQtyBtn(Icons.add, () => _updateQuantity(1)),
                          ],
                        ),
                      )
                    else
                      Text(
                        'SL: $_quantity',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderImage() {
    return Container(
      width: 70,
      height: 70,
      color: Colors.grey[200],
      child: const Icon(Icons.image, color: Colors.grey),
    );
  }

  Widget _buildQtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: 30,
        alignment: Alignment.center,
        child: Icon(icon, size: 16, color: Colors.black54),
      ),
    );
  }
}
