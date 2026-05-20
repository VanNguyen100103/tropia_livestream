# TROPIA APP – HƯỚNG DẪN CÀI ĐẶT & DEPLOY

> **Dành cho:** Người mới học Flutter/Dart  
> **Cấp độ:** Từng bước một, không bỏ qua bước nào  
> **Cập nhật:** 2026-05-07

---

## MỤC LỤC

1. [Cài đặt môi trường](#1-cài-đặt-môi-trường)
2. [Cài đặt project](#2-cài-đặt-project)
3. [Chạy app trên máy ảo](#3-chạy-app-trên-máy-ảo)
4. [Chạy app trên điện thoại thật](#4-chạy-app-trên-điện-thoại-thật)
5. [Build APK để test](#5-build-apk-để-test)
6. [Build release APK](#6-build-release-apk)
7. [Xử lý lỗi thường gặp](#7-xử-lý-lỗi-thường-gặp)

---

## 1. Cài đặt môi trường

### Bước 1.1 – Cài Flutter SDK

```powershell
# Tải Flutter SDK từ trang chính thức
# https://docs.flutter.dev/get-started/install/windows

# Sau khi giải nén, thêm flutter\bin vào PATH
# Kiểm tra cài đặt:
flutter doctor
```

**Output mong đợi (không có dấu X đỏ):**
```
[✓] Flutter (Channel stable, 3.22.x)
[✓] Windows Version
[✓] Android toolchain - develop for Android devices
[✓] Android Studio (version 2024.x)
[✓] VS Code (version 1.9x)
[✓] Connected device
[✓] Network resources
```

### Bước 1.2 – Cài Android Studio

1. Tải từ: https://developer.android.com/studio
2. Cài đặt → mở Android Studio → More Actions → SDK Manager
3. Tích chọn: **Android SDK Platform 34** (API Level 34)
4. Tích chọn: **Android SDK Build-Tools 34**
5. Nhấn Apply → OK

### Bước 1.3 – Tạo máy ảo Android (AVD)

1. Android Studio → More Actions → **Virtual Device Manager**
2. Create device → chọn **Pixel 7** → Next
3. Chọn **API 34 (Android 14)** → Download nếu chưa có → Next
4. Finish

### Bước 1.4 – Cài VS Code Extensions

Mở VS Code → Extensions (Ctrl+Shift+X) → Cài:
- **Flutter** (by Dart Code)
- **Dart** (by Dart Code)

---

## 2. Cài đặt project

```powershell
# Di chuyển vào thư mục project
cd C:\Users\Admin\Tropia

# Tải tất cả dependencies (packages)
flutter pub get

# Kiểm tra không có lỗi
flutter analyze
```

**Nếu `flutter analyze` báo lỗi**, xem [Mục 7](#7-xử-lý-lỗi-thường-gặp).

---

## 3. Chạy app trên máy ảo

```powershell
# Bước 1: Mở máy ảo Android từ Android Studio
# (Virtual Device Manager → nhấn nút Play)

# Bước 2: Kiểm tra thiết bị đã nhận diện
flutter devices
# Output ví dụ:
# Pixel 7 (mobile) • emulator-5554 • android-x64

# Bước 3: Chạy app (debug mode)
cd C:\Users\Admin\Tropia
flutter run

# Hoặc chỉ định thiết bị cụ thể:
flutter run -d emulator-5554
```

**Trong khi app đang chạy**, nhấn phím:
- `r` – Hot Reload (cập nhật UI nhanh, giữ nguyên state)
- `R` – Hot Restart (restart toàn bộ app)
- `q` – Thoát
- `i` – In inspector overlay

---

## 4. Chạy app trên điện thoại thật

### Bước 4.1 – Bật Developer Mode trên điện thoại

1. Cài đặt → Giới thiệu điện thoại → Số hiệu bản dựng → **Nhấn 7 lần**
2. Cài đặt → Tùy chọn nhà phát triển → **Bật**
3. Tùy chọn nhà phát triển → **Gỡ lỗi USB** → Bật

### Bước 4.2 – Kết nối và chạy

```powershell
# Cắm cáp USB → chọn "File Transfer" trên điện thoại
flutter devices
# Phải thấy tên điện thoại trong danh sách

flutter run
```

---

## 5. Build APK để test (Debug APK)

```powershell
cd C:\Users\Admin\Tropia

# Build APK debug (dùng để test nội bộ)
flutter build apk --debug

# File APK ở đây:
# build\app\outputs\flutter-apk\app-debug.apk
```

**Cài APK lên điện thoại:**
```powershell
# Cắm điện thoại qua USB, sau đó:
flutter install
```

Hoặc copy file APK sang điện thoại và cài thủ công.

---

## 6. Build release APK

> ⚠️ **QUAN TRỌNG:** Release APK cần ký (signing). Không ký sẽ không lên được Google Play.

### Bước 6.1 – Tạo keystore (chỉ làm 1 lần)

```powershell
# Chạy lệnh này ở thư mục project
keytool -genkey -v -keystore tropia-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias tropia

# Nhập mật khẩu và thông tin khi được hỏi
# LƯU FILE .jks NÀY AN TOÀN - MẤT LÀ MẤT APP TRÊN GOOGLE PLAY
```

### Bước 6.2 – Cấu hình signing

Tạo file `android/key.properties`:
```properties
storePassword=<mật_khẩu_keystore>
keyPassword=<mật_khẩu_key>
keyAlias=tropia
storeFile=../tropia-release-key.jks
```

### Bước 6.3 – Sửa `android/app/build.gradle`

Thêm vào đầu file (sau dòng `apply plugin:`):
```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

Trong `android { ... }`, thêm:
```gradle
signingConfigs {
    release {
        keyAlias keystoreProperties['keyAlias']
        keyPassword keystoreProperties['keyPassword']
        storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
        storePassword keystoreProperties['storePassword']
    }
}
buildTypes {
    release {
        signingConfig signingConfigs.release
    }
}
```

### Bước 6.4 – Build

```powershell
# Build APK release
flutter build apk --release

# File ở: build\app\outputs\flutter-apk\app-release.apk

# Build App Bundle (tốt hơn cho Google Play)
flutter build appbundle --release
# File ở: build\app\outputs\bundle\release\app-release.aab
```

---

## 7. Xử lý lỗi thường gặp

### Lỗi: `flutter pub get` thất bại

```powershell
# Xóa cache và thử lại
flutter clean
flutter pub get
```

### Lỗi: Version conflict (dependency conflict)

```
Because X requires Y ^1.0.0 and Z requires Y ^2.0.0...
```

```powershell
# Kiểm tra dependency tree
flutter pub deps

# Nâng cấp tất cả packages lên version mới nhất tương thích
flutter pub upgrade
```

### Lỗi: Gradle build failed

```powershell
cd android
.\gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

### Lỗi: `minSdkVersion` too low

Mở `android/app/build.gradle`, tìm và sửa:
```gradle
minSdkVersion 21  # Đổi thành 21 hoặc cao hơn
```

### Lỗi: Null safety

```
Null check operator used on a null value
```

Đây là lỗi runtime. Xem log để biết dòng nào, kiểm tra biến có thể null.

### Lỗi: `CERTIFICATE_VERIFY_FAILED` khi pub get

```powershell
# Tắt proxy/VPN, thử lại
# Hoặc:
set PUB_HOSTED_URL=https://pub.dartlang.org
flutter pub get
```

---

## Kiểm tra cuối cùng trước khi giao

```powershell
# 1. Không có warning/error
flutter analyze

# 2. Test chạy qua
flutter test

# 3. Build thành công
flutter build apk --debug

# 4. App khởi động không crash
flutter run --release
```
