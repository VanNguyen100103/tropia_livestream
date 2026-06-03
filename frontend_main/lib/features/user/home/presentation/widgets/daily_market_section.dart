import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/datasources/home_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/home/data/models/product_model.dart';
import '../../../../../core/constants/app_colors.dart';
import 'product_card.dart';

class DailyMarketSection extends StatefulWidget {
  const DailyMarketSection({super.key});

  @override
  State<DailyMarketSection> createState() => _DailyMarketSectionState();
}

class _DailyMarketSectionState extends State<DailyMarketSection> {
  bool _isLoading = true;
  String _title = 'ĐI CHỢ MỖI NGÀY';
  String _subtitle = '';
  List<ProductModel> _products = [];

  @override
  void initState() {
    super.initState();
    _fetchDailyMarket();
  }

  Future<void> _fetchDailyMarket() async {
    try {
      final dio = DioClient().dio;
      final dataSource = HomeRemoteDataSourceImpl(client: dio);
      final result = await dataSource.getDailyMarket();
      if (!mounted) return;
      final rawProducts = result['products'];
      setState(() {
        _title = result['title']?.toString() ?? 'ĐI CHỢ MỖI NGÀY';
        _subtitle = result['subtitle']?.toString() ?? '';
        _products = (rawProducts is List)
            ? rawProducts.whereType<ProductModel>().toList()
            : [];
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return _buildSkeleton();
    if (_products.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          // Header xanh
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: const BoxDecoration(
              color: AppColors.greenFresh,
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_subtitle.isNotEmpty)
                  Text(
                    _subtitle,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),

          // Danh sách sản phẩm
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
            ),
            height: 310,
            padding: const EdgeInsets.only(top: 10),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _products.length,
              itemBuilder: (context, index) {
                return SizedBox(
                  width: 170,
                  child: ProductCard(
                    product: _products[index],
                    isFlashSale: false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkeleton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: 60,
            decoration: const BoxDecoration(
              color: AppColors.greenFresh,
              borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
            ),
          ),
          Container(
            height: 310,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(15)),
            ),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              itemBuilder: (_, _) => Container(
                width: 170,
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
