import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/features/user/order/presentation/order_page.dart';
import 'package:tropia_mobile_app_android/features/user/profile/presentation/pages/profile_notification_page.dart';
import 'package:tropia_mobile_app_android/features/user/profile/presentation/pages/profile_voucher_page.dart';
import 'package:tropia_mobile_app_android/features/user/rewards/presentation/rewards_list_screen.dart';

class MockProfileData {
  static const Map<String, dynamic> userProfile = {
    "name": "Khách hàng Tropia",
    "rank": "CHƯA CÓ HẠNG",
    "points": 0,
    "barcode": "371538", // Mã số tích điểm
    "email": "user@example.com",
    "phone": "0123456789",
  };

  // Danh sách menu nhóm 1 (Tiện ích)
  static final List<Map<String, dynamic>> utilityMenu = [
    {
      "icon": Icons.receipt_long_outlined,
      "title": "Đơn hàng",
      "trailing": "",
      "destination": const OrderPage(showAppBar: true),
    },
    {
      "icon": Icons.notifications_outlined,
      "title": "Thông báo",
      "destination": const NotificationsPage(), // Trang đích
    },
    // {
    //   "icon": Icons.account_balance_wallet_outlined,
    //   "title": "Tiền Dư",
    //   "trailing": "0đ",
    //   "destination": const WalletPage(),
    // },
    {
      "icon": Icons.confirmation_number_outlined,
      "title": "Phiếu mua hàng",
      "trailing": "",
      "destination": const MyVouchersPage(),
    },
    {
      "icon": Icons.card_giftcard,
      "title": "Đổi điểm thưởng",
      "trailing": "",
      "destination": const RewardsListScreen(),
      "useSlideRoute": true,
    },
    // Các mục khác tương tự...
    // {
    //   "icon": Icons.card_giftcard,
    //   "title": "Quà của tôi",
    //   "trailing": "",
    //   "destination": const Scaffold(body: Center(child: Text("Đang phát triển")))
    // },
  ];

  // Danh sách menu nhóm 2 (Cài đặt tài khoản)
  static final List<Map<String, dynamic>> settingMenu = [
    {"icon": Icons.person_outline, "title": "Sửa thông tin cá nhân"},
    {"icon": Icons.location_on_outlined, "title": "Địa chỉ nhận hàng"},
  ];
}
