// =============================================================================
// live_reward_widget.dart
// =============================================================================
// Widget panel PHẦN THƯỞNG (reward) hiển thị ở cạnh phải màn hình live.
//
// Giao diện:
//   ┌─────────────┐
//   │ PHẦN THƯỞNG │  ← header vàng
//   ├─────────────┤
//   │ Nhấn để     │
//   │ nhận thưởng │
//   │             │
//   │ [Điểm danh] │  ← nút với 80 xu (bị dim nếu đã điểm danh)
//   │  80 xu      │
//   │             │
//   │ ⏱ 05:23    │  ← timer xem
//   │ +5xu/phút   │
//   │ [====  ] ▷  │  ← progress bar
//   └─────────────┘
//
// SỬ DỤNG:
//   LiveRewardWidget(
//     reward: stream.reward,
//     onAttendanceTap: () => provider.claimAttendanceReward(streamId),
//   )
// =============================================================================

import 'package:flutter/material.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/models/live_stream_model.dart';

class LiveRewardWidget extends StatelessWidget {
  final LiveReward reward;
  final VoidCallback onAttendanceTap;
  final VoidCallback? onRewardPanelTap;

  const LiveRewardWidget({
    super.key,
    required this.reward,
    required this.onAttendanceTap,
    this.onRewardPanelTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRewardPanelTap,
      child: Container(
        width: AppSizes.rewardPanelWidth,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          border: Border.all(
            color: AppColors.gold.withValues(alpha: 0.8),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ─────────────────────────────────────────────────
            _buildHeader(),

            // ── Divider ────────────────────────────────────────────────
            Container(
              height: 0.5,
              color: AppColors.gold.withValues(alpha: 0.4),
            ),

            // ── Content ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(AppSizes.xs + 2),
              child: Column(
                children: [
                  _buildSubtitle(),
                  const SizedBox(height: AppSizes.sm),
                  _buildAttendanceButton(),
                  const SizedBox(height: AppSizes.sm),
                  _buildWatchTimer(),
                  const SizedBox(height: AppSizes.xs),
                  _buildProgressBar(),
                  const SizedBox(height: AppSizes.xs),
                  _buildTotalCoins(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header PHẦN THƯỞNG
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.xs,
        vertical: AppSizes.xs,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.goldDark, AppColors.gold],
        ),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppSizes.radiusMd - 1),
          topRight: Radius.circular(AppSizes.radiusMd - 1),
        ),
      ),
      child: const Text(
        AppStrings.liveRewardPanel,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: AppSizes.fontXs,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Subtitle
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSubtitle() {
    return const Text(
      AppStrings.liveRewardTap,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: AppColors.gold,
        fontSize: 9,
        fontWeight: FontWeight.w500,
        height: 1.3,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Nút điểm danh
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAttendanceButton() {
    final hasAttended = reward.hasAttended;

    return GestureDetector(
      onTap: hasAttended ? null : onAttendanceTap,
      child: AnimatedOpacity(
        opacity: hasAttended ? 0.5 : 1.0,
        duration: AppDurations.normal,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
          decoration: BoxDecoration(
            gradient: hasAttended
                ? const LinearGradient(
                    colors: [Color(0xFF757575), Color(0xFF9E9E9E)],
                  )
                : const LinearGradient(
                    colors: [AppColors.goldDark, AppColors.gold],
                  ),
            borderRadius: BorderRadius.circular(AppSizes.radiusSm),
            boxShadow: hasAttended
                ? []
                : [
                    BoxShadow(
                      color: AppColors.gold.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Column(
            children: [
              Text(
                hasAttended ? '✓ Đã điểm danh' : AppStrings.liveAttendance,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!hasAttended) ...[
                const SizedBox(height: 1),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '🪙',
                      style: TextStyle(fontSize: 9),
                    ),
                    Text(
                      ' ${reward.attendanceCoins} ${AppStrings.liveCoins}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Watch timer
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWatchTimer() {
    final mins = reward.watchMinutes;
    final secs = reward.watchSeconds % 60;
    final timeStr =
        '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.timer_outlined,
              color: Colors.white70,
              size: 10,
            ),
            const SizedBox(width: 2),
            Text(
              timeStr,
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppSizes.fontXs,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('🪙', style: TextStyle(fontSize: 9)),
            Text(
              ' +${reward.watchCoins}xu/phút',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 9,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Progress bar đến xu tiếp theo
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProgressBar() {
    final progress = reward.progressToNextReward.clamp(0.0, 1.0);

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white24,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    AppColors.gold,
                  ),
                  minHeight: 4,
                ),
              ),
            ),
            const SizedBox(width: AppSizes.xs),
            const Text('🎁', style: TextStyle(fontSize: 10)),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '${(progress * 100).toInt()}% → ${reward.nextRewardCoins}xu',
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 8,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Total coins earned
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTotalCoins() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.xs,
        vertical: AppSizes.xs - 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🪙', style: TextStyle(fontSize: 10)),
          Text(
            ' ${reward.totalEarnedCoins}',
            style: const TextStyle(
              color: AppColors.gold,
              fontSize: AppSizes.fontSm,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
