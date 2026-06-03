var admin = require("firebase-admin");

// 1. Load File Service Account
var serviceAccount = require("./firebase-service-account.json"); 

// Kiểm tra để tránh lỗi initialize nhiều lần
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert(serviceAccount)
  });
}

// 2. TOKEN MÁY CỦA BẠN (Lấy từ Log mới nhất)
var deviceToken = "cZfaN24QQcWqQ108VpZLhr:APA91bFkO3qPv9VRtmpoglgP0lkzqgJBslV5lRuVBkiIT9EyH-aVmVUmmkfFuAirT2VwSxfW3wXDRhkPGpm1LXQWEkzj3Jh2ormtORCAX455AbpUV0zwRBU";

// 3. NỘI DUNG TEST DEEP LINK (CHUYỂN TAB)
var message = {
  notification: {
    title: "🛒 Ơ KÌA USER 40 ƠI!",
    body: "Bạn có đơn hàng chưa thanh toán trong giỏ kìa. Bấm vào đây để xem ngay kẻo hết mã giảm giá nhé! 👇"
  },
  
  // --- PHẦN QUAN TRỌNG NHẤT ---
  // Đây là dữ liệu ngầm để App biết phải làm gì khi bấm vào
  data: {
    "deep_link": "cart",        // Lệnh: Chuyển sang tab Giỏ hàng
    "notification_id": "9999"   // ID giả định để test API mark-read
  },
  // -----------------------------

  android: {
    notification: {
      color: "#DA291C",      // Màu đỏ thương hiệu
      priority: "high",      // Hiện popup ngay lập tức
      defaultSound: true,    // Có tiếng ting ting
      defaultVibrateTimings: true
    }
  },
  token: deviceToken
};

console.log("🚀 Đang gửi thông báo test Deep Link...");

// 4. GỬI
admin.messaging().send(message)
  .then((response) => {
    console.log("✅ Đã gửi thành công!", response);
    console.log("👉 Bây giờ hãy bấm vào thông báo trên điện thoại xem nó có nhảy vào GIỎ HÀNG không nhé!");
  })
  .catch((error) => {
    console.log("❌ Lỗi gửi:", error);
  });