// =============================================================================
// initials_avatar.dart
// =============================================================================
// Avatar tròn dùng chung: thử load [imageUrl] (logo shop / ảnh user) trước; nếu
// null hoặc load LỖI thì vẽ chữ-cái-đầu của [name] NGAY trong app (giống
// Shopee/TikTok) thay vì để trống.
//
// Lý do cần fallback cục bộ: trên Flutter Web, ảnh avatar mặc định trỏ tới dịch
// vụ ngoài (ui-avatars.com) bị trình duyệt chặn vì header CORS hỏng
// ('Access-Control-Allow-Origin: *, *' — lặp giá trị), nên CachedNetworkImage
// luôn errorWidget. Vẽ initials cục bộ không phụ thuộc mạng/CORS/encoding.
// =============================================================================

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';

class InitialsAvatar extends StatelessWidget {
  /// URL ảnh (logo shop / avatar user). null → vẽ initials luôn.
  final String? imageUrl;

  /// Tên hiển thị để lấy chữ cái đầu khi không có ảnh.
  final String name;

  /// Bán kính avatar (px). Cỡ chữ + icon co theo bán kính.
  final double radius;

  const InitialsAvatar({
    super.key,
    required this.imageUrl,
    required this.name,
    this.radius = 24,
  });

  @override
  Widget build(BuildContext context) {
    final url = _usableUrl(imageUrl);
    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: url != null
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, _) => _fallback(),
                errorWidget: (_, _, _) => _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  /// URL ảnh dùng được, hoặc null để vẽ initials cục bộ.
  ///
  /// Bỏ qua URL trỏ tới ui-avatars.com: dịch vụ này trả về header CORS hỏng
  /// ('Access-Control-Allow-Origin: *, *' — lặp giá trị) nên trên Flutter Web
  /// trình duyệt CHẶN ảnh và spam lỗi console (net::ERR_FAILED) ngay cả khi ta
  /// có errorWidget. Vì avatar mặc định kiểu ui-avatars chỉ là chữ-cái-đầu, ta
  /// tự vẽ initials cục bộ thay thế — không gọi mạng, không phụ thuộc CORS.
  /// (Backend cũng đã ngừng sinh URL kiểu này; guard này phủ luôn dữ liệu cũ.)
  static String? _usableUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
    if (host == 'ui-avatars.com' || host.endsWith('.ui-avatars.com')) {
      return null;
    }
    return url;
  }

  Widget _fallback() {
    final initials = initialsOf(name);
    if (initials.isEmpty) {
      return Container(
        color: AppColors.primaryContainer,
        alignment: Alignment.center,
        child: Icon(Icons.person, color: AppColors.primary, size: radius),
      );
    }
    return Container(
      color: AppColors.primary,
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          color: Colors.white,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// Tối đa 2 chữ cái đầu: 2 từ đầu của tên ("Nguyễn Văn A's Shop" → "NV") hoặc
  /// 2 ký tự đầu nếu tên chỉ 1 từ. Ký tự tiếng Việt precomposed đều trong BMP
  /// (1 UTF-16 code unit) nên substring an toàn.
  static String initialsOf(String name) {
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) return '';
    if (words.length == 1) {
      final w = words.first;
      return (w.length >= 2 ? w.substring(0, 2) : w).toUpperCase();
    }
    return (words[0].substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
  }
}
