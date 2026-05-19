// =============================================================================
// live_voucher_popup.dart
// =============================================================================
// Widget popup voucher/coupon hiển thị trong buổi livestream.
//
// Giao diện:
//   ┌──────────────────────────────────┐
//   │  🎫  VOUCHER ĐỘC QUYỀN LIVE     │  ← header
//   │  ─────────────────────────────   │
//   │  [TROPIA20K]  Giảm 20.000đ       │  ← code + mô tả
//   │  Đơn tối thiểu 100.000đ          │
//   │  HH: 23:45:12                    │  ← countdown
//   │                                  │
//   │  [Lưu voucher] [Dùng ngay]       │  ← actions
//   │                             [×]  │  ← nút đóng
//   └──────────────────────────────────┘
//
// Hiển thị dạng bottom sheet slide-up.
//
// SỬ DỤNG:
//   showModalBottomSheet(
//     context: context,
//     builder: (_) => LiveVoucherPopup(
//       voucher: myVoucher,
//       onSave: () => provider.saveVoucher(streamId, voucher.id),
//       onClose: () => Navigator.pop(context),
//     ),
//   );
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';

class LiveVoucherPopup extends StatefulWidget {
  final LiveVoucher voucher;
  final VoidCallback onSave;
  final VoidCallback onClose;
  final VoidCallback? onUseNow;

  const LiveVoucherPopup({
    super.key,
    required this.voucher,
    required this.onSave,
    required this.onClose,
    this.onUseNow,
  });

  @override
  State<LiveVoucherPopup> createState() => _LiveVoucherPopupState();
}

class _LiveVoucherPopupState extends State<LiveVoucherPopup>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;

  // Countdown timer
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();

    // Slide-up animation
    _controller = AnimationController(
      vsync: this,
      duration: AppDurations.popupShow,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));
    _controller.forward();

    // Countdown
    _remaining = widget.voucher.expiresAt.difference(DateTime.now());
    if (_remaining.isNegative) _remaining = Duration.zero;
    _startCountdown();
  }

  @override
  void dispose() {
    _controller.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final newRemaining = widget.voucher.expiresAt.difference(DateTime.now());
      setState(() {
        _remaining = newRemaining.isNegative ? Duration.zero : newRemaining;
      });
      if (_remaining == Duration.zero) {
        _countdownTimer?.cancel();
      }
    });
  }

  String get _countdownText {
    if (_remaining == Duration.zero) return 'Đã hết hạn';
    final h = _remaining.inHours;
    final m = _remaining.inMinutes % 60;
    final s = _remaining.inSeconds % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppSizes.radiusXl),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: AppSizes.sm),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(AppSizes.radiusFull),
              ),
            ),

            // Header
            _buildHeader(),

            const Divider(height: 1),

            // Body
            Padding(
              padding: const EdgeInsets.all(AppSizes.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildVoucherCard(),
                  const SizedBox(height: AppSizes.md),
                  _buildCountdown(),
                  const SizedBox(height: AppSizes.md),
                  _buildActions(),
                  SizedBox(
                    height: MediaQuery.of(context).padding.bottom + AppSizes.sm,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.md,
        AppSizes.sm,
        AppSizes.xs,
        AppSizes.sm,
      ),
      child: Row(
        children: [
          const Text('🎫', style: TextStyle(fontSize: 20)),
          const SizedBox(width: AppSizes.sm),
          const Expanded(
            child: Text(
              'VOUCHER ĐỘC QUYỀN LIVE',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: AppSizes.fontLg,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: AppColors.textSecondary),
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Voucher card
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildVoucherCard() {
    return Container(
      padding: const EdgeInsets.all(AppSizes.md),
      decoration: BoxDecoration(
        color: widget.voucher.isSaved
            ? AppColors.surfaceVariant
            : AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(AppSizes.radiusLg),
        border: Border.all(
          color: widget.voucher.isSaved
              ? AppColors.divider
              : AppColors.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Icon/Discount display
          Container(
            width: 70,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.sm,
              vertical: AppSizes.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            ),
            child: Column(
              children: [
                Text(
                  widget.voucher.isPercentage
                      ? '-${widget.voucher.discountValue.toInt()}%'
                      : '-${(widget.voucher.discountValue / 1000).toInt()}K',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.fontLg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: AppSizes.md),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Code
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.sm,
                    vertical: AppSizes.xs / 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    widget.voucher.code,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: AppSizes.fontMd,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                ),

                const SizedBox(height: AppSizes.xs),

                // Description
                Text(
                  widget.voucher.description,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppSizes.fontSm,
                  ),
                ),

                const SizedBox(height: AppSizes.xs / 2),

                // Min order
                if (widget.voucher.minOrderValue > 0)
                  Text(
                    'Đơn tối thiểu ${_formatPrice(widget.voucher.minOrderValue)}',
                    style: const TextStyle(
                      color: AppColors.textHint,
                      fontSize: AppSizes.fontXs,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Countdown
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCountdown() {
    final isExpired = _remaining == Duration.zero;
    return Row(
      children: [
        Icon(
          Icons.timer_outlined,
          size: AppSizes.iconSm,
          color: isExpired ? AppColors.error : AppColors.warning,
        ),
        const SizedBox(width: AppSizes.xs),
        const Text(
          'Hết hạn sau: ',
          style: TextStyle(
            color: AppColors.textSecondary,
            fontSize: AppSizes.fontSm,
          ),
        ),
        Text(
          _countdownText,
          style: TextStyle(
            color: isExpired ? AppColors.error : AppColors.warning,
            fontSize: AppSizes.fontSm,
            fontWeight: FontWeight.w700,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Action buttons
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildActions() {
    return Row(
      children: [
        // Lưu voucher
        Expanded(
          child: widget.voucher.isSaved
              ? OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.check_circle, size: 16),
                  label: const Text(AppStrings.liveSaved),
                )
              : OutlinedButton.icon(
                  onPressed: widget.onSave,
                  icon: const Icon(Icons.bookmark_border, size: 16),
                  label: const Text(AppStrings.liveSaveVoucher),
                ),
        ),
        const SizedBox(width: AppSizes.sm),
        // Dùng ngay (nếu có callback)
        if (widget.onUseNow != null)
          Expanded(
            child: ElevatedButton(
              onPressed: widget.onUseNow,
              child: const Text('Dùng ngay'),
            ),
          ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  String _formatPrice(double price) {
    if (price >= 1000000) {
      return '${(price / 1000000).toStringAsFixed(1)}tr đ';
    } else if (price >= 1000) {
      return '${(price / 1000).toInt()}K đ';
    }
    return '${price.toInt()}đ';
  }
}
