import 'package:flutter/material.dart';

class ProfileInfoBox extends StatelessWidget {
  // [MỚI] Nhận dữ liệu từ bên ngoài
  final String email;
  final String address;

  const ProfileInfoBox({super.key, required this.email, required this.address});

  @override
  Widget build(BuildContext context) {
    // Xử lý hiển thị nếu dữ liệu trống hoặc bằng "0" (do API cũ)
    String displayEmail = (email.isNotEmpty && email != "0")
        ? email
        : "Chưa cập nhật";

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100], // Nền xám nhạt
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Email",
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Text(
            displayEmail,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),

          const Divider(height: 24),

          // const Text(
          //   "Khu vực / Địa chỉ",
          //   style: TextStyle(fontSize: 12, color: Colors.grey),
          // ),
          // const SizedBox(height: 4),
          // Text(
          //   displayAddress,
          //   style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          // ),
        ],
      ),
    );
  }
}
