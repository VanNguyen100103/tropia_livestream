import 'package:tropia_mobile_app_android/features/user/cart/data/models/store_model.dart';
import 'package:tropia_mobile_app_android/features/user/cart/data/models/user_address_model.dart';

import '../../data/models/cart_model.dart';

abstract class CartRepository {
  // Hàm lấy giỏ hàng
  Future<CartModel?> getCart(int userId);

  // Trả về "SUCCESS" nếu thành công.
  // Trả về nội dung lỗi (ví dụ: "Sản phẩm hết hàng") nếu thất bại.
  Future<String> addToCart(
    int userId,
    String productId,
    int quantity, {
    int? optionId,
  });

  // Hàm cập nhật số lượng (dùng cho tính năng tăng/giảm)
  Future<bool> updateCart(
    int userId,
    String productId,
    int quantity, {
    int? optionId,
  });

  Future<List<UserAddressModel>> getUserAddresses(int userId);
  Future<List<StoreModel>> getListStores();
}
