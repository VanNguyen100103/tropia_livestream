#!/bin/bash

echo "🔧 Đang cấu hình Xcode..."
echo "📝 Bạn sẽ cần nhập mật khẩu của máy Mac"

# Cấu hình Xcode
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer

# Chạy first launch của Xcode
sudo xcodebuild -runFirstLaunch

echo ""
echo "✅ Xcode đã được cấu hình!"
echo ""
echo "📱 Bây giờ bạn có thể:"
echo "   1. Mở Simulator: open -a Simulator"
echo "   2. Hoặc kết nối iPhone và chạy: flutter run"
echo ""


