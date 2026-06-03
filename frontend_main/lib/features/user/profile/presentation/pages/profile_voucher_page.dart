import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Cần import intl để format ngày
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/core/utils/dashboard_controller.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';
import 'package:tropia_mobile_app_android/features/user/cart/presentation/cart_badge_controller.dart';
import 'package:tropia_mobile_app_android/features/user/dashboard/presentation/dashboard_page.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/voucher_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/voucher_repository.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/unused_voucher_repository.dart';

class MyVouchersPage extends StatefulWidget {
  const MyVouchersPage({super.key});

  @override
  State<MyVouchersPage> createState() => _MyVouchersPageState();
}

class _MyVouchersPageState extends State<MyVouchersPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  List<VoucherModel> _vouchers = [];
  String _message = "";

  bool _isUnusedLoading = false;
  List<Map<String, dynamic>> _unusedVouchers = [];
  String _unusedMessage = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadVouchers();
    _loadUnusedVouchers();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadUnusedVouchers() async {
    setState(() {
      _isUnusedLoading = true;
      _unusedMessage = "";
    });
    final dio = DioClient().dio;
    try {
      final prefs = await SharedPreferences.getInstance();
      final authToken = prefs.getString('app_auth_token') ?? '';
      final repo = UnusedVoucherRepository(client: dio);
      final vouchers = await repo.fetchUnusedVouchers(authToken: authToken);
      setState(() {
        _unusedVouchers = vouchers;
        _isUnusedLoading = false;
        if (vouchers.isEmpty) _unusedMessage = "Không có voucher nào mới";
      });
    } catch (e) {
      setState(() {
        _isUnusedLoading = false;
        _unusedMessage = "Lỗi tải dữ liệu";
      });
    }
  }

  Future<void> _saveVoucher(String code) async {
    final dio = DioClient().dio;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final userId = prefs.getInt('user_id');
    final authToken = prefs.getString('app_auth_token') ?? '';
    if (userId == null || userId == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng đăng nhập để lưu voucher!')),
      );
      return;
    }
    final repo = UnusedVoucherRepository(client: dio);
    final result = await repo.saveVoucher(
      authToken: authToken,
      userId: userId,
      code: code,
    );
    if (!mounted) return;
    if (result['Result'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Lưu mã thành công!')),
      );
      _loadVouchers();
      _loadUnusedVouchers();
      // Chuyển sang tab "Đang dùng" sau khi lưu thành công
      _tabController.animateTo(0);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Lưu mã thất bại!')),
      );
    }
  }

  Future<void> _loadVouchers() async {
    final dio = DioClient().dio;

    try {
      // 1. Auth App
      final appAuthRepo = AppAuthRepository(
        remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
      );
      await appAuthRepo.authenticateApp();

      // 2. Get User ID
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      // final userId = 1;

      if (userId == null || userId == 0) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _message = "Vui lòng đăng nhập để xem Voucher";
          });
        }
        return;
      }

      // 3. Call API
      final repo = VoucherRepository(client: dio);
      final vouchers = await repo.getUserVouchers(userId, status: 'active');

      if (mounted) {
        setState(() {
          _vouchers = vouchers;
          _isLoading = false;
          if (vouchers.isEmpty) _message = "Bạn chưa có voucher nào";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _message = "Lỗi tải dữ liệu";
        });
      }
    }
  }

  // Helper format ngày
  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      return DateFormat('dd/MM/yyyy').format(date);
    } catch (_) {
      return isoDate;
    }
  }

  // Helper chọn màu theo loại voucher
  Color _getVoucherColor(String type) {
    switch (type) {
      case 'shipping':
        return Colors.green; // Freeship màu xanh
      case 'percent':
        return Colors.blue; // Giảm % màu xanh dương
      default:
        return Colors.orange; // Giảm tiền màu cam
    }
  }

  // Helper chọn icon theo loại voucher
  IconData _getVoucherIcon(String type) {
    switch (type) {
      case 'shipping':
        return Icons.local_shipping;
      case 'percent':
        return Icons.percent;
      default:
        return Icons.confirmation_number;
    }
  }

  /// Xử lý nút "Dùng ngay" - kiểm tra giỏ hàng rồi điều hướng
  void _onUseVoucher(VoucherModel voucher) {
    final cartCount = CartBadgeController.instance.count.value;
    if (cartCount > 0) {
      // Có sản phẩm trong giỏ → chuyển sang giỏ hàng + gắn voucher chờ
      DashboardController.pendingVoucherCode = voucher.code;
      Navigator.of(context).popUntil((route) => route.isFirst);
      DashboardController.switchTab(DashboardPage.tabCart);
    } else {
      // Giỏ trống → chuyển về trang home
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Giỏ hàng trống, hãy thêm sản phẩm trước!'),
          backgroundColor: Colors.orange,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
      DashboardController.switchTab(DashboardPage.tabHome);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text("Kho Voucher"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0.5,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Đang dùng'),
            Tab(text: 'Chưa dùng'),
          ],
          labelColor: Colors.red,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.red,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Tab 1: Đang dùng
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _vouchers.isEmpty
              ? Center(
                  child: Text(
                    _message,
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _vouchers.length,
                  itemBuilder: (context, index) {
                    final item = _vouchers[index];
                    final color = _getVoucherColor(item.discountType);
                    return Container(
                      height: 120,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 100,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _getVoucherIcon(item.discountType),
                                  color: Colors.white,
                                  size: 40,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  item.discountType == 'shipping'
                                      ? "FREESHIP"
                                      : "GIẢM",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    item.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item.description,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "HSD: ${_formatDate(item.endTime)}",
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (item.applyButtonState == 'enable')
                                        TextButton(
                                          onPressed: () => _onUseVoucher(item),
                                          style: TextButton.styleFrom(
                                            padding: EdgeInsets.zero,
                                            minimumSize: const Size(50, 30),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap,
                                          ),
                                          child: Text(
                                            "Dùng ngay",
                                            style: TextStyle(
                                              color: color,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          // Tab 2: Chưa dùng
          _isUnusedLoading
              ? const Center(child: CircularProgressIndicator())
              : _unusedVouchers.isEmpty
              ? Center(
                  child: Text(
                    _unusedMessage,
                    style: const TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _unusedVouchers.length,
                  itemBuilder: (context, index) {
                    final item = _unusedVouchers[index];
                    final color = _getVoucherColor(item['discount_type'] ?? '');
                    return Container(
                      height: 120,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withValues(alpha: 0.2),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 100,
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(8),
                                bottomLeft: Radius.circular(8),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _getVoucherIcon(item['discount_type'] ?? ''),
                                  color: Colors.white,
                                  size: 40,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  (item['discount_type'] ?? '') == 'shipping'
                                      ? "FREESHIP"
                                      : "GIẢM",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    item['title'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    item['description'] ?? '',
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 13,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const Spacer(),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        "HSD: ${_formatDate(item['end_time'] ?? '')}",
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 12,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            _saveVoucher(item['code'] ?? ''),
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(50, 30),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          "Lưu mã",
                                          style: TextStyle(
                                            color: color,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }
}
