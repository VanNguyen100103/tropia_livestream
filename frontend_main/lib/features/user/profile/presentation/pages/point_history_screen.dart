import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/datasources/profile_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/models/point_history_model.dart';
import 'package:tropia_mobile_app_android/features/user/profile/data/repositories/profile_repository.dart';

class PointHistoryScreen extends StatefulWidget {
  const PointHistoryScreen({super.key});

  @override
  State<PointHistoryScreen> createState() => _PointHistoryScreenState();
}

class _PointHistoryScreenState extends State<PointHistoryScreen> {
  final List<TransactionItem> _items = [];
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _page = 1;
  int _totalPages = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    _page = 1;
    _items.clear();
    await _fetchPage(page: _page);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _fetchPage({required int page}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');
    if (userId == null) return;

    final dio = DioClient().dio;
    final profileRepo = ProfileRepository(
      remoteDataSource: ProfileRemoteDataSource(client: dio),
    );

    final result = await profileRepo.getPointsHistory(
      userId: userId,
      page: page,
      limit: 10,
    );

    if (!mounted) return;

    if (result != null) {
      setState(() {
        _items.addAll(result.items);
        _totalPages = result.pagination.totalPages;
      });
    }
  }

  void _onScroll() {
    if (_isLoading || _isLoadingMore) return;
    if (_page >= _totalPages) return;

    final threshold = _scrollController.position.maxScrollExtent - 200;
    if (_scrollController.position.pixels >= threshold) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    setState(() => _isLoadingMore = true);
    _page += 1;
    await _fetchPage(page: _page);
    if (mounted) setState(() => _isLoadingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Lịch sử tích điểm'),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
      ),
      body: _isLoading
          ? _buildShimmerList()
          : _items.isEmpty
              ? _buildEmptyState()
              : _buildHistoryList(),
    );
  }

  Widget _buildHistoryList() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _items.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }

        final item = _items[index];
        final isAccumulate = item.type == 'accumulate';
        final color = isAccumulate ? Colors.green : Colors.deepOrange;
        final icon = isAccumulate ? Icons.savings : Icons.card_giftcard;
        final points = NumberFormat.decimalPattern('vi_VN')
            .format(item.points.abs());
        final pointsText = '${isAccumulate ? '+' : '-'}$points';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.reason?.isNotEmpty == true
                            ? item.reason!
                            : 'Giao dịch #${item.id}',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _formatDate(item.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  pointsText,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 8,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Shimmer.fromColors(
            baseColor: Colors.grey.shade300,
            highlightColor: Colors.grey.shade100,
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: double.infinity,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: 140,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  height: 16,
                  width: 60,
                  color: Colors.white,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Image.asset(
              'assets/images/logo.png',
              height: 140,
              fit: BoxFit.contain,
            ),
            const SizedBox(height: 16),
            const Text(
              'Chưa có giao dịch nào',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hãy mua sắm để tích luỹ điểm và nhận ưu đãi nhé.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String value) {
    try {
      final date = DateFormat('yyyy-MM-dd HH:mm:ss').parse(value);
      return DateFormat('dd/MM/yyyy HH:mm').format(date);
    } catch (_) {
      return value;
    }
  }
}
