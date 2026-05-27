import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/cart/models/cart_item_model.dart';

const _tag = 'CartRepository';

class CartRepository {
  CartRepository._();
  static final instance = CartRepository._();

  get _dio => AuthService.instance.authorizedDio();

  // ── Lấy giỏ hàng ─────────────────────────────────────────────────────────

  Future<({List<CartItemModel> items, CartSummary summary})> getCart() async {
    final res  = await _dio.get('/api/cart');
    final data = res.data as Map<String, dynamic>;
    final items = (data['items'] as List)
        .map((e) => CartItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
    final summary = CartSummary.fromJson(data['summary'] as Map<String, dynamic>);
    return (items: items, summary: summary);
  }

  // ── Thêm vào giỏ ─────────────────────────────────────────────────────────

  Future<CartItemModel> addItem({
    required String variantId,
    int quantity = 1,
  }) async {
    final res = await _dio.post('/api/cart/items', data: {
      'variant_id': variantId,
      'quantity':   quantity,
    });
    AppLogger.logUserEvent(
      action: 'add_to_cart',
      context: _tag,
      metadata: {'variantId': variantId, 'quantity': quantity},
    );
    return CartItemModel.fromJson(res.data as Map<String, dynamic>);
  }

  // Thêm vào giỏ từ live stream — dùng liveProductId (live_session_products.id)
  Future<CartItemModel> addItemFromLive({
    required String liveProductId,
    required String sessionId,
    int quantity = 1,
  }) async {
    final res = await _dio.post('/api/cart/items/from-live', data: {
      'live_product_id': liveProductId,
      'session_id':      sessionId,
      'quantity':        quantity,
    });
    AppLogger.logUserEvent(
      action: 'live_add_to_cart',
      context: _tag,
      metadata: {'liveProductId': liveProductId, 'quantity': quantity},
    );
    return CartItemModel.fromJson(res.data as Map<String, dynamic>);
  }

  // ── Cập nhật số lượng ────────────────────────────────────────────────────

  Future<CartItemModel> updateQuantity(String itemId, int quantity) async {
    final res = await _dio.patch('/api/cart/items/$itemId/qty',
        data: {'quantity': quantity});
    return CartItemModel.fromJson(res.data as Map<String, dynamic>);
  }

  // ── Tick chọn / bỏ chọn ─────────────────────────────────────────────────

  Future<void> updateSelected(String itemId, {required bool isSelected}) async {
    await _dio.patch('/api/cart/items/$itemId/select',
        data: {'is_selected': isSelected});
  }

  Future<void> selectAll({required bool isSelected}) async {
    await _dio.patch('/api/cart/select-all', data: {'is_selected': isSelected});
  }

  // ── Xoá ──────────────────────────────────────────────────────────────────

  Future<void> removeItem(String itemId) async {
    await _dio.delete('/api/cart/items/$itemId');
    AppLogger.logUserEvent(action: 'remove_from_cart', context: _tag,
        metadata: {'itemId': itemId});
  }

  Future<void> removeSelected() async {
    await _dio.delete('/api/cart/items/selected');
  }
}
