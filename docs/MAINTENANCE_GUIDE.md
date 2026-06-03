# TROPIA APP – HƯỚNG DẪN VẬN HÀNH & BẢO TRÌ

> **QUAN TRỌNG:** Đọc kỹ mục "Sự cố khẩn cấp" trước – đây là thứ tránh bạn bị phạt tiền

---

## MỤC LỤC

1. [Sự cố khẩn cấp (ĐỌC TRƯỚC)](#1-sự-cố-khẩn-cấp)
2. [Cập nhật dependencies (packages)](#2-cập-nhật-dependencies)
3. [Cấu trúc code – Nơi sửa gì ở đâu](#3-cấu-trúc-code)
4. [Thêm tính năng mới](#4-thêm-tính-năng-mới)
5. [Quy trình làm việc hàng ngày](#5-quy-trình-làm-việc-hàng-ngày)
6. [Backup và version control](#6-backup-và-version-control)
7. [Theo dõi crash trong production](#7-theo-dõi-crash-production)

---

## 1. Sự cố khẩn cấp

### 🚨 App crash ngay khi mở (sau update)

```powershell
# Bước 1: Rollback ngay lập tức
git revert HEAD
git push

# Hoặc nếu chưa dùng git, restore file backup

# Bước 2: Xác định nguyên nhân
flutter clean
flutter pub get
flutter run
# Đọc log, tìm dòng ERROR đầu tiên
```

### 🚨 Crash sau `flutter pub upgrade`

```powershell
# Khôi phục pubspec.lock cũ (file này track version chính xác)
git checkout pubspec.lock
flutter pub get
# App sẽ dùng lại version cũ đã ổn định
```

### 🚨 Build thất bại (màu đỏ trong CI/CD)

```powershell
flutter clean
flutter pub cache repair
flutter pub get
flutter build apk --debug
```

### 🚨 Lỗi "Gradle failed" trên Android

```powershell
cd android
.\gradlew clean
cd ..
flutter clean
flutter pub get
flutter build apk
```

### 🚨 App bị reject trên Google Play vì crash rate cao

1. Mở Google Play Console → Android vitals → Crashes
2. Xem stack trace
3. Tìm file và dòng trong code
4. Fix → build release → upload lại

---

## 2. Cập nhật dependencies

> ⚠️ **NGUY HIỂM:** Cập nhật bừa bãi là nguyên nhân số 1 gây crash

### Quy tắc bất di bất dịch

1. **KHÔNG BAO GIỜ** chạy `flutter pub upgrade` ngay trước deadline
2. **LUÔN** có git commit sạch trước khi upgrade
3. **LUÔN** test kỹ sau khi upgrade
4. Chỉ upgrade từng package một, không upgrade tất cả cùng lúc

### Quy trình an toàn khi cần update

```powershell
# Bước 1: Commit code hiện tại
git add .
git commit -m "safe checkpoint before upgrade"

# Bước 2: Xem version hiện tại và version mới
flutter pub outdated

# Output ví dụ:
# Package    Current  Upgradable  Resolvable  Latest
# provider   6.1.1    6.1.2       6.1.2       6.1.2
# dio        5.4.0    5.4.3       5.4.3       5.7.0

# Bước 3: Chỉ upgrade patch version (x.x.PATCH - an toàn)
# KHÔNG upgrade minor/major nếu không cần thiết

# Bước 4: Upgrade từng package
flutter pub add provider:^6.1.2  # ví dụ

# Bước 5: Test kỹ
flutter analyze
flutter test
flutter run
# Test manual tất cả tính năng Live

# Bước 6: Nếu OK → commit
git add pubspec.yaml pubspec.lock
git commit -m "upgrade provider to 6.1.2 - tested OK"

# Bước 7: Nếu CRASH → rollback
git checkout pubspec.yaml pubspec.lock
flutter pub get
```

### Hiểu version numbering

```
provider: ^6.1.1
         │ │ │
         │ │ └─ PATCH: bug fix, an toàn để upgrade
         │ └─── MINOR: tính năng mới, cần test
         └───── MAJOR: breaking changes, nguy hiểm!

Dấu ^ có nghĩa: chấp nhận cùng MAJOR, MINOR+PATCH mới hơn
```

---

## 3. Cấu trúc code

### Bản đồ files – Sửa gì ở đâu

```
lib/
├── main.dart                          ← Sửa theme, locale, cấu hình chung
│
├── core/
│   ├── constants/app_constants.dart  ← Sửa màu sắc, chuỗi text, kích thước
│   ├── theme/app_theme.dart          ← Sửa font, màu theme, button style
│   └── utils/logger.dart             ← KHÔNG SỬA (trừ khi cần thêm log level)
│
└── features/
    ├── main/screens/main_screen.dart ← Sửa bottom navigation (thêm/bỏ tab)
    │
    ├── home/screens/home_screen.dart ← Sửa màn hình trang chủ
    │
    └── live/
        ├── models/
        │   └── live_stream_model.dart ← Sửa khi API thay đổi cấu trúc data
        │
        ├── providers/
        │   └── live_provider.dart    ← Logic nghiệp vụ Live (state management)
        │                               Sửa khi: thêm tính năng, kết nối API thật
        │
        ├── screens/
        │   ├── live_tab_screen.dart  ← Sửa layout danh sách streams
        │   └── live_stream_screen.dart ← Sửa layout màn hình xem live
        │
        └── widgets/
            ├── live_card_widget.dart       ← Card trong danh sách
            ├── live_chat_widget.dart       ← Chat overlay
            ├── live_product_card_widget.dart ← Card sản phẩm bên trái
            ├── live_product_popup.dart     ← Popup mua sản phẩm
            ├── live_reward_widget.dart     ← Panel phần thưởng
            ├── live_actions_widget.dart    ← Like/share/comment
            └── live_voucher_popup.dart     ← Popup voucher
```

### Kết nối API thật (khi backend sẵn sàng)

Hiện tại app dùng **mock data**. Khi có API thật:

1. Tìm trong `live_provider.dart` các method có comment `// MOCK DATA`
2. Thay bằng gọi API qua `dio`
3. Ví dụ:

```dart
// TRƯỚC (mock):
Future<void> loadStreams() async {
  _streams = _generateMockStreams(); // MOCK DATA
  notifyListeners();
}

// SAU (real API):
Future<void> loadStreams() async {
  try {
    final response = await _dio.get('/api/live/streams');
    _streams = (response.data['data'] as List)
        .map((json) => LiveStream.fromJson(json))
        .toList();
    notifyListeners();
  } on DioException catch (e) {
    AppLogger.logError('LiveProvider', 'loadStreams failed', e);
    // Fallback về mock nếu API lỗi
    _streams = _generateMockStreams();
    notifyListeners();
  }
}
```

---

## 4. Thêm tính năng mới

### Quy trình chuẩn (LUÔN theo thứ tự này)

```
1. Model  →  2. Provider  →  3. Widget  →  4. Screen  →  5. Test
```

### Ví dụ: Thêm tính năng "Tặng quà" (Gift)

**Bước 1 – Thêm model** (`live_stream_model.dart`):
```dart
class LiveGift {
  final String id;
  final String name;
  final int coinCost;
  final String iconUrl;
  const LiveGift({required this.id, required this.name, required this.coinCost, required this.iconUrl});
}
```

**Bước 2 – Thêm logic vào provider** (`live_provider.dart`):
```dart
Future<void> sendGift(String streamId, LiveGift gift) async {
  AppLogger.logUserEvent('gift_sent', {'streamId': streamId, 'gift': gift.name});
  // TODO: Gọi API
  notifyListeners();
}
```

**Bước 3 – Tạo widget** (`lib/features/live/widgets/live_gift_widget.dart`):
```dart
class LiveGiftWidget extends StatelessWidget {
  // ... UI tặng quà
}
```

**Bước 4 – Thêm vào screen** (`live_stream_screen.dart`):
```dart
LiveGiftWidget(onSend: (gift) => provider.sendGift(streamId, gift)),
```

**Bước 5 – Viết test:**
```dart
test('sendGift: log đúng event', () async {
  await provider.sendGift('stream1', testGift);
  // verify log được ghi
});
```

---

## 5. Quy trình làm việc hàng ngày

### Buổi sáng – Bắt đầu làm việc

```powershell
cd C:\Users\Admin\Tropia

# Pull code mới nhất (nếu làm việc nhóm)
git pull origin main

# Cài dependencies mới (nếu có thay đổi pubspec.yaml)
flutter pub get

# Chạy analyze để phát hiện lỗi ngay
flutter analyze

# Chạy test để đảm bảo không có regression
flutter test
```

### Trong ngày – Khi viết code

```powershell
# Hot reload (giữ state) - nhấn r trong terminal
# Hot restart (reset state) - nhấn R trong terminal

# Sau khi sửa xong, kiểm tra ngay:
flutter analyze
```

### Buổi tối – Trước khi kết thúc

```powershell
# Kiểm tra lần cuối
flutter analyze
flutter test

# Commit code
git add .
git commit -m "feat: mô tả ngắn những gì đã làm"

# Push lên remote (nếu có)
git push
```

### Commit message chuẩn

```
feat: thêm tính năng gift trong live stream
fix: sửa crash khi back từ live stream nhanh
style: điều chỉnh màu sắc product card
test: thêm unit test cho live_provider
docs: cập nhật hướng dẫn cài đặt
refactor: tách live_actions thành widget riêng
```

---

## 6. Backup và version control

### Cài đặt Git (nếu chưa có)

```powershell
# Tải từ https://git-scm.com/download/win
# Sau khi cài:
git config --global user.name "Tên của bạn"
git config --global user.email "email@example.com"
```

### Khởi tạo Git cho project

```powershell
cd C:\Users\Admin\Tropia

# Khởi tạo git
git init

# Tạo .gitignore (QUAN TRỌNG - tránh commit file nhạy cảm)
# File .gitignore đã có trong project (Flutter tạo sẵn)
# Kiểm tra:
cat .gitignore
# Phải có: build/, .dart_tool/, .flutter-plugins, key.properties

# Commit đầu tiên
git add .
git commit -m "init: initial Flutter project with Live feature"
```

### File KHÔNG ĐƯỢC commit (đã trong .gitignore)

```
build/              ← File build (tái tạo được)
.dart_tool/         ← Cache Flutter
key.properties      ← Mật khẩu keystore (bí mật!)
*.jks               ← Keystore file (bí mật!)
.env                ← API keys (bí mật!)
```

### Backup định kỳ

```powershell
# Tạo tag cho mỗi phiên bản hoạt động
git tag -a v1.0.0 -m "Version 1.0.0 - Live feature completed"
git tag -a v1.1.0 -m "Version 1.1.0 - Added gift feature"

# Xem danh sách tags
git tag

# Quay về version cũ nếu cần
git checkout v1.0.0
```

---

## 7. Theo dõi crash production

### Tích hợp Firebase Crashlytics (khuyến nghị)

```powershell
# Thêm vào pubspec.yaml:
# firebase_core: ^2.27.0
# firebase_crashlytics: ^3.5.0

flutter pub get
```

Sửa `main.dart`:
```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  
  // Gửi tất cả uncaught errors lên Crashlytics
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  
  runApp(const TropiaApp());
}
```

### Đọc crash report

Khi có crash report từ người dùng:
1. Mở Firebase Console → Crashlytics
2. Xem stack trace
3. Tìm dòng trong code
4. Fix → release mới

### Versionning khi fix crash

```
pubspec.yaml:
version: 1.0.0+1
         │   │ └── Build number (tăng mỗi lần upload)
         │   └──── Patch (tăng khi fix bug)
         └──────── Major.Minor (tăng khi có tính năng lớn)
```

```powershell
# Khi fix crash, tăng version:
# version: 1.0.0+1  →  version: 1.0.1+2

# Build và upload lên Play Store:
flutter build appbundle --release
```

---

## Checklist bảo trì hàng tháng

```
[ ] Chạy flutter pub outdated → xem packages nào outdated
[ ] Upgrade patch versions an toàn
[ ] Chạy flutter analyze → fix mọi warning
[ ] Chạy flutter test → đảm bảo tests pass
[ ] Kiểm tra crash rate trên Firebase (nếu có)
[ ] Backup keystore file (lưu ở nhiều nơi)
[ ] Review log của tháng qua để phát hiện pattern lỗi
```

---

## Liên hệ hỗ trợ

- **Flutter docs:** https://docs.flutter.dev
- **Pub.dev** (tra cứu packages): https://pub.dev
- **Stack Overflow:** https://stackoverflow.com/questions/tagged/flutter
- **Flutter Discord:** https://discord.gg/flutter
