import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/flash_sale_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/product_card.dart';

import '../../../../core/constants/app_colors.dart';

class PromotionsPage extends StatefulWidget {
  const PromotionsPage({super.key});

  @override
  State<PromotionsPage> createState() => _PromotionsPageState();
}

class _PromotionsPageState extends State<PromotionsPage> {
  late Future<List<FlashSaleModel>> _future;
  final Color _accentColor = const Color(0xFFE53935);
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  Future<List<FlashSaleModel>> _fetch() async {
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    final sales = await dataSource.getFlashSales();

    final now = DateTime.now();

    bool isActiveNow(FlashSaleModel s) {
      if (s.active != null && s.active != 1) return false;
      final start = s.startTime;
      final end = s.endTime;
      if (start != null && now.isBefore(start)) return false;
      if (end != null && !now.isBefore(end)) return false;
      return true;
    }

    return sales.where(isActiveNow).toList();
  }

  Future<void> _refresh() async {
    if (!mounted || _isRefreshing) return;

    _isRefreshing = true;
    final newFuture = _fetch();

    try {
      await newFuture;
    } catch (_) {
      // FutureBuilder handles error UI; RefreshIndicator just needs completion.
    } finally {
      if (mounted) {
        setState(() {
          _future = newFuture;
          _isRefreshing = false;
        });
      } else {
        _isRefreshing = false;
      }
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    return DateFormat('HH:mm dd/MM').format(date);
  }

  double _hPad(double width) => width < 360 ? 12 : 16;

  Widget _header(double hPad) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 10),
      child: const Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KHUYẾN MÃI',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Chương trình đang diễn ra',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  CustomScrollView _shell({
    required double width,
    required List<Widget> slivers,
  }) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        SliverToBoxAdapter(child: _header(_hPad(width))),
        const SliverToBoxAdapter(child: SizedBox(height: 6)),
        ...slivers,
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<Widget> _centerSlivers(Widget child) {
    return [
      SliverFillRemaining(hasScrollBody: false, child: Center(child: child)),
    ];
  }

  Widget _errorContent(double hPad, Object? error) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey),
        const SizedBox(height: 12),
        const Text(
          'Không tải được khuyến mãi.',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hPad),
          child: Text(
            (error ?? '').toString(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _emptyContent() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.flash_off_rounded, size: 72, color: Color(0xFFD0D0D0)),
        SizedBox(height: 12),
        Text(
          'Chưa có chương trình nào',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Vui lòng quay lại sau nhé!',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  List<Widget> _sliversForSnapshot(
    AsyncSnapshot<List<FlashSaleModel>> snapshot,
    double width,
    double hPad,
  ) {
    if (snapshot.connectionState == ConnectionState.waiting) {
      return _centerSlivers(CircularProgressIndicator(color: _accentColor));
    }

    if (snapshot.hasError) {
      return _centerSlivers(_errorContent(hPad, snapshot.error));
    }

    final sales = snapshot.data ?? const <FlashSaleModel>[];
    if (sales.isEmpty) {
      return _centerSlivers(_emptyContent());
    }

    return [
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 12),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final isLast = index == sales.length - 1;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
              child: _buildSaleItem(sales[index], width),
            );
          }, childCount: sales.length),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final hPad = _hPad(width);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _refresh,
          color: _accentColor,
          child: FutureBuilder<List<FlashSaleModel>>(
            future: _future,
            builder: (context, snapshot) {
              return _shell(
                width: width,
                slivers: _sliversForSnapshot(snapshot, width, hPad),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSaleItem(FlashSaleModel sale, double screenWidth) {
    final banner = (sale.bannerImage ?? '').trim();
    final hasBanner = banner.isNotEmpty && banner != '0';

    final cardWidth = screenWidth >= 600
        ? 210.0
        : (screenWidth < 360 ? 152.0 : 164.0);
    final listHeight = screenWidth >= 600
        ? 390.0
        : (screenWidth < 360 ? 356.0 : 344.0);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Icon(Icons.bolt, color: _accentColor, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sale.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        height: 1.15,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sale.endTime != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            size: 14,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Kết thúc: ${_formatDate(sale.endTime)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Banner
          if (hasBanner)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 7,
                child: Image.network(
                  banner,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    color: AppColors.border,
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),

          if (hasBanner) const SizedBox(height: 12),

          // Product list
          if (sale.products.isNotEmpty)
            SizedBox(
              height: listHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                itemCount: sale.products.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) => SizedBox(
                  width: cardWidth,
                  child: ProductCard(
                    product: sale.products[index],
                    isFlashSale: true,
                  ),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Text(
                'Sản phẩm đang được cập nhật',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
