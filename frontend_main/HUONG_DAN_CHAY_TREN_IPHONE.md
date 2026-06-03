# Hướng Dẫn Chạy Dự Án Flutter Trên iPhone

## Yêu Cầu Hệ Thống

1. **macOS** (bắt buộc - chỉ macOS mới build được iOS app)
2. **Xcode** (từ App Store)
3. **Flutter SDK**
4. **CocoaPods** (quản lý dependencies iOS)

## Bước 1: Cài Đặt Xcode

1. Mở **App Store** trên Mac
2. Tìm kiếm "Xcode"
3. Cài đặt Xcode (khoảng 10-15GB)
4. Sau khi cài xong, mở Xcode một lần để chấp nhận license agreement
5. Cài đặt Command Line Tools:
   ```bash
   sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
   sudo xcodebuild -license accept
   ```

## Bước 2: Cài Đặt Flutter

### Cách 1: Sử dụng Homebrew (Khuyến nghị)
```bash
# Cài Homebrew nếu chưa có
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Cài Flutter
brew install --cask flutter
```

### Cách 2: Tải trực tiếp
1. Truy cập: https://docs.flutter.dev/get-started/install/macos
2. Tải Flutter SDK
3. Giải nén vào thư mục (ví dụ: `~/development/flutter`)
4. Thêm vào PATH:
   ```bash
   # Thêm vào ~/.zshrc
   export PATH="$PATH:$HOME/development/flutter/bin"
   
   # Hoặc nếu cài bằng Homebrew, PATH đã được tự động thêm
   ```

## Bước 3: Cài Đặt CocoaPods

```bash
sudo gem install cocoapods
```

## Bước 4: Kiểm Tra Cài Đặt

```bash
# Kiểm tra Flutter
flutter doctor

# Kiểm tra các thiết bị iOS
flutter devices
```

**Lưu ý:** Nếu `flutter doctor` báo lỗi, hãy làm theo hướng dẫn để sửa.

## Bước 5: Cấu Hình Dự Án

### 5.1. Cài đặt dependencies
```bash
cd "/Users/tanmanucian/Documents/Ths app/tropia app/tropia_app"
flutter pub get
```

### 5.2. Cài đặt CocoaPods dependencies
```bash
cd ios
pod install
cd ..
```

### 5.3. Cấu hình Signing trong Xcode (Quan trọng!)

1. Mở file `ios/Runner.xcworkspace` trong Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```
   
2. Trong Xcode:
   - Chọn **Runner** ở sidebar bên trái
   - Chọn tab **Signing & Capabilities**
   - Chọn **Team** của bạn (cần Apple Developer Account)
   - Nếu chưa có Team, có thể chọn "Personal Team" (miễn phí)
   - Xcode sẽ tự động tạo Bundle Identifier

## Bước 6: Chạy Trên iPhone

### Cách 1: Chạy trên iPhone Simulator
```bash
# Xem danh sách simulator
flutter emulators

# Khởi động simulator
open -a Simulator

# Hoặc chạy trực tiếp
flutter run
```

### Cách 2: Chạy trên iPhone thật

1. **Kết nối iPhone với Mac** bằng cáp USB
2. **Mở khóa iPhone** và chấp nhận "Trust This Computer"
3. **Kiểm tra thiết bị:**
   ```bash
   flutter devices
   ```
   Bạn sẽ thấy iPhone của mình trong danh sách

4. **Chạy app:**
   ```bash
   flutter run
   ```
   
   Hoặc chỉ định thiết bị cụ thể:
   ```bash
   flutter run -d <device-id>
   ```

5. **Lần đầu chạy trên iPhone thật:**
   - Trên iPhone, vào **Settings > General > VPN & Device Management**
   - Tìm Developer App và **Trust** nó
   - Sau đó mở app từ màn hình chính

## Bước 7: Debug và Hot Reload

- **Hot Reload:** Nhấn `r` trong terminal
- **Hot Restart:** Nhấn `R` trong terminal
- **Quit:** Nhấn `q` trong terminal

## Xử Lý Lỗi Thường Gặp

### Lỗi: "No devices found"
- Đảm bảo iPhone đã được unlock
- Kiểm tra cáp USB
- Chạy `flutter doctor` để kiểm tra cấu hình

### Lỗi: "Signing for Runner requires a development team"
- Mở Xcode và cấu hình Signing như ở Bước 5.3

### Lỗi: "CocoaPods not installed"
- Chạy: `sudo gem install cocoapods`
- Sau đó: `cd ios && pod install`

### Lỗi: "Flutter command not found"
- Đảm bảo Flutter đã được thêm vào PATH
- Chạy: `source ~/.zshrc` hoặc mở terminal mới

## Lưu Ý Quan Trọng

1. **Apple Developer Account:** 
   - Miễn phí: Có thể test trên thiết bị của chính mình (Personal Team)
   - Trả phí ($99/năm): Cần để publish lên App Store

2. **Bundle Identifier:** 
   - Phải là duy nhất (ví dụ: `com.yourcompany.tropia`)
   - Có thể thay đổi trong Xcode

3. **iOS Deployment Target:**
   - Kiểm tra trong `ios/Podfile` và `ios/Runner.xcodeproj`
   - Khuyến nghị: iOS 12.0 trở lên

## Tài Liệu Tham Khảo

- Flutter iOS Setup: https://docs.flutter.dev/get-started/install/macos
- Xcode Setup: https://developer.apple.com/xcode/
- CocoaPods: https://cocoapods.org/


