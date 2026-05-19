// =============================================================================
// app_constants.dart
// =============================================================================
// Tập trung tất cả hằng số dùng trong toàn bộ ứng dụng Tropia:
//   - Màu sắc thương hiệu (AppColors)
//   - Chuỗi văn bản tĩnh (AppStrings)
//   - Kích thước & spacing (AppSizes)
//   - URL & endpoint mock (AppUrls)
//
// HƯỚNG DẪN SỬ DỤNG:
//   import 'package:tropia/core/constants/app_constants.dart';
//   Container(color: AppColors.primary)
//   Text(AppStrings.appName)
// =============================================================================

import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MÀU SẮC
// ─────────────────────────────────────────────────────────────────────────────

/// Bảng màu thương hiệu Tropia.
///
/// - [primary]: Xanh lá đậm – màu chủ đạo của Tropia
/// - [primaryLight]: Xanh lá nhạt – dùng cho nền, hover states
/// - [secondary]: Cam – dùng cho giá cả, khuyến mãi, CTA nổi bật
/// - [accent]: Xanh lá nhạt hơn – highlight nhỏ
/// - [background]: Nền tổng thể (trắng xám nhạt)
/// - [surface]: Nền thẻ card (trắng)
/// - [error]: Đỏ cảnh báo
/// - [textPrimary]: Chữ chính (gần đen)
/// - [textSecondary]: Chữ phụ (xám)
/// - [textHint]: Placeholder, mờ
/// - [divider]: Đường kẻ phân cách
/// - [gold]: Vàng – dùng cho phần thưởng, huy hiệu
/// - [liveRed]: Đỏ – badge "LIVE" đang phát
/// - [overlayDark]: Lớp phủ tối bán trong suốt
abstract class AppColors {
  // Tropia brand greens
  static const Color primary = Color(0xFF2E7D32);
  static const Color primaryLight = Color(0xFF4CAF50);
  static const Color primaryDark = Color(0xFF1B5E20);
  static const Color primaryContainer = Color(0xFFE8F5E9);

  // Secondary – cam/orange (giá, CTA)
  static const Color secondary = Color(0xFFFF6B35);
  static const Color secondaryLight = Color(0xFFFF8A65);
  static const Color secondaryDark = Color(0xFFE64A19);

  // Accent
  static const Color accent = Color(0xFF81C784);

  // Backgrounds & surfaces
  static const Color background = Color(0xFFF5F5F5);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF0F4F0);

  // Text
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF757575);
  static const Color textHint = Color(0xFFBDBDBD);
  static const Color textOnPrimary = Color(0xFFFFFFFF);
  static const Color textOnSecondary = Color(0xFFFFFFFF);

  // Utility
  static const Color divider = Color(0xFFE0E0E0);
  static const Color error = Color(0xFFD32F2F);
  static const Color success = Color(0xFF388E3C);
  static const Color warning = Color(0xFFF57C00);

  // Live & Video specific
  static const Color liveRed = Color(0xFFE53935);
  static const Color gold = Color(0xFFFFD700);
  static const Color goldDark = Color(0xFFFF8F00);
  static const Color overlayDark = Color(0x99000000);
  static const Color overlayLight = Color(0x33FFFFFF);
  static const Color chatBubble = Color(0x80000000);

  // Bottom nav
  static const Color navSelected = Color(0xFF2E7D32);
  static const Color navUnselected = Color(0xFF9E9E9E);
  static const Color navBackground = Color(0xFFFFFFFF);
}

// ─────────────────────────────────────────────────────────────────────────────
// CHUỖI VĂN BẢN
// ─────────────────────────────────────────────────────────────────────────────

/// Toàn bộ chuỗi tĩnh hiển thị trong UI, được tập trung ở đây
/// để dễ dàng dịch sang đa ngôn ngữ (i18n) sau này.
abstract class AppStrings {
  // App info
  static const String appName = 'Tropia';
  static const String appTagline = 'Thực phẩm tươi – Giao nhanh';

  // Bottom navigation labels
  static const String navHome = 'Trang chủ';
  static const String navPromotion = 'Khuyến mãi';
  static const String navLive = 'Live';
  static const String navCart = 'Giỏ hàng';
  static const String navProfile = 'Cá nhân';

  // Live & Video screen
  static const String liveTabVideo = 'Video';
  static const String liveTabLive = 'Live';
  static const String liveTabForYou = 'Cho bạn';
  static const String liveViewers = 'người xem';
  static const String liveFollow = 'Theo dõi';
  static const String liveFollowing = 'Đang theo dõi';
  static const String liveExplore = 'Khám phá';
  static const String liveCreatorBadge = 'Top nhà sáng tạo';
  static const String liveRewardPanel = 'PHẦN THƯỞNG';
  static const String liveRewardTap = 'Nhấn để nhận thưởng';
  static const String liveAttendance = 'Điểm danh';
  static const String liveCoins = 'xu';
  static const String liveWatchToEarn = 'Xem để nhận xu';
  static const String liveBuyNow = 'Mua ngay';
  static const String liveAutoOrder = 'Đặt hàng tự động';
  static const String liveCommentHint = 'Bạn đang nghĩ gì...';
  static const String liveSaveVoucher = 'Lưu voucher';
  static const String liveSaved = 'Đã lưu';
  static const String liveDiscount = 'Giảm';
  static const String liveLoading = 'Đang tải buổi phát sóng...';
  static const String liveEmpty = 'Chưa có buổi phát sóng nào';
  static const String liveError = 'Không thể tải dữ liệu. Thử lại sau.';

  // Product popup
  static const String productAddToCart = 'Thêm vào giỏ';
  static const String productBuyNow = 'Mua ngay';
  static const String productStock = 'Còn lại';
  static const String productItems = 'sản phẩm';
  static const String productSold = 'Đã bán';

  // Auto order
  static const String autoOrderTitle = 'Đặt hàng tự động';
  static const String autoOrderConfirm =
      'Bật tính năng này sẽ tự động đặt hàng khi giá đạt mức bạn mong muốn.';
  static const String autoOrderEnabled = 'Đã bật đặt hàng tự động';
  static const String autoOrderDisabled = 'Đã tắt đặt hàng tự động';
  static const String autoOrderPlaced = 'Đơn hàng đã được đặt tự động!';

  // Common actions
  static const String actionConfirm = 'Xác nhận';
  static const String actionCancel = 'Huỷ';
  static const String actionClose = 'Đóng';
  static const String actionRetry = 'Thử lại';
  static const String actionShare = 'Chia sẻ';
  static const String actionLike = 'Thích';

  // Host live
  static const String hostLiveTitle = 'Tạo buổi Live';
  static const String hostLiveStart = 'Bắt đầu Live';
  static const String hostLiveEnd = 'Kết thúc Live';
  static const String hostLiveEndConfirm = 'Bạn có chắc muốn kết thúc buổi live?';
  static const String hostLiveTitleHint = 'Tiêu đề buổi live (VD: Flash sale hôm nay!)';
  static const String hostLiveCategoryHint = 'Chọn danh mục';
  static const String hostLiveAddProduct = 'Thêm sản phẩm';
  static const String hostLivePinProduct = 'Ghim sản phẩm';
  static const String hostLiveViewers = 'Người xem';
  static const String hostLiveOrders = 'Đơn hàng';
  static const String hostLiveRevenue = 'Doanh thu';
  static const String hostLiveDuration = 'Thời lượng';
  static const String hostLiveSummary = 'Tổng kết buổi Live';
  static const String hostLiveCameraOff = 'Camera đang tắt\n(Mock mode)';

  // Notifications / snackbars
  static const String notifVoucherSaved = 'Đã lưu voucher thành công!';
  static const String notifRewardClaimed = 'Bạn đã nhận được phần thưởng!';
  static const String notifFollowSuccess = 'Đã theo dõi cửa hàng!';
  static const String notifCommentSent = 'Bình luận đã được gửi!';
  static const String notifShareSuccess = 'Đã chia sẻ buổi live!';
  static const String notifOrderPlaced = 'Đã đặt hàng thành công!';
  static const String notifAddedToCart = 'Đã thêm vào giỏ hàng!';
}

// ─────────────────────────────────────────────────────────────────────────────
// KÍCH THƯỚC & SPACING
// ─────────────────────────────────────────────────────────────────────────────

/// Hệ thống kích thước cố định – sử dụng nhất quán trong toàn dự án.
///
/// Quy ước đặt tên:
///   - [xs] = extra small (4dp)
///   - [sm] = small (8dp)
///   - [md] = medium (16dp)
///   - [lg] = large (24dp)
///   - [xl] = extra large (32dp)
///   - [xxl] = 48dp
abstract class AppSizes {
  // Spacing
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 16.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
  static const double xxl = 48.0;

  // Border radius
  static const double radiusSm = 4.0;
  static const double radiusMd = 8.0;
  static const double radiusLg = 12.0;
  static const double radiusXl = 16.0;
  static const double radiusFull = 100.0; // pill shape

  // Icon sizes
  static const double iconSm = 16.0;
  static const double iconMd = 24.0;
  static const double iconLg = 32.0;
  static const double iconXl = 48.0;

  // Avatar sizes
  static const double avatarSm = 32.0;
  static const double avatarMd = 40.0;
  static const double avatarLg = 56.0;

  // Font sizes
  static const double fontXs = 10.0;
  static const double fontSm = 12.0;
  static const double fontMd = 14.0;
  static const double fontLg = 16.0;
  static const double fontXl = 18.0;
  static const double fontXxl = 22.0;
  static const double fontTitle = 26.0;

  // Live screen specific
  static const double productCardWidth = 130.0;
  static const double rewardPanelWidth = 90.0;
  static const double bottomBarHeight = 56.0;
  static const double tabBarHeight = 40.0;
  static const double liveCardHeight = 200.0;
  static const double liveCardWidth = 150.0;

  // Bottom nav
  static const double bottomNavHeight = 60.0;
}

// ─────────────────────────────────────────────────────────────────────────────
// URL & ENDPOINT
// ─────────────────────────────────────────────────────────────────────────────

abstract class AppUrls {
  // Placeholder images – chỉ dùng khi backend không trả về URL ảnh
  static const String placeholderProduct =
      'https://picsum.photos/seed/product/300/300';
  static const String placeholderAvatar =
      'https://picsum.photos/seed/avatar/100/100';
  static const String placeholderBanner =
      'https://picsum.photos/seed/banner/800/400';
}

// ─────────────────────────────────────────────────────────────────────────────
// DURATION CONSTANTS (dùng cho animation)
// ─────────────────────────────────────────────────────────────────────────────

abstract class AppDurations {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 500);
  static const Duration verySlow = Duration(milliseconds: 800);

  // Live feature
  static const Duration commentScroll = Duration(milliseconds: 400);
  static const Duration emojiFloat = Duration(seconds: 2);
  static const Duration popupShow = Duration(milliseconds: 250);
}
