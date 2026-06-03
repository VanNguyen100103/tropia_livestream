// =============================================================================
// chat_command_parser.dart
// =============================================================================
// Parser cho hệ thống lệnh tự động đặt hàng qua chat live.
//
// CÚ PHÁP LỆNH:
//   /mua [slot] [qty?]   → đặt hàng sản phẩm số [slot], SL mặc định = 1
//   /mua 3 2             → sản phẩm số 3, số lượng 2
//   /mua 3 x2            → sản phẩm số 3, số lượng 2 (cú pháp x)
//   /sp [slot]           → xem chi tiết sản phẩm
//   /gia [slot]          → xem giá sản phẩm
//   /con [slot]          → xem tồn kho sản phẩm
//   /voucher             → xem danh sách voucher đang có
//   /luu [code]          → lưu voucher theo mã
//   /giohang             → xem giỏ hàng hiện tại
//   /xoa [slot]          → xóa sản phẩm khỏi giỏ hàng
//   /dat                 → xác nhận đặt tất cả trong giỏ
//
// QUY ĐỊNH:
//   - slot = số thứ tự sản phẩm trong live (bắt đầu từ 1)
//   - Lệnh không phân biệt hoa thường
//   - Khoảng trắng thừa được bỏ qua
//   - parse() trả về null nếu không phải lệnh hợp lệ
// =============================================================================

/// Kết quả parse lệnh chat — sealed class (Dart 3+)
sealed class ChatCommand {
  const ChatCommand();
}

/// /mua [slot] [qty?]
class BuyCommand extends ChatCommand {
  final int productSlot;
  final int quantity;
  const BuyCommand({required this.productSlot, this.quantity = 1});
}

/// /sp [slot]
class ViewProductCommand extends ChatCommand {
  final int productSlot;
  const ViewProductCommand({required this.productSlot});
}

/// /gia [slot]
class PriceCommand extends ChatCommand {
  final int productSlot;
  const PriceCommand({required this.productSlot});
}

/// /con [slot]
class StockCommand extends ChatCommand {
  final int productSlot;
  const StockCommand({required this.productSlot});
}

/// /voucher
class VoucherListCommand extends ChatCommand {
  const VoucherListCommand();
}

/// /luu [code]
class SaveVoucherCommand extends ChatCommand {
  final String code;
  const SaveVoucherCommand({required this.code});
}

/// /giohang
class CartViewCommand extends ChatCommand {
  const CartViewCommand();
}

/// /xoa [slot]
class CartRemoveCommand extends ChatCommand {
  final int productSlot;
  const CartRemoveCommand({required this.productSlot});
}

/// /dat
class CheckoutCommand extends ChatCommand {
  const CheckoutCommand();
}

// =============================================================================
// Parser
// =============================================================================

class ChatCommandParser {
  // Regex cho từng lệnh — compile 1 lần, tái dùng nhiều lần
  static final _buyRx = RegExp(
    r'^/mua\s+(\d+)(?:\s+x?(\d+))?$',
    caseSensitive: false,
  );
  static final _viewRx = RegExp(r'^/sp\s+(\d+)$', caseSensitive: false);
  static final _priceRx = RegExp(r'^/gia\s+(\d+)$', caseSensitive: false);
  static final _stockRx = RegExp(r'^/con\s+(\d+)$', caseSensitive: false);
  static final _voucherListRx = RegExp(r'^/voucher$', caseSensitive: false);
  static final _saveVoucherRx = RegExp(
    r'^/luu\s+(\S+)$',
    caseSensitive: false,
  );
  static final _cartRx = RegExp(r'^/giohang$', caseSensitive: false);
  static final _removeRx = RegExp(r'^/xoa\s+(\d+)$', caseSensitive: false);
  static final _checkoutRx = RegExp(r'^/dat$', caseSensitive: false);

  /// Parse một chuỗi text thành [ChatCommand].
  /// Trả về null nếu không phải lệnh hợp lệ.
  static ChatCommand? parse(String text) {
    final t = text.trim();
    if (!t.startsWith('/')) return null;

    RegExpMatch? m;

    m = _buyRx.firstMatch(t);
    if (m != null) {
      final slot = int.tryParse(m.group(1) ?? '') ?? 0;
      final qty = int.tryParse(m.group(2) ?? '') ?? 1;
      if (slot <= 0 || qty <= 0 || qty > 99) return null;
      return BuyCommand(productSlot: slot, quantity: qty);
    }

    m = _viewRx.firstMatch(t);
    if (m != null) {
      final slot = int.tryParse(m.group(1) ?? '') ?? 0;
      if (slot <= 0) return null;
      return ViewProductCommand(productSlot: slot);
    }

    m = _priceRx.firstMatch(t);
    if (m != null) {
      final slot = int.tryParse(m.group(1) ?? '') ?? 0;
      if (slot <= 0) return null;
      return PriceCommand(productSlot: slot);
    }

    m = _stockRx.firstMatch(t);
    if (m != null) {
      final slot = int.tryParse(m.group(1) ?? '') ?? 0;
      if (slot <= 0) return null;
      return StockCommand(productSlot: slot);
    }

    if (_voucherListRx.hasMatch(t)) return const VoucherListCommand();

    m = _saveVoucherRx.firstMatch(t);
    if (m != null) {
      final code = m.group(1) ?? '';
      if (code.isEmpty) return null;
      return SaveVoucherCommand(code: code.toUpperCase());
    }

    if (_cartRx.hasMatch(t)) return const CartViewCommand();

    m = _removeRx.firstMatch(t);
    if (m != null) {
      final slot = int.tryParse(m.group(1) ?? '') ?? 0;
      if (slot <= 0) return null;
      return CartRemoveCommand(productSlot: slot);
    }

    if (_checkoutRx.hasMatch(t)) return const CheckoutCommand();

    return null; // lệnh không nhận ra
  }

  /// Kiểm tra có phải lệnh (bắt đầu bằng /) hay không, không cần parse đầy đủ.
  static bool isCommand(String text) => text.trim().startsWith('/');

  /// Trả về text hướng dẫn hiển thị khi user gõ /help trong chat.
  static String get helpText => '''
📋 *Lệnh đặt hàng qua chat:*
• /mua [số] — thêm vào giỏ (VD: /mua 2)
• /mua [số] [sl] — chỉ định số lượng (VD: /mua 2 3)
• /sp [số] — xem sản phẩm
• /gia [số] — xem giá
• /con [số] — xem tồn kho
• /voucher — danh sách voucher
• /luu [mã] — lưu voucher
• /giohang — xem giỏ hàng
• /xoa [số] — xóa khỏi giỏ
• /dat — đặt hàng ngay''';
}
