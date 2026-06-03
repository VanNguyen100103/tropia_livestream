import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart'; // 1. Import SharedPreferences
import 'package:tropia_mobile_app_android/features/user/cart/domain/repositories/cart_repository_impl.dart';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/cart_badge_controller.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/datasources/order_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/order/domain/repositories/order_repository_impl.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/models/user_orders.dart';
import '../../../../../core/constants/app_colors.dart';

// Import Network & Cart
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';

// Import Order Tracking
import 'package:tropia_mobile_app_android/features/user/order/presentation/order_tracking_screen.dart';

class OrderCard extends StatefulWidget {
  final UserOrder order;
  final VoidCallback? onReorder;
  final VoidCallback? onCancelled;

  const OrderCard({super.key, required this.order, this.onReorder, this.onCancelled});

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  bool _isLoadingDetail = false;
  bool _isAddingToCart = false;
  bool _isCancelling = false;

  bool get _isProcessing {
    final s = (widget.order.status ?? '').toLowerCase();
    return s.contains('pending') ||
        s.contains('processing') ||
        s.contains('confirmed') ||
        s.contains('đang xử lý') ||
        s.contains('chờ');
  }
  List<OrderProduct>? _products;
  String? _shippingMethod;

  // Khai báo Repository (sẽ khởi tạo trong initState để an toàn)
  late OrderRepositoryImpl _orderRepository;
  late CartRepositoryImpl _cartRepository;

  // ❌ ĐÃ XÓA BIẾN _currentUserId = 40 (Nguyên nhân lỗi)

  @override
  void initState() {
    super.initState();
    // 2. Khởi tạo Repository chuẩn với DioClient (có Token)
    final dio = DioClient().dio;

    // Nếu Constructor của OrderRemoteDataSourceImpl không có tham số client thì bỏ qua
    _orderRepository = OrderRepositoryImpl(
      remoteDataSource: OrderRemoteDataSourceImpl(),
    );

    _cartRepository = CartRepositoryImpl(
      remoteDataSource: CartRemoteDataSourceImpl(client: dio),
    );
  }

  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });

    if (_isExpanded && (_products == null || _products!.isEmpty)) {
      _fetchOrderDetail();
    }
  }

  Future<void> _fetchOrderDetail() async {
    setState(() => _isLoadingDetail = true);
    try {
      final detailOrder = await _orderRepository.getOrderDetail(
        widget.order.id,
      );
      if (mounted) {
        setState(() {
          _products = detailOrder?.products ?? [];
          _shippingMethod = detailOrder?.shippingMethod;
          _isLoadingDetail = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingDetail = false);
    }
  }

  // --- HÀM XỬ LÝ MUA LẠI (ĐÃ SỬA) ---
  Future<void> _handleBuyAgain() async {
    if (_products == null || _products!.isEmpty) return;

    // 3. Lấy User ID thật từ SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final userId = prefs.getInt('user_id');

    if (userId == null || userId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Vui lòng đăng nhập lại để thực hiện")),
      );
      return;
    }

    setState(() => _isAddingToCart = true);

    int successCount = 0;

    for (var item in _products!) {
      if (item.id.isEmpty) continue;

      // 4. Gọi API với ID thật (userId)
      try {
        String result = await _cartRepository.addToCart(
          userId, // Dùng biến userId vừa lấy, KHÔNG dùng _currentUserId cũ
          item.id,
          item.quantity ?? 1,
        );

        if (result == "SUCCESS") {
          successCount++;
        }
      } catch (e) {
        debugPrint("Lỗi thêm giỏ hàng: $e");
      }
    }

    setState(() => _isAddingToCart = false);

    if (mounted) {
      if (successCount > 0) {
        unawaited(CartBadgeController.instance.syncFromApi());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Đã thêm $successCount sản phẩm vào giỏ hàng"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
        // Gọi callback nếu cha cần cập nhật
        widget.onReorder?.call();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Không thể thêm sản phẩm vào giỏ"),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // --- HÀM ĐIỀU HƯỚNG ĐẾN TRANG THEO DÕI ĐƠN HÀNG ---
  void _handleViewDetails() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OrderTrackingScreen(
          orderId: widget.order.id,
          orderCode: widget.order.orderCode,
        ),
      ),
    );
  }

  // --- HÀM HỦY ĐƠN HÀNG ---
  Future<void> _handleCancelOrder() async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Hủy đơn hàng"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Mã đơn: ${widget.order.orderCode ?? widget.order.id}",
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: "Lý do hủy",
                hintText: "Nhập lý do hủy đơn hàng...",
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.all(10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Quay lại"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Xác nhận hủy", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Vui lòng nhập lý do hủy đơn"),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isCancelling = true);

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id') ?? 0;

    final success = await _orderRepository.cancelOrder(
      userId,
      widget.order.id,
      reason,
    );

    if (!mounted) return;
    setState(() => _isCancelling = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Đã hủy đơn hàng thành công"),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      widget.onCancelled?.call();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Không thể hủy đơn. Vui lòng thử lại"),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // --- GIỮ NGUYÊN PHẦN UI CỦA BẠN ---
    Color statusColor;
    Color statusBgColor;
    String status = widget.order.status?.toLowerCase() ?? 'pending';

    switch (status) {
      case 'completed':
      case 'success':
      case 'hoàn thành':
        statusColor = Colors.green;
        statusBgColor = Colors.green;
        break;
      case 'processing':
      case 'confirmed':
      case 'đang xử lý':
        statusColor = Colors.blue;
        statusBgColor = Colors.blue;
        break;
      case 'cancelled':
      case 'cancel':
      case 'đã hủy':
        statusColor = Colors.red;
        statusBgColor = Colors.red;
        break;
      default:
        statusColor = AppColors.primary;
        statusBgColor = AppColors.primary;
    }

    String shippingText = _getShippingMethodText(widget.order.shippingMethod);
    if (shippingText.isEmpty) {
      shippingText = _getShippingMethodText(_shippingMethod);
    }

    return GestureDetector(
      onTap: _toggleExpand,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: _isExpanded
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
          border: _isExpanded
              ? Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- HEADER ---
            Row(
              children: [
                const Icon(Icons.receipt_long, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  "Mã đơn: ${widget.order.orderCode ?? widget.order.id}",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusBgColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _getStatusText(status),
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: _isExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.chevron_right,
                    color: Colors.grey[400],
                    size: 24,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4),
              child: Text(
                widget.order.createdAt ?? "",
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
              ),
            ),

            const Divider(height: 24, thickness: 0.5),

            // --- TỔNG TIỀN ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Tổng tiền:",
                  style: TextStyle(fontSize: 15, color: Colors.black54),
                ),
                Text(
                  _formatCurrency(widget.order.totalAmount ?? 0),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),

            // --- PHẦN MỞ RỘNG (DROP DOWN) ---
            AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              child: SizedBox(
                width: double.infinity,
                child: _isExpanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          // --- THÔNG TIN NGƯỜI NHẬN & ĐỊA CHỈ ---
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.person_outline,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.black87,
                                          ),
                                          children: [
                                            const TextSpan(
                                              text: "Người nhận: ",
                                              style: TextStyle(
                                                color: Colors.grey,
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  widget.order.customerName ??
                                                  "Khách hàng",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.location_on_outlined,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.order.address ??
                                            "Chưa cập nhật địa chỉ",
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Icon(
                                      Icons.phone_outlined,
                                      size: 16,
                                      color: Colors.grey,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        widget.order.phone ??
                                            "Chưa cập nhật số điện thoại",
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),

                                if (_getShippingMethodText(
                                  _shippingMethod,
                                ).isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.local_shipping_outlined,
                                        size: 16,
                                        color: Colors.grey,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _getShippingMethodText(
                                            _shippingMethod,
                                          ),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.black87,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),
                          const Text(
                            "Chi tiết sản phẩm:",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // --- LIST SẢN PHẨM ---
                          _isLoadingDetail
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(10),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                )
                              : _products == null || _products!.isEmpty
                              ? const Text(
                                  "Không có dữ liệu sản phẩm",
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic,
                                  ),
                                )
                              : Column(
                                  children: _products!
                                      .map((item) => _buildProductItem(item))
                                      .toList(),
                                ),

                          const SizedBox(height: 16),

                          // --- NÚT MUA LẠI VÀ XEM CHI TIẾT (SPLIT BUTTONS) ---
                          Row(
                            children: [
                              // Nút "Hủy đơn" (processing) hoặc "Theo dõi đơn hàng"
                              Expanded(
                                child: _isProcessing
                                    ? OutlinedButton(
                                        onPressed: _isCancelling ? null : _handleCancelOrder,
                                        style: ButtonStyle(
                                          foregroundColor: WidgetStateProperty.all(Colors.red),
                                          side: WidgetStateProperty.all(
                                            const BorderSide(color: Colors.red),
                                          ),
                                          padding: WidgetStateProperty.all(
                                            const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                          shape: WidgetStateProperty.all(
                                            RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                          backgroundColor: WidgetStateProperty.all(Colors.white),
                                        ),
                                        child: _isCancelling
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.red,
                                                ),
                                              )
                                            : const Text(
                                                "Hủy đơn",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 13,
                                                ),
                                              ),
                                      )
                                    : OutlinedButton(
                                        onPressed: _handleViewDetails,
                                        style: ButtonStyle(
                                          foregroundColor: WidgetStateProperty.all(
                                            AppColors.primary,
                                          ),
                                          side: WidgetStateProperty.all(
                                            const BorderSide(color: AppColors.primary),
                                          ),
                                          padding: WidgetStateProperty.all(
                                            const EdgeInsets.symmetric(vertical: 12),
                                          ),
                                          shape: WidgetStateProperty.all(
                                            RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                          ),
                                          overlayColor: WidgetStateProperty.all(
                                            AppColors.primary.withValues(alpha: 0.1),
                                          ),
                                          backgroundColor: WidgetStateProperty.all(Colors.white),
                                        ),
                                        child: const Text(
                                          "Theo dõi đơn hàng",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                              ),
                              const SizedBox(width: 12),

                              // Nút "Mua lại"
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _isAddingToCart
                                      ? null
                                      : _handleBuyAgain,
                                  style: ButtonStyle(
                                    foregroundColor: WidgetStateProperty.all(
                                      AppColors.primary,
                                    ),
                                    side: WidgetStateProperty.all(
                                      const BorderSide(color: AppColors.primary),
                                    ),
                                    padding: WidgetStateProperty.all(
                                      const EdgeInsets.symmetric(vertical: 12),
                                    ),
                                    shape: WidgetStateProperty.all(
                                      RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    overlayColor: WidgetStateProperty.all(
                                      AppColors.primary.withValues(alpha: 0.1),
                                    ),
                                    backgroundColor: WidgetStateProperty.all(
                                      Colors.white,
                                    ),
                                  ),
                                  child: _isAddingToCart
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppColors.primary,
                                          ),
                                        )
                                      : const Text(
                                          "Mua lại",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductItem(OrderProduct item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedNetworkImage(
              imageUrl: item.image ?? "",
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 50,
                height: 50,
                color: Colors.grey[100],
              ),
              errorWidget: (_, _, _) => Container(
                width: 50,
                height: 50,
                color: Colors.grey[100],
                child: const Icon(Icons.image_not_supported, size: 20, color: Colors.grey),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name ?? "",
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  "x${item.quantity ?? 0}",
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            _formatCurrency(item.total ?? 0),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  String _formatCurrency(num amount) =>
      "${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}đ";

  String _getStatusText(String status) {
    if (status.contains('pending')) return "Chờ xử lý";
    if (status.contains('processing')) return "Đang xử lý";
    if (status.contains('complete') || status.contains('success')) {
      return "Hoàn thành";
    }
    if (status.contains('cancel')) return "Đã hủy";
    return "Đang cập nhật";
  }

  String _getShippingMethodText(String? shippingMethod) {
    final raw = (shippingMethod ?? '').trim();
    final method = raw.toLowerCase();
    if (method.isEmpty) return '';

    String? label;
    if (method == 'store_pickup' ||
        method == 'store pickup' ||
        method == 'storepick' ||
        method == 'store pick') {
      label = 'Nhận tại cửa hàng';
    } else if (method == 'home_delivery' ||
        method == 'home delivery' ||
        method == 'homedelivery') {
      label = 'Giao hàng tận nơi';
    }

    return label ?? raw;
  }
}
