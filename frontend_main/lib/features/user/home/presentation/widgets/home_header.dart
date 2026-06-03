import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/features/user/profile/presentation/pages/profile_notification_page.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/pages/category_menu/category_menu_page.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/datasources/profile_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/profile_repository.dart';
import '../pages/search_page.dart';

class HomeHeader extends StatefulWidget {
  const HomeHeader({super.key});

  @override
  State<HomeHeader> createState() => _HomeHeaderState();
}

class _HomeHeaderState extends State<HomeHeader> {
  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final dio = DioClient().dio;
      final dataSource = ProfileRemoteDataSource(client: dio);
      final repository = ProfileRepository(remoteDataSource: dataSource);
      final count = await repository.getUnreadCount();
      if (mounted) {
        setState(() {
          _unreadCount = count;
        });
      }
    } catch (e) {
      debugPrint("Lỗi tải unread count: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final double paddingTop = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.fromLTRB(16, paddingTop + 10, 16, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          // 1. MENU ICON
          InkWell(
            onTap: () {
              Navigator.of(context).push(CategoryMenuPage.route());
            },
            borderRadius: BorderRadius.circular(50),
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.sort, color: Colors.black, size: 28),
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const SearchPage(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                          return FadeTransition(
                            opacity: animation,
                            child: child,
                          );
                        },
                    transitionDuration: const Duration(
                      milliseconds: 500,
                    ),
                  ),
                );
              },
              child: Hero(
                tag: 'search_bar_tag',
                child: Material(
                  type: MaterialType.transparency,
                  child: Container(
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F3F3),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const TextField(
                      enabled: false,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        hintText: "Bạn muốn mua gì?",
                        hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: Colors.black),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(horizontal: 16),
                        isDense: true,
                        fillColor: Colors.transparent,
                        filled: true,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 12),

          // 3. NOTIFICATION ICON với badge
          Stack(
            children: [
              InkWell(
                onTap: () {
                  // Chuyển sang trang Thông Báo
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationsPage(),
                    ),
                  ).then((_) {
                    // Sau khi quay lại, reload unread count
                    _loadUnreadCount();
                  });
                },
                borderRadius: BorderRadius.circular(50),
                child: const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Icon(
                    Icons.notifications_none,
                    color: Colors.black,
                    size: 28,
                  ),
                ),
              ),
              if (_unreadCount > 0)
                Positioned(
                  right: 0,
                  top: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      _unreadCount > 99 ? '99+' : _unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
