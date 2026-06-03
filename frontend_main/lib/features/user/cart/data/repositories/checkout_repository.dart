import '../datasources/checkout_remote_datasource.dart';
import '../models/points_preview_model.dart';

class CheckoutRepository {
  final CheckoutRemoteDataSource remoteDataSource;

  CheckoutRepository({required this.remoteDataSource});

  Future<PointsPreviewModel?> getPointsPreview({
    required int userId,
    required int orderAmount,
  }) async {
    return await remoteDataSource.getPointsPreview(
      userId: userId,
      orderAmount: orderAmount,
    );
  }
}
