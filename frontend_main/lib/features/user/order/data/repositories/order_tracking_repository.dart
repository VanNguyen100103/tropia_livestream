/// Order Tracking Repository
/// Repository layer for order tracking data access
library;

import 'package:tropia_mobile_app_android/features/user/order/data/datasources/order_tracking_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/models/order_tracking_model.dart';

class OrderTrackingRepository {
  final OrderTrackingRemoteDataSource remoteDataSource;

  OrderTrackingRepository({required this.remoteDataSource});

  /// Get order tracking information
  Future<OrderTrackingModel?> getOrderTracking(String orderId) async {
    return await remoteDataSource.getOrderTracking(orderId);
  }
}
