import 'dart:ui';

class DashboardController {
  // Biến lưu trữ hàm callback
  static Function(int)? _onTabChange;

  /// Voucher code chờ áp dụng khi chuyển sang tab Cart
  static String? pendingVoucherCode;

  /// Callback để CartPage tự refresh khi được kích hoạt
  static VoidCallback? _onCartActivated;

  static void registerCartListener(VoidCallback callback) {
    _onCartActivated = callback;
  }

  static void unregisterCartListener() {
    _onCartActivated = null;
  }

  // 1. Dashboard sẽ gọi hàm này để "đăng ký" nhận lệnh
  static void register(Function(int) callback) {
    _onTabChange = callback;
  }

  // 2. NotificationService sẽ gọi hàm này để "ra lệnh" chuyển tab
  static void switchTab(int index) {
    if (_onTabChange != null) {
      _onTabChange!(index);
    }
    // Notify cart page khi switch sang tab cart (index 3)
    if (index == 3 && _onCartActivated != null) {
      _onCartActivated!();
    }
  }
}