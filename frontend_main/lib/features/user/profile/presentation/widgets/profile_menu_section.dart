import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/routes/slide_right_route.dart';

class ProfileMenuSection extends StatelessWidget {
  final String? title;
  final List<Map<String, dynamic>> items;
  // [MỚI] Callback để báo widget cha load lại dữ liệu
  final VoidCallback? onProfileUpdate; 

  const ProfileMenuSection({
    super.key,
    this.title,
    required this.items,
    this.onProfileUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8, top: 20),
            child: Text(
              title!,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: items.map((item) {
              bool isLast = items.last == item;

              return Column(
                children: [
                  ListTile(
                    leading: Icon(
                      item['icon'],
                      color: Colors.grey[700],
                    ),
                    title: Text(
                      item['title'],
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item['badge'] != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              item['badge'],
                              style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        if (item['trailing'] != null && item['trailing'] != "")
                          Text(
                            item['trailing'],
                            style: const TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                      ],
                    ),
                    
                    // --- [MỚI] LOGIC XỬ LÝ NAVIGATE VÀ RELOAD ---
                    onTap: () async {
                      if (item['destination'] != null) {
                        final useSlideRoute = item['useSlideRoute'] == true;
                        final route = item['route'];

                        final result = await Navigator.push(
                          context,
                          route is Route
                              ? route
                              : (useSlideRoute
                                  ? SlideRightRoute(page: item['destination'])
                                  : MaterialPageRoute(
                                      builder: (context) => item['destination'],
                                    )),
                        );

                        // Nếu result == true (nghĩa là trang con báo đã update thành công)
                        if (result == true) {
                          // Gọi callback để báo widget cha reload
                          onProfileUpdate?.call();
                        }
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Tính năng đang phát triển")),
                        );
                      }
                    },
                  ),
                  if (!isLast)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}