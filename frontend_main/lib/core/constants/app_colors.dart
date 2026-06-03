import 'package:flutter/material.dart';

class AppColors {
  // --- MÀU THƯƠNG HIỆU CHÍNH (MỚI: ĐEN) ---
  // Dùng cho Header, Nút chính (trạng thái bình thường), Icon chính
  static const Color primary = Color(
    0xFF212121,
  ); // Đen nhám (Dark Grey) - Nhìn sang hơn đen tuyền

  // --- MÀU NHẤN (ACCENT) - DÙNG KHI TƯƠNG TÁC (CAM) ---
  // Dùng cho: Nút đang bấm (Pressed), Giá tiền, Sale tag, Icon đang chọn
  static const Color accent = Color(0xFFFF5722); // Cam đậm
  static const Color accentLight = Color(0xFFFFCCBC); // Cam nhạt (nền mờ)

  // --- MÀU THỰC PHẨM / TƯƠI SỐNG (XANH LÁ) ---
  // Vẫn giữ lại để dùng cho các nút tích cực như "Thêm vào giỏ", "Freeship"
  static const Color greenFresh = Color(0xFF2E7D32);
  static const Color greenLight = Color(0xFFE8F5E9);

  // --- MÀU KHUYẾN MÃI / CẢNH BÁO (ĐỎ) ---
  static const Color redSale = Color(0xFFFF1744);

  // --- CÁC MÀU CHỨC NĂNG KHÁC ---
  static const Color star = Color(0xFFFFC107);
  static const Color blueLink = Color(0xFF1976D2);

  // --- MÀU NỀN & VĂN BẢN ---
  static const Color background = Color(0xFFF5F5F5); // Xám nhạt
  static const Color white = Colors.white;
  static const Color black = Colors.black; // Đen tuyền cho chữ

  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);
  static const Color border = Color(0xFFEEEEEE);
}
