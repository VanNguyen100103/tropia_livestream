import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/ready_to_cook_model.dart';
import 'package:tropia_mobile_app_android/features/user/home/presentation/widgets/combo_detail_sheet.dart';

import '../../../../core/constants/app_colors.dart';

class UfreshPage extends StatefulWidget {
  const UfreshPage({super.key});

  @override
  State<UfreshPage> createState() => _UfreshPageState();
}

class _UfreshPageState extends State<UfreshPage> {
  late Future<List<ReadyToCookModel>> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _fetch();
  }

  Future<List<ReadyToCookModel>> _fetch() {
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    return dataSource.getReadyToCook();
  }

  Future<void> _onRefresh() async {
    if (!mounted) return;
    final newFuture = _fetch();
    setState(() => _dataFuture = newFuture);
    try {
      await newFuture;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _onRefresh,
          child: FutureBuilder<List<ReadyToCookModel>>(
            future: _dataFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final combos = snapshot.data ?? const <ReadyToCookModel>[];
              if (combos.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 24),
                    _UfreshHeader(),
                    SizedBox(height: 24),
                    Center(
                      child: Text(
                        'Hiện chưa có combo Ufresh.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                );
              }

              return CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  const SliverToBoxAdapter(child: SizedBox(height: 10)),
                  const SliverToBoxAdapter(child: _UfreshHeader()),
                  const SliverToBoxAdapter(child: SizedBox(height: 6)),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    sliver: SliverList.separated(
                      itemBuilder: (context, index) {
                        return _ComboListItem(combo: combos[index]);
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemCount: combos.length,
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _UfreshHeader extends StatelessWidget {
  const _UfreshHeader();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'UFRESH',
                  style: TextStyle(
                    color: AppColors.greenFresh,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Combo nguyên liệu tươi – chọn là nấu ngay',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComboListItem extends StatelessWidget {
  final ReadyToCookModel combo;

  const _ComboListItem({required this.combo});

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(locale: 'vi_VN', symbol: '₫');

    void openDetail() {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => ComboDetailSheet(combo: combo),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final double imageSize = width < 360 ? 88 : (width < 420 ? 100 : 112);
        final titleFontSize = width < 360 ? 13.0 : 14.0;
        final actionLabel = width < 360 ? 'XEM' : 'XEM COMBO';

        return InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: openDetail,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: imageSize,
                    height: imageSize,
                    child: _ComboImage(url: combo.image),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        combo.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: titleFontSize,
                          color: AppColors.textPrimary,
                          height: 1.15,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        combo.description,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _InfoPill(
                            icon: Icons.payments_outlined,
                            text:
                                'Ước tính: ${currency.format(combo.totalPriceEstimate)}',
                            textColor: AppColors.accent,
                            iconColor: AppColors.accent,
                            background: AppColors.accentLight,
                          ),
                          _InfoPill(
                            icon: Icons.shopping_basket_outlined,
                            text: '${combo.ingredients.length} nguyên liệu',
                            textColor: AppColors.greenFresh,
                            iconColor: AppColors.greenFresh,
                            background: AppColors.greenLight,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: InkWell(
                          onTap: openDetail,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.greenLight,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.greenFresh.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.shopping_basket_outlined,
                                  size: 16,
                                  color: AppColors.greenFresh,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  actionLabel,
                                  style: const TextStyle(
                                    color: AppColors.greenFresh,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color textColor;
  final Color iconColor;
  final Color background;

  const _InfoPill({
    required this.icon,
    required this.text,
    required this.textColor,
    required this.iconColor,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComboImage extends StatelessWidget {
  final String url;

  const _ComboImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final imageUrl = url.trim();
    if (imageUrl.isEmpty) return _placeholder();

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _placeholder();
      },
      errorBuilder: (_, _, _) => _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      width: double.infinity,
      color: Colors.grey[200],
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: Colors.grey, size: 28),
    );
  }
}
