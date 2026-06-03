// Lưu ý: Import đúng đường dẫn file model UserOrder bạn vừa tạo
import 'package:tropia_mobile_app_android/features/user/order/data/models/user_orders.dart';


abstract class OrderRepository {
  // Lấy danh sách đơn hàng
  Future<List<UserOrder>> getUserOrders(int userId);
  
  // Lấy chi tiết một đơn hàng
  Future<UserOrder?> getOrderDetail(String orderId);

  // Hủy đơn hàng
  Future<bool> cancelOrder(int userId, String orderId, String cancelReason);
}