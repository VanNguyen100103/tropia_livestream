import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/core/utils/dashboard_controller.dart';
import 'package:tropia_mobile_app_android/features/user/dashboard/presentation/dashboard_page.dart';
import '../../data/datasources/profile_remote_datasource.dart';
import '../../data/models/notification_model.dart';
import '../../data/repositories/profile_repository.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  late ProfileRepository _repository;
  List<NotificationModel> _notifications = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final int _limit = 15;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final dio = DioClient().dio;
    final dataSource = ProfileRemoteDataSource(client: dio);
    _repository = ProfileRepository(remoteDataSource: dataSource);
    _loadNotifications();

    _scrollController.addListener(() {
      if (_scrollController.position.pixels ==
              _scrollController.position.maxScrollExtent &&
          !_isLoadingMore &&
          _hasMore) {
        _loadMoreNotifications();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  String _formatDate(String dateString) {
    try {
      final DateTime parsed = DateTime.parse(dateString);
      return "${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}";
    } catch (e) {
      return dateString;
    }
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _isLoading = true;
      _currentPage = 1;
      _hasMore = true;
    });

    try {
      final data =
          await _repository.getNotifications(page: _currentPage, limit: _limit);
      
      data.sort((a, b) {
        if (a.isRead != b.isRead) {
          return a.isRead ? 1 : -1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });

      if (mounted) {
        setState(() {
          _notifications = data;
          _isLoading = false;
          _hasMore = data.length == _limit;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      debugPrint("Lỗi tải thông báo: $e");
    }
  }

  Future<void> _loadMoreNotifications() async {
    if (_isLoadingMore || !_hasMore) return;

    setState(() => _isLoadingMore = true);
    _currentPage++;

    try {
      final data =
          await _repository.getNotifications(page: _currentPage, limit: _limit);
      
      data.sort((a, b) {
        if (a.isRead != b.isRead) {
          return a.isRead ? 1 : -1;
        }
        return b.createdAt.compareTo(a.createdAt);
      });

      if (mounted) {
        setState(() {
          _notifications.addAll(data);
          _isLoadingMore = false;
          _hasMore = data.length == _limit;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingMore = false);
      debugPrint("Lỗi tải thêm thông báo: $e");
    }
  }

  Future<void> _handleMarkAsRead(int id) async {
    await _repository.markAsRead(id.toString());
    if (mounted) {
      setState(() {
        final index = _notifications.indexWhere((element) => element.id == id);
        if (index != -1) {
          _notifications[index].isRead = true;
        }
      });
    }
  }

  Future<void> _markAllRead() async {
    await _repository.markAsRead('all');
    _loadNotifications();
  }

  void _onNotificationTap(NotificationModel item) {
    if (!item.isRead) {
      _handleMarkAsRead(item.id);
    }

    if (item.deepLink != null && item.deepLink!.isNotEmpty) {
      final link = item.deepLink!;
      if (link.contains("cart")) {
        DashboardController.switchTab(DashboardPage.tabCart);
        Navigator.pop(context);
      } else if (link.contains("home")) {
        DashboardController.switchTab(DashboardPage.tabHome);
        Navigator.pop(context);
      } else if (link.contains("promotion")) {
        DashboardController.switchTab(DashboardPage.tabPromotions);
        Navigator.pop(context);
      } else if (link.contains("profile")) {
        DashboardController.switchTab(DashboardPage.tabProfile);
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5), // 1. Nền xám nhạt để nổi bật Box trắng
      appBar: AppBar(
        title: const Text(
          "Thông báo",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.black,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _markAllRead,
            style: TextButton.styleFrom(
              foregroundColor: Colors.orange,
            ),
            child: const Text(
              "Đọc tất cả",
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: Colors.orange,
                  backgroundColor: Colors.white,
                  onRefresh: _loadNotifications,
                  child: ListView.separated(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16), // Padding xung quanh danh sách
                    itemCount: _notifications.length + (_isLoadingMore ? 1 : 0),
                    // 2. Khoảng cách giữa các box là 12px
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      if (index == _notifications.length) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                        );
                      }
                      return _buildNotificationBox(_notifications[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none_rounded,
              size: 60, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("Không có thông báo nào",
              style: TextStyle(color: Colors.grey[400], fontSize: 14)),
        ],
      ),
    );
  }

  // --- WIDGET BOX MỚI ---
  Widget _buildNotificationBox(NotificationModel item) {
    bool isUnread = !item.isRead;

    return GestureDetector(
      onTap: () => _onNotificationTap(item),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12), // Bo góc giống hình
          boxShadow: [
            BoxShadow(
              color: const Color.fromRGBO(0, 0, 0, 0.05), // Thay withOpacity
              offset: const Offset(0, 2),
              blurRadius: 8,
            )
          ],
          // Nếu chưa đọc thì có viền trái màu cam để dễ nhận biết (Optional)
          border: isUnread ? Border(left: BorderSide(color: Colors.orange, width: 4)) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            _buildIcon(item.type, isUnread),
            
            const SizedBox(width: 14),
            
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          item.title,
                          style: TextStyle(
                            fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                            fontSize: 15,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // Chấm cam nhỏ nếu chưa đọc (nằm góc phải)
                      if (isUnread)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Ngày tháng
                  Text(
                    _formatDate(item.createdAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[400],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.content,
                    style: TextStyle(
                      fontSize: 13,
                      color: isUnread ? Colors.black87 : Colors.grey[600],
                      height: 1.4,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(String type, bool isUnread) {
    IconData iconData = Icons.notifications_outlined;
    if (type.contains('promotion')) {
      iconData = Icons.local_offer_outlined;
    } else if (type.contains('order')) {
      iconData = Icons.local_shipping_outlined;
    } else if (type.contains('wallet')) {
      iconData = Icons.account_balance_wallet_outlined;
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isUnread ? const Color.fromRGBO(255, 152, 0, 0.1) : Colors.grey[100],
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        color: isUnread ? Colors.orange : Colors.grey[500],
        size: 20,
      ),
    );
  }
}