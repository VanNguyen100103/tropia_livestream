# TROPIA APP – HƯỚNG DẪN KIỂM THỬ (TESTING)

> **Mục tiêu:** Đảm bảo app không crash, tính năng Live hoạt động đúng  
> **Ưu tiên:** Tính năng Live & Video (yếu tố chính của thử việc)

---

## MỤC LỤC

1. [Kiểm thử thủ công (Manual Testing)](#1-kiểm-thử-thủ-công)
2. [Kiểm thử tự động (Unit Test)](#2-kiểm-thử-tự-động)
3. [Kiểm thử hiệu năng](#3-kiểm-thử-hiệu-năng)
4. [Danh sách test case quan trọng](#4-danh-sách-test-case-quan-trọng)
5. [Cách đọc log để debug](#5-cách-đọc-log-để-debug)

---

## 1. Kiểm thử thủ công

### 1.1 – Checklist khởi động app

```
[ ] App mở không crash (không có màn hình đỏ "Error")
[ ] Bottom navigation hiển thị 5 tab: Trang chủ | Khuyến mãi | Live | Giỏ hàng | Cá nhân
[ ] Icon "Live" ở giữa có kiểu dáng đặc biệt (nền cam/đỏ, text "LIVE")
[ ] Có thể chuyển qua lại giữa các tab mà không crash
```

### 1.2 – Checklist Live tab

```
[ ] Mở tab Live → hiển thị danh sách stream cards
[ ] Có 3 tab phụ ở trên: "Video" | "Live" | "Cho bạn"
[ ] Chuyển giữa 3 tab phụ hoạt động
[ ] Mỗi card hiển thị: tên seller, số người xem, thumbnail
[ ] Badge "LIVE" màu đỏ hiển thị trên card đang live
[ ] Shimmer loading effect khi tải danh sách
```

### 1.3 – Checklist màn hình Live Stream

```
[ ] Nhấn vào 1 card → mở màn hình live (toàn màn hình)
[ ] Nền gradient màu (giả lập video stream)
[ ] Hiển thị tên seller + số người xem (góc trên trái)
[ ] Nút "Theo dõi" hiển thị (nếu chưa follow)
[ ] Nút "Khám phá >" hiển thị (góc trên phải)
[ ] "Top nhà sáng tạo" badge hiển thị
[ ] Product card bên trái: ảnh sản phẩm, giá, nút "Mua ngay"
[ ] PHẦN THƯỞNG panel bên phải: điểm danh, đồng hồ, coin
[ ] Chat overlay cuộn tự động
[ ] Comment input bar ở dưới
[ ] Nút Like (tim), Share, Comment count bên phải
[ ] Voucher popup xuất hiện và có thể đóng (nút X)
```

### 1.4 – Checklist tương tác

```
[ ] Nhấn nút Like → trái tim đổi màu đỏ, số tăng lên
[ ] Nhấn Like lần 2 → bỏ like, màu về xám
[ ] Nhấn "Theo dõi" → đổi thành "Đang theo dõi"
[ ] Gõ comment → nhấn gửi → comment xuất hiện trong chat
[ ] Nhấn "Mua ngay" trên product card → mở popup sản phẩm
[ ] Trong popup: có thể bật/tắt "Đặt hàng tự động"
[ ] Nhấn "Lưu" trên voucher → snackbar "Đã lưu voucher"
[ ] Nhấn nút điểm danh → toast thông báo
[ ] Nút back (←) → quay lại danh sách
```

### 1.5 – Kiểm tra crash scenarios

Thử những việc này để đảm bảo app không crash:

```
[ ] Xoay màn hình (portrait ↔ landscape) nhiều lần
[ ] Vào live stream rồi nhấn back nhiều lần nhanh
[ ] Nhấn Like rất nhanh nhiều lần
[ ] Mở nhiều stream liên tiếp
[ ] Để app ở màn hình live 5 phút (test memory leak)
[ ] Bật/tắt internet trong khi xem live
[ ] Nhấn home rồi quay lại app (background/foreground)
```

---

## 2. Kiểm thử tự động

### Chạy tất cả tests

```powershell
cd C:\Users\Admin\Tropia

# Chạy tất cả unit tests
flutter test

# Chạy test với output chi tiết
flutter test --reporter expanded

# Chạy 1 file test cụ thể
flutter test test/features/live/live_provider_test.dart
```

### Tạo test cho LiveProvider

Tạo file `test/features/live/live_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/features/live/providers/live_provider.dart';

void main() {
  group('LiveProvider Tests', () {
    late LiveProvider provider;

    setUp(() {
      provider = LiveProvider();
    });

    tearDown(() {
      provider.dispose();
    });

    test('Khởi tạo: có streams mock', () {
      expect(provider.streams.isNotEmpty, true);
      expect(provider.streams.length, greaterThan(0));
    });

    test('Toggle like: lần 1 → liked = true', () {
      final streamId = provider.streams.first.id;
      provider.toggleLike(streamId);
      expect(provider.isLiked(streamId), true);
    });

    test('Toggle like: lần 2 → liked = false', () {
      final streamId = provider.streams.first.id;
      provider.toggleLike(streamId);
      provider.toggleLike(streamId);
      expect(provider.isLiked(streamId), false);
    });

    test('Toggle follow: hoạt động', () {
      final streamId = provider.streams.first.id;
      provider.toggleFollow(streamId);
      expect(provider.isFollowing(streamId), true);
    });

    test('Gửi comment: comment xuất hiện', () async {
      provider.selectStream(provider.streams.first);
      provider.sendComment('Test comment');
      expect(
        provider.currentComments.any((c) => c.message == 'Test comment'),
        true,
      );
    });
  });
}
```

### Tạo widget test cơ bản

Tạo `test/widget_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tropia/main.dart';

void main() {
  testWidgets('App khởi động không crash', (WidgetTester tester) async {
    await tester.pumpWidget(const TropiaApp());
    await tester.pump(const Duration(seconds: 2));
    
    // Kiểm tra bottom navigation có 5 tab
    expect(find.byType(BottomNavigationBar), findsOneWidget);
  });
}
```

---

## 3. Kiểm thử hiệu năng

### Chạy profile mode (đo hiệu năng)

```powershell
# Profile mode: gần với release nhưng có DevTools
flutter run --profile
```

### Dùng Flutter DevTools

```powershell
# Mở DevTools trong browser
flutter pub global activate devtools
flutter pub global run devtools

# Hoặc từ VS Code: F1 → "Flutter: Open DevTools"
```

**Các chỉ số cần kiểm tra:**
- **Frame rate**: phải đạt 60fps khi cuộn chat
- **Memory**: không tăng liên tục (memory leak)
- **CPU**: không quá 30% khi idle

### Kiểm tra rebuild không cần thiết

Trong VS Code, thêm vào `main.dart` tạm thời:
```dart
// Thêm vào MaterialApp
showPerformanceOverlay: true, // Xóa trước khi release
```

Thanh màu xanh/đỏ ở trên: xanh = tốt, đỏ = vấn đề.

---

## 4. Danh sách test case quan trọng

### TC001 – Mở Live tab (CRITICAL)

| Bước | Hành động | Kết quả mong đợi |
|------|-----------|-----------------|
| 1 | Nhấn tab Live | Không crash |
| 2 | Quan sát | Hiện danh sách stream |
| 3 | Đợi 2 giây | Không crash sau load |

**Pass/Fail:** ___

### TC002 – Vào màn hình live stream (CRITICAL)

| Bước | Hành động | Kết quả mong đợi |
|------|-----------|-----------------|
| 1 | Nhấn vào bất kỳ stream card | Mở màn hình full-screen |
| 2 | Quan sát layout | Product card trái, rewards phải |
| 3 | Đợi 3 giây | Chat tự động cập nhật |
| 4 | Nhấn back | Quay lại danh sách |

**Pass/Fail:** ___

### TC003 – Tương tác Like (HIGH)

| Bước | Hành động | Kết quả mong đợi |
|------|-----------|-----------------|
| 1 | Vào 1 stream | - |
| 2 | Nhấn nút Like | Tim đỏ, số tăng |
| 3 | Nhấn lại | Tim xám, số giảm |

**Pass/Fail:** ___

### TC004 – Gửi comment (HIGH)

| Bước | Hành động | Kết quả mong đợi |
|------|-----------|-----------------|
| 1 | Vào 1 stream | - |
| 2 | Nhấn vào ô comment | Bàn phím hiện lên |
| 3 | Gõ "Xin chào" | Hiện trong ô |
| 4 | Nhấn gửi | Comment xuất hiện trong chat |

**Pass/Fail:** ___

### TC005 – Mua sản phẩm (HIGH)

| Bước | Hành động | Kết quả mong đợi |
|------|-----------|-----------------|
| 1 | Vào 1 stream | - |
| 2 | Nhấn "Mua ngay" | Popup sản phẩm hiện |
| 3 | Bật "Đặt hàng tự động" | Confirmation dialog |
| 4 | Nhấn "Đặt hàng" | Snackbar "Đặt hàng thành công" |

**Pass/Fail:** ___

### TC006 – Follow seller (MEDIUM)

| Bước | Hành động | Kết quả mong đợi |
|------|-----------|-----------------|
| 1 | Vào 1 stream | Nút "Theo dõi" hiện |
| 2 | Nhấn "Theo dõi" | Đổi thành "Đang theo dõi" |

**Pass/Fail:** ___

---

## 5. Cách đọc log để debug

### Xem log trong VS Code

Log của app hiển thị ở terminal khi chạy `flutter run`. Tìm dòng có prefix:

```
ℹ️ [INFO] [LiveProvider] selectStream: Đang xem stream: Con Cưng
⚠️ [WARNING] ...
❌ [ERROR] ...
🎯 [USER_EVENT] like_toggled: streamId=xxx, liked=true
```

### Log quan trọng cần chú ý

```
# Khi vào stream:
🎯 [USER_EVENT] stream_opened: streamId=xxx, title=Con Cưng

# Khi crash xảy ra:
❌ [ERROR] [FlutterError] RenderFlex overflowed...

# Khi gặp lỗi network:
❌ [ERROR] [LiveProvider] Lỗi tải danh sách streams
```

### Debug crash: đọc stack trace

Khi app crash, VS Code hiện màn đỏ với dòng như:
```
The following _TypeError was thrown building LiveStreamScreen:
type 'Null' is not a subtype of type 'String'
```

**Cách xử lý:**
1. Đọc dòng "at" đầu tiên trong stack trace → đó là file và dòng bị lỗi
2. Mở file đó → tìm dòng đó
3. Kiểm tra biến nào có thể null

### Lọc log theo tag

```powershell
# Lọc chỉ xem log của LiveProvider
flutter run 2>&1 | Select-String "LiveProvider"

# Lọc USER_EVENT
flutter run 2>&1 | Select-String "USER_EVENT"
```

---

## Checklist trước khi nộp thử việc

```
[ ] flutter analyze → 0 errors, 0 warnings
[ ] flutter test → All tests pass
[ ] Tất cả TC001-TC006 đều Pass
[ ] App không crash sau 10 phút sử dụng
[ ] Live tab hiện đầy đủ danh sách streams
[ ] Màn hình live có đầy đủ UI như Shopee Live
[ ] Log xuất hiện khi tương tác
[ ] Build APK thành công: flutter build apk --debug
```
