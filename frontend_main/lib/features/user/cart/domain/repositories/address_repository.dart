import 'package:flutter/foundation.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/datasources/cart_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/models/user_address_model.dart';

class AddressRepository {
  final CartRemoteDataSource remoteDataSource;

  // Inject Datasource vào đây để sử dụng
  AddressRepository({required this.remoteDataSource});

  // Hàm này sẽ gọi xuống Datasource đã viết ở bước trước
  Future<List<UserAddressModel>> getUserAddresses(int userId) async {
    try {
      return await remoteDataSource.getUserAddresses(userId);
    } catch (e) {
      debugPrint("❌ Lỗi AddressRepository: $e");
      return [];
    }
  }
}