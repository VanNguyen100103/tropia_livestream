import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';

import 'package:tropia_mobile_app_android/core/network/dio_client.dart';
import 'package:tropia_mobile_app_android/features/user/rewards/data/datasources/rewards_remote_datasource.dart';
import 'package:tropia_mobile_app_android/features/user/rewards/data/models/rewards_models.dart';
import 'package:tropia_mobile_app_android/features/user/rewards/data/repositories/rewards_repository.dart';
import 'widgets/reward_item_card.dart';

class RewardsListScreen extends StatefulWidget {
  const RewardsListScreen({super.key});

  @override
  State<RewardsListScreen> createState() => _RewardsListScreenState();
}

class _RewardsListScreenState extends State<RewardsListScreen> {
  bool _isLoading = true;
  int _userPoints = 0;
  List<RewardItemModel> _rewards = [];
  final Map<int, bool> _redeemLoading = {};

  @override
  void initState() {
    super.initState();
    _loadRewards();
  }

  Future<void> _loadRewards({bool showLoading = true}) async {
    if (showLoading) setState(() => _isLoading = true);

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null || userId == 0) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final dio = DioClient().dio;
    final repo = RewardsRepository(
      remoteDataSource: RewardsRemoteDataSource(client: dio),
    );

    final result = await repo.getRewardsList(userId: userId);

    if (!mounted) return;

    setState(() {
      _userPoints = result?.userPoints ?? 0;
      _rewards = result?.rewards ?? [];
      _isLoading = false;
    });
  }

  Future<void> _redeemReward(RewardItemModel reward) async {
    final canRedeem = reward.canRedeem && _userPoints >= reward.pointCost;
    if (!canRedeem) {
      _showSnack('Điểm chưa đủ hoặc voucher không khả dụng');
      return;
    }

    setState(() => _redeemLoading[reward.id] = true);

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('user_id');

    if (userId == null || userId == 0) {
      if (mounted) setState(() => _redeemLoading[reward.id] = false);
      return;
    }

    final dio = DioClient().dio;
    final repo = RewardsRepository(
      remoteDataSource: RewardsRemoteDataSource(client: dio),
    );

    final result = await repo.redeemReward(userId: userId, rewardId: reward.id);

    if (!mounted) return;

    setState(() => _redeemLoading[reward.id] = false);

    if (result == null || !result.success) {
      _showSnack(result?.message ?? 'Đổi điểm thất bại, vui lòng thử lại');
      return;
    }

    setState(() {
      _userPoints = result.pointsRemaining;
    });

    await _showSuccessDialog(result.voucherCode, result.message);
    await _loadRewards(showLoading: false);
  }

  Future<void> _showSuccessDialog(String code, String message) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Chúc mừng!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.confirmation_number_outlined,
                        color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        code.isNotEmpty ? code : '---',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Đóng'),
            ),
          ],
        );
      },
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pointsText = NumberFormat.decimalPattern('vi_VN')
        .format(_userPoints)
        .toString();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Danh sách đổi thưởng'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () => _loadRewards(showLoading: false),
        child: _isLoading ? _buildLoading() : _buildContent(pointsText),
      ),
    );
  }

  Widget _buildContent(String pointsText) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 12),
        _buildPointsHeader(pointsText),
        const SizedBox(height: 8),
        if (_rewards.isEmpty)
          _buildEmptyState()
        else
          ..._rewards.map(
            (reward) => RewardItemCard(
              reward: reward,
              userPoints: _userPoints,
              isRedeeming: _redeemLoading[reward.id] ?? false,
              onRedeem: () => _redeemReward(reward),
            ),
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildPointsHeader(String pointsText) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.stars_rounded, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Điểm hiện tại',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              Text(
                '$pointsText điểm',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.card_giftcard, size: 54, color: Colors.grey[400]),
          const SizedBox(height: 12),
          const Text(
            'Chưa có quà tặng khả dụng',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Vui lòng quay lại sau',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 12),
        _buildPointsHeader('---'),
        const SizedBox(height: 8),
        ...List.generate(4, (index) => _buildShimmerCard()),
      ],
    );
  }

  Widget _buildShimmerCard() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Card(
        elevation: 1,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
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
                      width: 120,
                      height: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 54,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
