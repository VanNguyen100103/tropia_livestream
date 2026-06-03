import 'package:flutter/foundation.dart';
// 1. Import đúng file interface vừa sửa bên trên
import 'package:tropia_mobile_app_android/features/user/order/data/datasources/order_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/models/user_orders.dart';

import '../../domain/repositories/order_repository.dart';

// 2. Thêm "implements OrderRepository" vào đây
class OrderRepositoryImpl implements OrderRepository {
  final OrderRemoteDataSource remoteDataSource;

  OrderRepositoryImpl({required this.remoteDataSource});

  @override
  Future<List<UserOrder>> getUserOrders(int userId) async {
    try {
      debugPrint("DEBUG: Đang gọi API lấy đơn hàng cho User ID: $userId");
      return await remoteDataSource.getUserOrders(userId);
    } catch (e) {
      // Return list rỗng thay vì null để tránh lỗi crash
      debugPrint("Error in Repo: $e");
      return [];
    }
  }

  @override
  Future<UserOrder?> getOrderDetail(String orderId) async {
    try {
      return await remoteDataSource.getOrderDetail(orderId);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<bool> cancelOrder(int userId, String orderId, String cancelReason) async {
    try {
      return await remoteDataSource.cancelOrder(userId, orderId, cancelReason);
    } catch (e) {
      return false;
    }
  }
}
