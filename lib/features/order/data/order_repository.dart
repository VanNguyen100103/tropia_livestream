import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/order/models/order_model.dart';

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

  /// POST /api/orders/checkout — đặt hàng từ giỏ hàng thường
  /// Trả về list orders và summary
  Future<({List<OrderModel> orders, int grandTotal, int couponDiscount})> checkout({
    required List<CheckoutItem> items,
    String? couponCode,
    int discountAmount = 0,
    String paymentMethod = 'cod',
    String? note,
  }) async {
    final res = await _dio.post('/api/orders/checkout', data: {
      'items': items.map((i) => i.toJson()).toList(),
      if (couponCode != null) 'couponCode': couponCode,
      if (discountAmount > 0) 'discountAmount': discountAmount,
      'paymentMethod': paymentMethod,
      if (note != null && note.isNotEmpty) 'note': note,
    });
    final data = res.data as Map<String, dynamic>;
    final orderList = (data['orders'] as List)
        .map((e) => OrderModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final summary = data['summary'] as Map<String, dynamic>;
    AppLogger.logInfo(_tag, 'Cart checkout: ${orderList.length} orders, total=${summary['grandTotal']}');
    return (
      orders: orderList,
      grandTotal: (summary['grandTotal'] as num).toInt(),
      couponDiscount: (summary['couponDiscount'] as num? ?? 0).toInt(),
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
