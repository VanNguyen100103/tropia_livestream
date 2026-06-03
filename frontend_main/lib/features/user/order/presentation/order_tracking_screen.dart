/// Order Tracking Screen
/// Minimalist Style: White/Black dominant, Orange accent
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/datasources/order_tracking_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/models/order_tracking_model.dart';
import 'package:tropia_mobile_app_android/features/user/order/data/repositories/order_tracking_repository.dart';

// Định nghĩa màu cục bộ cho file này để đảm bảo đúng style yêu cầu
class MinimalColors {
  static const Color accentOrange = Color(0xFFFF6B00); // Cam đậm
  static const Color bgWhite = Colors.white;
  static const Color textBlack = Color(0xFF1F1F1F);
  static const Color textGrey = Color(0xFF9E9E9E);
  static const Color borderGrey = Color(0xFFEEEEEE);
}

class OrderTrackingScreen extends StatefulWidget {
  final String orderId;
  final String? orderCode;

  const OrderTrackingScreen({
    super.key,
    required this.orderId,
    this.orderCode,
  });

  @override
  State<OrderTrackingScreen> createState() => _OrderTrackingScreenState();
}

class _OrderTrackingScreenState extends State<OrderTrackingScreen> {
  late OrderTrackingRepository _repository;
  OrderTrackingModel? _trackingData;
  bool _isLoading = true;
  String? _error;
  Timer? _pollingTimer;
  bool _wasInTransit = false;

  @override
  void initState() {
    super.initState();
    _initRepository();
    _loadTracking();
    _startPolling();
  }

  void _initRepository() {
    final dio = DioClient().dio;
    _repository = OrderTrackingRepository(
      remoteDataSource: OrderTrackingRemoteDataSource(dio: dio),
    );
  }

  Future<void> _loadTracking() async {
    try {
      final data = await _repository.getOrderTracking(widget.orderId);

      if (mounted) {
        setState(() {
          _trackingData = data;
          _error = data == null ? 'Không thể tải dữ liệu' : null;
          _isLoading = false;
        });

        if (data != null && data.isInTransit && !_wasInTransit) {
          _wasInTransit = true;
          if (mounted) setState(() {});
        } else if (data != null && !data.isInTransit) {
          _wasInTransit = false;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Lỗi: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) _loadTracking();
    });
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // Nền trắng toàn màn hình
      appBar: AppBar(
        title: const Text(
          'Theo dõi đơn hàng',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: MinimalColors.textBlack,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: MinimalColors.textBlack),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MinimalColors.borderGrey, height: 1),
        ),
        actions: [
          
        ],
      ),
      body: _isLoading
          ? const _LoadingState()
          : _error != null
              ? _ErrorState(error: _error!, onRetry: _loadTracking)
              : _trackingData == null
                  ? const _ErrorState(error: 'Không tìm thấy đơn hàng')
                  : SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildOrderHeader(),
                          const Divider(height: 1, color: MinimalColors.borderGrey),
                          
                          const SizedBox(height: 24),
                          
                          // Map Section
                          _buildMapSection(),
                          
                          const SizedBox(height: 24),
                          
                          // Shipper
                          _buildShipperCard(),
                          
                          const SizedBox(height: 24),
                          
                          // Timeline Header
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Text(
                              'Hành trình đơn hàng',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: MinimalColors.textBlack,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Timeline Content
                          _buildTimeline(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildOrderHeader() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MÃ ĐƠN HÀNG',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: MinimalColors.textGrey,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.orderCode ?? _trackingData?.orderId ?? '',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: MinimalColors.textBlack,
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: MinimalColors.accentOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20), // Bo tròn dạng viên thuốc
            ),
            child: Text(
              _getStatusText(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: MinimalColors.accentOrange,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMapSection() {
    if (_trackingData == null) return const SizedBox.shrink();
    final displayLoc = _getDisplayLocation();

    // Luôn hiển thị bản đồ trong thẻ (card)
    return _buildMapCard(displayLoc);
  }

  Widget _buildMapCard(Location? displayLoc) {
    final LatLng target = displayLoc != null
        ? LatLng(displayLoc.lat, displayLoc.lng)
        : const LatLng(21.028511, 105.854444);

    final markers = displayLoc != null
        ? <Marker>{
            Marker(
              markerId: const MarkerId('shipper'),
              position: target,
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueOrange,
              ),
            ),
          }
        : <Marker>{};

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MinimalColors.borderGrey),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Bản đồ theo dõi',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: MinimalColors.textBlack,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: displayLoc != null
                        ? MinimalColors.accentOrange.withValues(alpha: 0.12)
                        : Colors.grey.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    displayLoc != null ? 'Đang theo dõi' : 'Chưa có vị trí',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: displayLoc != null
                          ? MinimalColors.accentOrange
                          : MinimalColors.textGrey,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: Stack(
                children: [
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: target,
                      zoom: 15,
                    ),
                    markers: markers,
                    myLocationEnabled: false,
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                    mapToolbarEnabled: false,
                  ),
                  if (displayLoc == null)
                    Positioned.fill(
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.75),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.location_off, size: 28, color: MinimalColors.textGrey),
                            SizedBox(height: 8),
                            Text(
                              'Chưa có vị trí tài xế',
                              style: TextStyle(
                                fontSize: 13,
                                color: MinimalColors.textGrey,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (displayLoc != null)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: MinimalColors.accentOrange,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'Live Tracking',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: MinimalColors.textBlack,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Location? _getDisplayLocation() {
    if (_trackingData == null) return null;
    final shipperLoc = _trackingData!.shipper?.currentLocation;
    if (shipperLoc != null && shipperLoc.lat != 0.0 && shipperLoc.lng != 0.0) {
      return shipperLoc;
    }
    for (final item in _trackingData!.trackingHistory) {
      if (item.location != null && item.location!.lat != 0.0 && item.location!.lng != 0.0) {
        return item.location;
      }
    }
    return null;
  }

  Widget _buildShipperCard() {
    if (_trackingData?.shipper == null) return const SizedBox.shrink();

    final shipper = _trackingData!.shipper!;
    final isWaiting = shipper.isWaiting;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MinimalColors.borderGrey),
        // Không dùng shadow để giữ vẻ phẳng
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey[100],
            ),
            child: Icon(
              Icons.person,
              color: isWaiting ? Colors.grey : MinimalColors.textBlack,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tài xế',
                  style: TextStyle(fontSize: 10, color: MinimalColors.textGrey, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  isWaiting ? 'Chờ cập nhật...' : shipper.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isWaiting ? Colors.grey : MinimalColors.textBlack,
                  ),
                ),
                if (!isWaiting)
                  Text(
                    shipper.displayPhone,
                    style: TextStyle(fontSize: 12, color: MinimalColors.textGrey),
                  ),
              ],
            ),
          ),

          // Call Button (Minimalist: Đen hoặc Cam)
          if (shipper.hasPhone && !isWaiting)
            IconButton(
              onPressed: () => _callShipper(shipper.phone),
              style: IconButton.styleFrom(
                backgroundColor: MinimalColors.textBlack, // Nền đen
                foregroundColor: Colors.white, // Icon trắng
                padding: const EdgeInsets.all(10),
              ),
              icon: const Icon(Icons.phone, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _buildTimeline() {
    if (_trackingData?.trackingHistory.isEmpty ?? true) {
      return const SizedBox.shrink();
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: _trackingData!.trackingHistory.length,
      itemBuilder: (context, index) {
        final item = _trackingData!.trackingHistory[index];
        final isLast = index == _trackingData!.trackingHistory.length - 1;
        // Logic xác định step hiện tại
        final isCurrentStep = !item.isCompleted &&
            (index == 0 ||
                _trackingData!.trackingHistory
                        .where((i) => !i.isCompleted)
                        .first ==
                    item);

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline line & dot
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: item.isCompleted || isCurrentStep
                            ? MinimalColors.accentOrange
                            : Colors.white,
                        border: Border.all(
                          color: item.isCompleted || isCurrentStep
                              ? MinimalColors.accentOrange
                              : Colors.grey[300]!,
                          width: 2,
                        ),
                      ),
                      // Chấm nhỏ màu trắng ở giữa nếu là current
                      child: isCurrentStep
                          ? Center(
                              child: Container(
                                width: 4,
                                height: 4,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : null,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: item.isCompleted
                              ? MinimalColors.accentOrange.withValues(alpha: 0.5)
                              : Colors.grey[200],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              
              // Text Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24), // Spacing between items
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: item.isCompleted || isCurrentStep
                              ? MinimalColors.textBlack
                              : MinimalColors.textGrey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            item.formattedTime,
                            style: TextStyle(
                              fontSize: 12,
                              color: MinimalColors.textGrey,
                            ),
                          ),
                          if (item.isEstimated) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Dự kiến',
                                style: TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ),
                          ]
                        ],
                      ),
                      if ((item.description ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            item.description!,
                            style: TextStyle(
                              fontSize: 13,
                              color: MinimalColors.textBlack.withValues(alpha: 0.7),
                              height: 1.4,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _callShipper(String phone) async {
    try {
      final uri = Uri(scheme: 'tel', path: phone);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return;
      }
      await Clipboard.setData(ClipboardData(text: phone));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã sao chép số: $phone'),
            backgroundColor: MinimalColors.textBlack,
          ),
        );
      }
    } catch (e) {
      // ignore
    }
  }

  String _getStatusText() {
    if (_trackingData == null) return '';
    switch (_trackingData!.status) {
      case 'delivered': return 'Đã giao';
      case 'in_transit': return 'Đang giao';
      case 'in_warehouse': return 'Trong kho';
      case 'waiting_pickup': return 'Chờ lấy hàng';
      case 'order_placed': return 'Đơn mới';
      default: return 'Đang xử lý';
    }
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: MinimalColors.accentOrange,
        strokeWidth: 2,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback? onRetry;
  const _ErrorState({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(error, style: const TextStyle(color: Colors.grey)),
          if (onRetry != null)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: TextButton(
                onPressed: onRetry,
                style: TextButton.styleFrom(foregroundColor: MinimalColors.accentOrange),
                child: const Text('Thử lại'),
              ),
            ),
        ],
      ),
    );
  }
}