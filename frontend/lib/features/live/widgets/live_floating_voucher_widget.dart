// =============================================================================
// live_floating_voucher_widget.dart
// =============================================================================
// Banner voucher nổi (floating) xuất hiện tự động khi vào live.
//
// Thiết kế giống Shopee Live: card ngang có logo shop, mã giảm giá, nút Lưu.
// Slide in từ dưới, tự đóng sau 8 giây, user có thể swipe-down để dismiss.
//
// Giao diện:
//   ┌──────────────────────────────────────────────────────┐
//   │ [S]  Giảm 25%                              [Lưu]  ✕ │
//   │      tối đa 200.000đ cho đơn từ 9...               │
//   │      Live  Hàng Quốc Tế                            │
//   └──────────────────────────────────────────────────────┘
//
// Vị trí: phía trên bottom bar, chiếm toàn bộ chiều ngang.
// =============================================================================

import 'package:flutter/material.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';

class LiveFloatingVoucherWidget extends StatefulWidget {
  final LiveVoucher voucher;
  final String shopName;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  const LiveFloatingVoucherWidget({
    super.key,
    required this.voucher,
    required this.shopName,
    required this.onSave,
    required this.onDismiss,
  });

  @override
  State<LiveFloatingVoucherWidget> createState() =>
      _LiveFloatingVoucherWidgetState();
}

class _LiveFloatingVoucherWidgetState extends State<LiveFloatingVoucherWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.6),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _controller.reverse();
    widget.onDismiss();
  }

  Future<void> _save() async {
    widget.onSave();
    await _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            // Swipe down to dismiss
            if (details.primaryVelocity != null &&
                details.primaryVelocity! > 150) {
              _dismiss();
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(
              horizontal: AppSizes.md,
              vertical: AppSizes.xs,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusMd),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Left accent strip (màu brand) ────────────────────
                    Container(
                      width: 6,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.primary, AppColors.primaryDark],
                        ),
                      ),
                    ),

                    // ── Shop logo ────────────────────────────────────────
                    Container(
                      width: 48,
                      color: AppColors.primaryContainer,
                      child: Center(
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Text(
                              'T',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Content ──────────────────────────────────────────
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.sm,
                          vertical: AppSizes.sm,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Discount headline
                            Text(
                              widget.voucher.discountDisplay,
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: AppSizes.fontMd,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            // Description
                            Text(
                              widget.voucher.description,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: AppSizes.fontXs,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            // Tags
                            Row(
                              children: [
                                const _Tag(
                                  label: 'Live',
                                  color: AppColors.liveRed,
                                ),
                                const SizedBox(width: 4),
                                _Tag(
                                  label: widget.shopName,
                                  color: AppColors.primary,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ── Save button ──────────────────────────────────────
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.sm,
                        vertical: AppSizes.sm,
                      ),
                      child: widget.voucher.isSaved
                          ? const Icon(
                              Icons.check_circle,
                              color: AppColors.primary,
                              size: 22,
                            )
                          : GestureDetector(
                              onTap: _save,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSizes.sm,
                                  vertical: AppSizes.xs,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.liveRed,
                                  borderRadius: BorderRadius.circular(
                                    AppSizes.radiusFull,
                                  ),
                                ),
                                child: const Text(
                                  'Lưu',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: AppSizes.fontXs,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                    ),

                    // ── Dismiss ──────────────────────────────────────────
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Padding(
                        padding: EdgeInsets.only(
                          right: AppSizes.sm,
                          top: AppSizes.xs,
                        ),
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;
  final Color color;

  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
