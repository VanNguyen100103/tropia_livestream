import 'package:tropia_mobile_app_android/livestream/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/livestream/core/utils/logger.dart';
import 'package:tropia_mobile_app_android/livestream/features/order/models/order_model.dart';

const _tag = 'OrderRepository';

class OrderRepository {
  OrderRepository._();
  static final instance = OrderRepository._();

  get _dio => AuthService.instance.authorizedDio();

  // ── Place order ───────────────────────────────────────────────────────────

  /// POST /api/orders
  Future<OrderModel> place({
    required String sessionId,
    required String productId,
    required int quantity,
    String? couponCode,
  }) async {
    final res = await _dio.post('/api/orders', data: {
      'sessionId':  sessionId,
      'productId':  productId,
      'quantity':   quantity,
      'buyerName':  AuthService.instance.currentUser?.name ?? 'Khách',
      if (couponCode != null) 'couponCode': couponCode,
    });
    AppLogger.logInfo(_tag, 'Order placed: ${res.data['orderId']}');
    return OrderModel.fromJson(res.data as Map<String, dynamic>);
  }

  // ── My orders ─────────────────────────────────────────────────────────────

  /// GET /api/orders/my/list?page=&limit=
  Future<({List<OrderModel> items, int total})> myOrders(
      {int page = 1, int limit = 20}) async {
    final res = await _dio.get('/api/orders/my/list',
        queryParameters: {'page': page, 'limit': limit});
    final data = res.data as Map<String, dynamic>;
    final items = (data['items'] as List? ?? data['orders'] as List? ?? [])
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
    return (items: items, total: (data['total'] as num? ?? items.length).toInt());
  }

  /// POST /api/orders/checkout — đặt hàng từ giỏ hàng thường.
  /// Backend đọc `cart_items WHERE is_selected = TRUE` cho buyer hiện tại,
  /// validate từng `coupon_codes[i]` (active / chưa dùng / đạt min), cộng
  /// discount, tạo order tổng hợp. `items` / `note` / `discountAmount` FE
  /// gửi xuống hiện chưa được backend dùng tới.
  ///
  /// `shippingName` / `shippingPhone` / `shippingAddress` được lưu vào
  /// live_orders + đính kèm vào event `payment.success` để email biên
  /// lai hiển thị địa chỉ giao hàng. Tab "Nhận tại cửa hàng" để trống.
  Future<({List<OrderModel> orders, int grandTotal, int couponDiscount})> checkout({
    required List<CheckoutItem> items,
    List<String> couponCodes = const [],
    int discountAmount = 0,
    String paymentMethod = 'cod',
    String? note,
    String? shippingName,
    String? shippingPhone,
    String? shippingAddress,
  }) async {
    final res = await _dio.post('/api/orders/checkout', data: {
      if (couponCodes.isNotEmpty) 'coupon_codes': couponCodes,
      'payment_method': paymentMethod,
      if (shippingName    != null && shippingName.isNotEmpty)    'shipping_name':    shippingName,
      if (shippingPhone   != null && shippingPhone.isNotEmpty)   'shipping_phone':   shippingPhone,
      if (shippingAddress != null && shippingAddress.isNotEmpty) 'shipping_address': shippingAddress,
    });
    final data = res.data as Map<String, dynamic>;
    final order = OrderModel.fromJson(data['order'] as Map<String, dynamic>);
    AppLogger.logInfo(_tag, 'Cart checkout: order=${order.id}, total=${order.totalPrice}');
    return (
      orders: [order],
      grandTotal: order.totalPrice,
      couponDiscount: order.discountAmount,
    );
  }

  /// GET /api/orders/:sessionId  (orders by session – seller/admin)
  Future<List<OrderModel>> bySession(String sessionId) async {
    final res = await _dio.get('/api/orders/$sessionId');
    return (res.data as List)
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class CheckoutItem {
  final String cartItemId;
  final String variantId;
  final int quantity;
  final int unitPrice;
  final String productName;
  final String? sessionId;

  const CheckoutItem({
    required this.cartItemId,
    required this.variantId,
    required this.quantity,
    required this.unitPrice,
    required this.productName,
    this.sessionId,
  });

  Map<String, dynamic> toJson() => {
    'cartItemId':  cartItemId,
    'variantId':   variantId,
    'quantity':    quantity,
    'unitPrice':   unitPrice,
    'productName': productName,
    if (sessionId != null) 'sessionId': sessionId,
  };
}
