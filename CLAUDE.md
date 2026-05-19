# Tropia – Live & Video Feature Module

## Tổng quan dự án

Tropia là ứng dụng mua sắm thực phẩm tươi sống Việt Nam, được xây dựng bằng Flutter.
Module **Live & Video** (tính năng chính trong codebase này) cho phép người dùng xem và tương tác với các buổi livestream bán hàng – tương tự Shopee Live.

## Yêu cầu

- Flutter 3.x (SDK ≥ 3.0.0)
- Dart ≥ 3.0.0
- Android Studio hoặc VS Code với Flutter extension

## Chạy dự án

```bash
flutter pub get
flutter run
```

## Cấu trúc thư mục

```
lib/
├── main.dart                          # Entry point
├── core/
│   ├── constants/app_constants.dart   # AppColors, AppStrings, AppSizes, AppUrls
│   ├── theme/app_theme.dart           # ThemeData Tropia (light + dark)
│   └── utils/logger.dart             # AppLogger – ghi log tập trung
└── features/
    ├── main/screens/main_screen.dart  # Bottom nav 5 tabs
    ├── home/screens/home_screen.dart  # Tab Trang chủ
    └── live/                          # Module Live & Video
        ├── models/live_stream_model.dart   # Models: LiveStream, LiveProduct, ...
        ├── providers/live_provider.dart    # State management (ChangeNotifier)
        ├── screens/
        │   ├── live_tab_screen.dart        # Danh sách streams (grid)
        │   └── live_stream_screen.dart     # Màn hình xem live đầy đủ
        └── widgets/
            ├── live_card_widget.dart           # Card trong danh sách
            ├── live_actions_widget.dart        # Like/Share/Comment bên phải
            ├── live_chat_widget.dart           # Chat overlay
            ├── live_product_card_widget.dart   # Card sản phẩm bên trái
            ├── live_product_popup.dart         # Popup chi tiết sản phẩm
            ├── live_reward_widget.dart         # Panel PHẦN THƯỞNG
            └── live_voucher_popup.dart         # Popup voucher
```

## Kiến trúc State Management

Dùng **Provider** package (ChangeNotifier pattern):

```
LiveProvider (ChangeNotifier)
    ↑ provides to
LiveTabScreen → LiveStreamScreen → [all widgets]
```

Provider được đặt ở `MainScreen` bọc toàn bộ tab Live.

## Logging

Dùng `AppLogger` (không import trực tiếp `logger` package):

```dart
AppLogger.logInfo('MyWidget', 'Message here');
AppLogger.logError('MyProvider', 'Failed', error, stackTrace);
AppLogger.logUserEvent(
  action: 'button_tapped',
  context: 'MyScreen',
  metadata: {'key': 'value'},
);
```

## Mock Data

`LiveProvider._buildMockStreams()` tạo 6 streams giả:
1. Con Cưng Official (Mẹ & Bé, LIVE)
2. Lạc Yên Foods (Thực phẩm, LIVE)
3. PUMA Official Vietnam (Thời trang, LIVE)
4. Shondo Shoes (Giày dép, LIVE)
5. Beauty by Linh Nguyễn (Mỹ phẩm, LIVE)
6. Tropia Fresh Market (VOD, đã kết thúc)

## Tính năng đặt hàng tự động

Trong `LiveProductCardWidget` và `LiveProductPopup`:
- Toggle switch "Đặt hàng tự động"
- Khi bật: hiện AlertDialog xác nhận → `provider.toggleAutoOrder()`
- Sau 2 giây: gọi `provider.placeAutoOrder()` (mock log)
- Log event: `auto_order_enabled`, `auto_order_placed`

## Dependencies chính

| Package | Mục đích |
|---------|----------|
| provider | State management |
| cached_network_image | Load ảnh từ URL với cache |
| shimmer | Loading placeholder |
| logger | Logging engine |
| video_player + chewie | Sẵn sàng cho video thực (chưa integrate) |

## Ghi chú cho developer mới

1. **Không dùng màu inline** – luôn dùng `AppColors.xxx`
2. **Không dùng string hardcode** – dùng `AppStrings.xxx`
3. **Log mọi tương tác** – dùng `AppLogger.logUserEvent()`
4. **Mock data** ở `live_provider.dart:_buildMockStreams()` – thay bằng API call khi có backend
5. **Video stream** – hiện dùng gradient placeholder; tích hợp `chewie` khi có URL HLS thực
