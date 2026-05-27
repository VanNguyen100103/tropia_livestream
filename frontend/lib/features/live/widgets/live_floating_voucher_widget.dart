// =============================================================================
// live_floating_voucher_widget.dart
// =============================================================================
// Shopee Live-style floating coupon banner shown when the host releases a
// coupon. Auto-dismisses after [autoDismissSeconds] with a visible
// countdown so viewers see exactly how long they have to tap "Lưu".
//
// Layout:
//   ┌──────────────────────────────────────────────────────────┐
//   │ ┌────────┐  Giảm 16%                          ┌──────┐  │
//   │ │   S    │  tối đa 100.000đ cho đơn từ 300K   │ Lưu  │  │
//   │ │        │                                    └──────┘  │
//   │ │ SHOPEE │  [Live] [Idol]                       27s    │
//   │ └────────┘                                              │
//   └──────────────────────────────────────────────────────────┘
//   ▰▰▰▰▰▰▰▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱▱  ← progress bar (orange)
//
// The discount headline is the focal point — viewers should read it from
// the stream in < 1 second. Save button on the right has a high-contrast
// red pill so it stands out against the white card.
// =============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';

class LiveFloatingVoucherWidget extends StatefulWidget {
  final LiveVoucher voucher;
  final String shopName;
  final String? shopLogoUrl;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  /// Seconds before the banner auto-dismisses. Matches Shopee Live's
  /// ~30s window where the coupon is "fresh" before fading.
  final int autoDismissSeconds;

  const LiveFloatingVoucherWidget({
    super.key,
    required this.voucher,
    required this.shopName,
    required this.onSave,
    required this.onDismiss,
    this.shopLogoUrl,
    this.autoDismissSeconds = 30,
  });

  @override
  State<LiveFloatingVoucherWidget> createState() =>
      _LiveFloatingVoucherWidgetState();
}

class _LiveFloatingVoucherWidgetState extends State<LiveFloatingVoucherWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _enter;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  Timer? _tick;
  late int _remaining; // seconds left until auto-dismiss
  // When the user swipes/auto-dismisses, we play the reverse animation
  // before unmounting. During that ~320ms the widget is still in the
  // Stack and its bounding box still eats taps unless we explicitly
  // disable hit-testing — Stack hit-tests children last-first, so the
  // dismissed banner would otherwise hide the chat composer + chips
  // sitting underneath it.
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _enter, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _enter, curve: Curves.easeIn),
    );
    _enter.forward();

    _remaining = widget.autoDismissSeconds;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _remaining--);
      if (_remaining <= 0) _dismiss();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _enter.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    _tick?.cancel();
    if (!mounted) return;
    setState(() => _dismissing = true);
    await _enter.reverse();
    if (mounted) widget.onDismiss();
  }

  Future<void> _save() async {
    widget.onSave();
    _tick?.cancel();
    // Flash the "Đã lưu" state briefly for visual confirmation, then
    // slide the banner out so it stops covering the chat area. The
    // parent's onSave handler is already responsible for surfacing a
    // SnackBar / toast — we just handle the banner lifecycle.
    if (!mounted) return;
    setState(() {}); // rebuild so _buildActionColumn shows "Đã lưu"
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (!mounted) return;
    await _dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_remaining / widget.autoDismissSeconds).clamp(0.0, 1.0);
    return IgnorePointer(
      ignoring: _dismissing,
      child: FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: GestureDetector(
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 150) _dismiss();
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // Fixed banner height — previously used IntrinsicHeight +
                // Row(stretch), which on Flutter web sometimes failed to
                // resolve an intrinsic height (the gradient logo column
                // doesn't expose one). When that fails the RenderBox
                // gets `size: MISSING` and the next hit-test pass aborts
                // for the whole Stack — every overlay (chat input,
                // suggestion chips, like/share buttons) became
                // unclickable until a layout recompute. Pinning the
                // height lets each child size itself against a known
                // box and the issue goes away.
                child: SizedBox(
                  height: 84,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildLogoColumn(),
                            Expanded(child: _buildContent()),
                            _buildActionColumn(),
                          ],
                        ),
                      ),
                      // Countdown progress strip — orange like the
                      // discount accent. Tinted background underneath so
                      // it's visible even when nearly full.
                      Container(
                        height: 3,
                        color: const Color(0xFFFFE0DA),
                        child: FractionallySizedBox(
                          widthFactor: progress,
                          alignment: Alignment.centerLeft,
                          child: Container(
                            color: const Color(0xFFFF5722),
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
      ),
      ),
    );
  }

  Widget _buildLogoColumn() {
    final initial = widget.shopName.isNotEmpty
        ? widget.shopName.characters.first.toUpperCase()
        : 'S';
    return Container(
      width: 72,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFF6F61), Color(0xFFFF3D00)],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ClipOval(
            child: widget.shopLogoUrl != null && widget.shopLogoUrl!.isNotEmpty
                ? Image.network(
                    widget.shopLogoUrl!,
                    width: 38, height: 38, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildLogoFallback(initial),
                  )
                : _buildLogoFallback(initial),
          ),
          const SizedBox(height: 4),
          Text(
            widget.shopName.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogoFallback(String initial) {
    return Container(
      width: 38,
      height: 38,
      color: Colors.white,
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFFFF3D00),
          fontSize: 22,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Discount headline — biggest text in the banner.
          Text(
            widget.voucher.discountDisplay,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF1A1A1A),
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          // Min order / details line.
          Text(
            _buildSubtitle(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF808080),
              fontSize: 11,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          // Tags
          Row(
            children: [
              const _Tag(label: 'Live', color: Color(0xFFFF3B30)),
              const SizedBox(width: 4),
              _Tag(
                label: widget.shopName,
                color: const Color(0xFF1A73E8),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _buildSubtitle() {
    final hasMin = widget.voucher.minOrderValue > 0;
    if (!hasMin) return widget.voucher.description;
    // Format: "tối đa 100.000đ cho đơn từ 300.000đ" — Shopee idiom.
    // We don't have a "max discount cap" field yet, so fall back to
    // just min order when discount is not percent.
    return 'Đơn tối thiểu ${_formatPrice(widget.voucher.minOrderValue)}';
  }

  String _formatPrice(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}tr đ';
    if (v >= 1000) return '${(v / 1000).toInt()}K đ';
    return '${v.toInt()}đ';
  }

  Widget _buildActionColumn() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 10, 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.voucher.isSaved)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 13, color: Color(0xFF2E7D32)),
                  SizedBox(width: 3),
                  Text(
                    'Đã lưu',
                    style: TextStyle(
                      color: Color(0xFF2E7D32),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            )
          else
            InkWell(
              onTap: _save,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B30),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF3B30).withValues(alpha: 0.35),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Lưu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 5),
          Text(
            '${_remaining}s',
            style: const TextStyle(
              color: Color(0xFFFF5722),
              fontSize: 13,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
