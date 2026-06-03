import 'dart:async'; // Để dùng Timer
import 'package:flutter/material.dart';
import '../../../../../core/network/dio_client.dart';
import '../../data/datasources/home_remote_datasource.dart';
import '../../data/models/flash_sale_model.dart';
import 'product_card.dart';

class FlashSaleSection extends StatefulWidget {
  final VoidCallback? onTap;

  const FlashSaleSection({super.key, this.onTap});

  @override
  State<FlashSaleSection> createState() => _FlashSaleSectionState();
}

class _FlashSaleSectionState extends State<FlashSaleSection> {
  // Biến chứa dữ liệu FlashSale
  Future<FlashSaleModel?>? _flashSaleFuture;

  // Biến cho đồng hồ đếm ngược
  Timer? _timer;
  Duration _timeLeft = Duration.zero;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  void _fetchData() {
    _timer?.cancel();
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);

    // Gọi API và sau đó kích hoạt Timer nếu có dữ liệu
    _flashSaleFuture = dataSource.getFlashSale().then((data) {
      if (data != null) {
        final now = DateTime.now();
        final startTime = data.startTime;
        final endTime = data.endTime;

        final isActiveNow =
            startTime != null &&
            endTime != null &&
            !now.isBefore(startTime) &&
            now.isBefore(endTime);

        final countdownTarget = isActiveNow ? endTime : startTime;

        if (countdownTarget != null) {
          _startTimer(countdownTarget);
        }
      }
      return data;
    });
  }

  // Logic đếm ngược
  // Logic đếm ngược
  void _startTimer(DateTime targetTime) {
    _timer?.cancel();

    // Set initial value immediately (avoid 1s delay).
    final initialDiff = targetTime.difference(DateTime.now());
    if (mounted) {
      setState(() {
        _timeLeft = initialDiff.isNegative ? Duration.zero : initialDiff;
      });
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      // [QUAN TRỌNG] Kiểm tra xem Widget còn tồn tại không trước khi chạy logic
      if (!mounted) {
        timer.cancel();
        return;
      }

      final now = DateTime.now();
      final difference = targetTime.difference(now);

      if (difference.isNegative) {
        timer.cancel();
        // Kiểm tra mounted trước khi setState
        if (mounted) {
          setState(() {
            _timeLeft = Duration.zero;
          });
        }

        // When countdown hits 0, refetch to switch from upcoming -> active.
        if (mounted) {
          _fetchData();
        }
      } else {
        // Kiểm tra mounted trước khi setState
        if (mounted) {
          setState(() {
            _timeLeft = difference;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // Nhớ hủy Timer khi thoát màn hình để tránh rò rỉ bộ nhớ
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FlashSaleModel?>(
      future: _flashSaleFuture,
      builder: (context, snapshot) {
        // 1. Nếu đang load hoặc lỗi hoặc không có dữ liệu -> Ẩn luôn (SizedBox.shrink)
        if (!snapshot.hasData || snapshot.data == null) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;

        return Container(
          margin: const EdgeInsets.all(10),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(15),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: widget.onTap,
              child: Ink(
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                  horizontal: 10,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF5252), Color(0xFFFF1744)],
                  ),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Column(
                  children: [
                    // HEADER
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.flash_on, color: Colors.yellow),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                data.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_timeLeft.inDays > 0) ...[
                                  _buildClockBox('${_timeLeft.inDays}d'),
                                  const SizedBox(width: 6),
                                ],
                                _buildClockBox(
                                  _formatTwoDigits(
                                    _timeLeft.inHours.remainder(24),
                                  ),
                                ),
                                const Text(
                                  ":",
                                  style: TextStyle(color: Colors.white),
                                ),
                                _buildClockBox(
                                  _formatTwoDigits(
                                    _timeLeft.inMinutes.remainder(60),
                                  ),
                                ),
                                const Text(
                                  ":",
                                  style: TextStyle(color: Colors.white),
                                ),
                                _buildClockBox(
                                  _formatTwoDigits(
                                    _timeLeft.inSeconds.remainder(60),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 15),

                    // LIST SẢN PHẨM
                    if (data.products.isNotEmpty)
                      SizedBox(
                        height: 340,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: data.products.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(width: 12),
                          itemBuilder: (context, index) {
                            return SizedBox(
                              width: 175,
                              // Truyền ProductModel vào thẻ con
                              child: ProductCard(
                                product: data.products[index],
                                isFlashSale: true,
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Widget con hiển thị số giờ/phút/giây
  Widget _buildClockBox(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
      ),
    );
  }

  // Hàm helper để thêm số 0 đằng trước (ví dụ: 5 -> 05)
  String _formatTwoDigits(int n) {
    return n.toString().padLeft(2, '0');
  }
}
