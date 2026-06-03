import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/network/dio_client.dart';
import '../../data/datasources/home_remote_datasource.dart';
import '../../data/models/ready_to_cook_model.dart'; // Import Model
import 'combo_detail_sheet.dart';

class ReadyToCookSection extends StatefulWidget {
  const ReadyToCookSection({super.key});

  @override
  State<ReadyToCookSection> createState() => _ReadyToCookSectionState();
}

class _ReadyToCookSectionState extends State<ReadyToCookSection> {
  late Future<List<ReadyToCookModel>> _dataFuture;

  @override
  void initState() {
    super.initState();
    final dio = DioClient().dio;
    final dataSource = HomeRemoteDataSourceImpl(client: dio);
    _dataFuture = dataSource.getReadyToCook();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ReadyToCookModel>>(
      future: _dataFuture,
      builder: (context, snapshot) {
        // Nếu chưa có data hoặc lỗi, ẩn đi cho gọn
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return const SizedBox.shrink();
        }

        final combos = snapshot.data!;

        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "ĐI CHỢ MỖI NGÀY",
                          style: TextStyle(
                            color: AppColors.greenFresh,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          "Mua hàng tươi sống 150k, freeship 3km",
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(
              height: 260,
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                scrollDirection: Axis.horizontal,
                itemCount: combos.length,
                itemBuilder: (context, index) {
                  return _buildComboCard(context, combos[index]);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // Sửa tham số thành Model
  Widget _buildComboCard(BuildContext context, ReadyToCookModel combo) {
    return Container(
      width: 170,
      margin: const EdgeInsets.only(right: 16, bottom: 10, top: 5),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(12),
              ),
              child: _buildComboImage(combo.image),
            ),
          ),

          // NỘI DUNG
          Padding(
            padding: const EdgeInsets.all(10.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  combo.name, // Dùng model
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  combo.description, // Dùng model
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // NÚT MUA NGUYÊN LIỆU
          InkWell(
            onTap: () {
              // Truyền Model sang Sheet
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) => ComboDetailSheet(combo: combo),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: const BoxDecoration(
                color: AppColors.greenLight,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(12),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shopping_basket_outlined,
                    size: 16,
                    color: AppColors.greenFresh,
                  ),
                  SizedBox(width: 5),
                  Text(
                    "MUA NGUYÊN LIỆU",
                    style: TextStyle(
                      color: AppColors.greenFresh,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
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

  Widget _buildComboImage(String url) {
    final imageUrl = url.trim();
    if (imageUrl.isEmpty) return _imagePlaceholder();

    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return _imagePlaceholder();
      },
      errorBuilder: (_, _, _) => _imagePlaceholder(),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      width: double.infinity,
      color: Colors.grey[200],
      alignment: Alignment.center, // quan trọng: tránh icon bị dồn góc
      child: const Icon(Icons.image_outlined, color: Colors.grey, size: 28),
    );
  }
}
