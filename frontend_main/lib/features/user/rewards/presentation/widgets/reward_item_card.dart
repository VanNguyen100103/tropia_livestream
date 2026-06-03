import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/models/rewards_models.dart';

class RewardItemCard extends StatelessWidget {
  final RewardItemModel reward;
  final int userPoints;
  final bool isRedeeming;
  final VoidCallback onRedeem;

  const RewardItemCard({
    super.key,
    required this.reward,
    required this.userPoints,
    required this.isRedeeming,
    required this.onRedeem,
  });

  @override
  Widget build(BuildContext context) {
    final canRedeem = reward.canRedeem && userPoints >= reward.pointCost;
    final pointsText = NumberFormat.decimalPattern('vi_VN')
        .format(reward.pointCost)
        .toString();

    return Opacity(
      opacity: canRedeem ? 1.0 : 0.5,
      child: Card(
        elevation: 2,
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
                  color: const Color(0xFFFFF5D1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.card_giftcard,
                  color: Color(0xFFD4A106),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reward.title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$pointsText điểm',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 36,
                child: ElevatedButton(
                  onPressed: canRedeem && !isRedeeming ? onRedeem : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E7D32),
                    disabledBackgroundColor: Colors.grey[400],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: isRedeeming
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Đổi',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
