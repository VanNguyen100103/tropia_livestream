import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Để format tiền
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';

// --- IMPORTS KHUYẾN MÃI ---
import 'package:tropia_mobile_app_android/features/admin/promotions/data/models/promotion_model.dart';
import 'package:tropia_mobile_app_android/features/admin/promotions/data/repositories/promotion_repository.dart';
import '../widgets/promotion_card.dart';
import '../widgets/promotion_form_dialog.dart';

// --- IMPORTS BANNER ---
import 'package:tropia_mobile_app_android/features/admin/promotions/data/models/banner_model.dart';
import 'package:tropia_mobile_app_android/features/admin/promotions/data/repositories/banner_repository.dart';
import '../widgets/banner_form_dialog.dart'; // Đảm bảo bạn đã tạo file này ở bước trước

// --- AUTH ---
import 'package:tropia_mobile_app_android/features/user/auth/data/datasources/app_auth_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/auth/data/repositories/app_auth_repository.dart';

class PromotionListScreen extends StatefulWidget {
  const PromotionListScreen({super.key});

  @override
  State<PromotionListScreen> createState() => _PromotionListScreenState();
}

class _PromotionListScreenState extends State<PromotionListScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;

  // Data Khuyến mãi
  List<PromotionModel> _promotions = [];

  // Data Banner
  List<BannerModel> _banners = [];

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final dio = DioClient().dio;
    final authRepo = AppAuthRepository(
      remoteDataSource: AppAuthRemoteDataSourceImpl(client: dio),
    );
    await authRepo.authenticateApp();

    // Load cả 2 dữ liệu song song
    await Future.wait([_fetchPromotions(), _fetchBanners()]);

    if (mounted) setState(() => _isLoading = false);
  }

  // --- LOGIC KHUYẾN MÃI ---
  Future<void> _fetchPromotions() async {
    final dio = DioClient().dio;
    final repo = PromotionRepository(client: dio);
    final data = await repo.getPromotions();
    if (mounted) setState(() => _promotions = data);
  }

  Future<void> _toggleStatus(PromotionModel promo) async {
    final newStatus = promo.status == 'active' ? 'paused' : 'active';
    final dio = DioClient().dio;
    final repo = PromotionRepository(client: dio);
    final success = await repo.updateStatus(promo.id, newStatus);

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Đã ${newStatus == 'active' ? 'kích hoạt' : 'tạm dừng'}",
          ),
          duration: const Duration(seconds: 1),
        ),
      );
      _fetchPromotions();
    }
  }

  void _openPromoDialog(BuildContext context, {PromotionModel? promo}) async {
    final result = await showDialog(
      context: context,
      builder: (context) => PromotionFormDialog(promotion: promo),
    );
    if (result == true) _fetchPromotions();
  }

  // --- LOGIC BANNER ---
  Future<void> _fetchBanners() async {
    final dio = DioClient().dio;
    final repo = BannerRepository(client: dio);
    final data = await repo.getBanners();
    if (mounted) setState(() => _banners = data);
  }

  void _openBannerDialog(BuildContext context) async {
    final result = await showDialog(
      context: context,
      builder: (context) => const BannerFormDialog(),
    );
    if (result == true) _fetchBanners();
  }

  Future<void> _deleteBanner(String id) async {
    // Show confirm dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Xác nhận xóa"),
        content: const Text("Bạn có chắc chắn muốn xóa banner này không?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Hủy"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Xóa", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      // Gọi API xóa (Nếu Repo chưa có hàm delete thì bạn cần thêm vào repo như bài trước tôi hướng dẫn)
      // Ở đây tạm thời giả lập xóa thành công để UI cập nhật
      // final success = await repo.deleteBanner(id); // Uncomment khi Repo có hàm này

      // Tạm thời reload lại list
      _fetchBanners();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Đã gửi yêu cầu xóa")));
    }
  }

  String _formatCurrency(double value) {
    return "${NumberFormat("#,###", "vi_VN").format(value)}đ";
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2, // 2 Tab
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        // --- BƯỚC 1: Bỏ AppBar ---
        // appBar: ... (đã xóa),

        // --- BƯỚC 2 & 3: Dùng SafeArea và Column cho body ---
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  // Sử dụng Column để xếp TabBar lên trên
                  children: [
                    // --- BƯỚC 4: Đặt TabBar ở đầu Column ---
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          bottom: BorderSide(color: Colors.grey, width: 0.5),
                        ), // Thêm đường kẻ mờ bên dưới
                      ),
                      child: const TabBar(
                        labelColor: Color(0xFFF06F23),
                        unselectedLabelColor: Colors.grey,
                        indicatorColor: Color(0xFFF06F23),
                        indicatorWeight: 3, // Làm vạch chỉ thị dày hơn một chút
                        labelStyle: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        unselectedLabelStyle: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                        tabs: [
                          Tab(text: "Khuyến mãi"),
                          Tab(text: "Banner"),
                        ],
                      ),
                    ),

                    Expanded(
                      child: TabBarView(
                        children: [_buildPromotionTab(), _buildBannerTab()],
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  // --- TAB 1: KHUYẾN MÃI ---
  Widget _buildPromotionTab() {
    return RefreshIndicator(
      onRefresh: _fetchPromotions,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Nút Tạo Khuyến Mãi
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openPromoDialog(context),
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                "Tạo khuyến mãi mới",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF06F23),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // List
          if (_promotions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 50),
              child: Center(child: Text("Chưa có khuyến mãi nào")),
            )
          else
            ..._promotions.map((promo) {
              final Map<String, dynamic> promoMap = {
                'id': promo.id,
                'title': promo.title,
                'description': promo.description,
                'discountValue': _formatCurrency(promo.discountValue),
                'minOrder': _formatCurrency(promo.minOrderValue),
                'startDate': promo.startDate,
                'endDate': promo.endDate,
                'status': promo.status,
              };
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PromotionCard(
                  data: promoMap,
                  onEdit: () => _openPromoDialog(context, promo: promo),
                  onDelete: () {}, // Chưa implement
                  onToggle: () => _toggleStatus(promo),
                ),
              );
            }),
          const SizedBox(height: 80), // Padding bottom
        ],
      ),
    );
  }

  // --- TAB 2: BANNER ---
  Widget _buildBannerTab() {
    return RefreshIndicator(
      onRefresh: _fetchBanners,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          // Nút Tạo Banner
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _openBannerDialog(context),
              icon: const Icon(Icons.image, color: Colors.white),
              label: const Text(
                "Thêm Banner mới",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(
                  0xFF2196F3,
                ), // Màu xanh để phân biệt
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // List Banner
          if (_banners.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 50),
              child: Center(child: Text("Chưa có banner nào")),
            )
          else
            ..._banners.map((banner) {
              return Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ảnh Banner
                    Stack(
                      children: [
                        SizedBox(
                          height: 150,
                          width: double.infinity,
                          child: Image.network(
                            banner.imageUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                                  color: Colors.grey[300],
                                  child: const Icon(
                                    Icons.broken_image,
                                    size: 50,
                                    color: Colors.grey,
                                  ),
                                ),
                          ),
                        ),
                        // Nút xóa (Icon trash) ở góc ảnh
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            backgroundColor: Colors.white.withValues(alpha: 0.8),
                            radius: 16,
                            child: IconButton(
                              icon: const Icon(
                                Icons.delete,
                                size: 18,
                                color: Colors.red,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: () => _deleteBanner(banner.id ?? ''),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Thông tin Banner
                    Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            banner.title,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: Colors.blue.shade200,
                                  ),
                                ),
                                child: Text(
                                  banner.actionType,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue[800],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  banner.actionValue,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
