// =============================================================================
// live_actions_widget.dart
// =============================================================================
// Widget nút tác vụ bên phải màn hình livestream (dạng cột dọc).
//
// Bao gồm (từ trên xuống):
//   - Avatar seller (với badge follow)
//   - Nút Like (tim) + số lượng like
//   - Nút Comment (tin nhắn) + số lượng comment
//   - Nút Share (mũi tên)
//   - Floating emoji animation (tự phát lên khi có like mới)
//
// SỬ DỤNG:
//   LiveActionsWidget(
//     stream: currentStream,
//     onLike: () => provider.toggleLike(streamId),
//     onShare: () => provider.shareStream(streamId),
//     onCommentTap: () { /* focus comment input */ },
//   )
// =============================================================================

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:tropia_mobile_app_android/livestream/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/models/live_stream_model.dart';

class LiveActionsWidget extends StatefulWidget {
  final LiveStream stream;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onCommentTap;
  final VoidCallback onFollowTap;
  // Tặng quà (Shopee Live). Null → ẩn nút (ví dụ host xem chính mình).
  final VoidCallback? onGiftTap;

  const LiveActionsWidget({
    super.key,
    required this.stream,
    required this.onLike,
    required this.onShare,
    required this.onCommentTap,
    required this.onFollowTap,
    this.onGiftTap,
  });

  @override
  State<LiveActionsWidget> createState() => _LiveActionsWidgetState();
}

class _LiveActionsWidgetState extends State<LiveActionsWidget>
    with TickerProviderStateMixin {
  // Danh sách emoji đang bay lên
  final List<_FloatingEmoji> _floatingEmojis = [];
  final _random = Random();

  // Animation controller cho nút like
  late AnimationController _likeController;
  late Animation<double> _likeScaleAnim;

  @override
  void initState() {
    super.initState();
    _likeController = AnimationController(
      vsync: this,
      duration: AppDurations.fast,
    );
    _likeScaleAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.4),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.4, end: 1.0),
        weight: 50,
      ),
    ]).animate(_likeController);
  }

  @override
  void dispose() {
    _likeController.dispose();
    super.dispose();
  }

  void _handleLike() {
    widget.onLike();
    _likeController.forward(from: 0);
    _spawnEmoji();
  }

  void _spawnEmoji() {
    const emojis = ['❤️', '🔥', '😍', '👍', '💕', '⭐', '🎉'];
    final emoji = emojis[_random.nextInt(emojis.length)];
    final id = DateTime.now().millisecondsSinceEpoch;

    final controller = AnimationController(
      vsync: this,
      duration: AppDurations.emojiFloat,
    );

    final item = _FloatingEmoji(
      id: id,
      emoji: emoji,
      controller: controller,
      xOffset: (_random.nextDouble() - 0.5) * 20,
    );

    setState(() => _floatingEmojis.add(item));

    controller.forward().then((_) {
      if (mounted) {
        setState(() {
          _floatingEmojis.removeWhere((e) => e.id == id);
        });
        controller.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Floating emojis
          ..._floatingEmojis.map((e) => _buildFloatingEmoji(e)),

          // Actions column
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Seller avatar + follow ──────────────────────────────────
              _buildSellerAvatar(),
              const SizedBox(height: AppSizes.md),

              // ── Like button ─────────────────────────────────────────────
              _buildLikeButton(),
              const SizedBox(height: AppSizes.md),

              // ── Comment button ──────────────────────────────────────────
              _buildCommentButton(),
              const SizedBox(height: AppSizes.md),

              // ── Gift button (Shopee Live) ───────────────────────────────
              if (widget.onGiftTap != null) ...[
                _buildGiftButton(),
                const SizedBox(height: AppSizes.md),
              ],

              // ── Share button ────────────────────────────────────────────
              _buildShareButton(),
            ],
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Seller avatar với nút follow nhỏ
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSellerAvatar() {
    return PointerInterceptor(
      child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onFollowTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Avatar
          CircleAvatar(
            radius: AppSizes.avatarMd / 2,
            backgroundColor: Colors.white,
            child: ClipOval(
              child: CachedNetworkImage(
                imageUrl: widget.stream.sellerAvatarUrl,
                width: AppSizes.avatarMd,
                height: AppSizes.avatarMd,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const Icon(
                  Icons.person,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),

          // Follow / + button ở góc dưới
          Positioned(
            bottom: -4,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  color: widget.stream.isFollowing
                      ? AppColors.primary
                      : AppColors.liveRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Icon(
                  widget.stream.isFollowing ? Icons.check : Icons.add,
                  size: 10,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Like button
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLikeButton() {
    return _ActionButton(
      onTap: _handleLike,
      child: Column(
        children: [
          ScaleTransition(
            scale: _likeScaleAnim,
            child: Icon(
              widget.stream.isLiked ? Icons.favorite : Icons.favorite_border,
              color: widget.stream.isLiked ? AppColors.liveRed : Colors.white,
              size: AppSizes.iconMd,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            widget.stream.likeCountFormatted,
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Gift button (mở bottom sheet chọn quà)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildGiftButton() {
    return _ActionButton(
      onTap: widget.onGiftTap!,
      child: const Column(
        children: [
          Icon(Icons.card_giftcard, color: Colors.white, size: AppSizes.iconMd),
          SizedBox(height: 2),
          Text(
            'Quà',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Comment button
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildCommentButton() {
    final commentCount = widget.stream.comments.length;
    return _ActionButton(
      onTap: widget.onCommentTap,
      child: Column(
        children: [
          const Icon(
            Icons.chat_bubble_outline,
            color: Colors.white,
            size: AppSizes.iconMd,
          ),
          const SizedBox(height: 2),
          Text(
            commentCount > 999 ? '${(commentCount / 1000).toStringAsFixed(1)}K' : '$commentCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Share button
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildShareButton() {
    return _ActionButton(
      onTap: widget.onShare,
      child: const Column(
        children: [
          Icon(
            Icons.reply,
            color: Colors.white,
            size: AppSizes.iconMd,
          ),
          SizedBox(height: 2),
          Text(
            AppStrings.actionShare,
            style: TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w600,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Floating emoji animation
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFloatingEmoji(_FloatingEmoji item) {
    return AnimatedBuilder(
      animation: item.controller,
      builder: (context, child) {
        final progress = item.controller.value;
        final opacity = progress < 0.8 ? 1.0 : (1.0 - progress) / 0.2;
        final translateY = progress * -80;
        final translateX = item.xOffset * progress;

        return Positioned(
          bottom: 100,
          right: 0,
          child: Transform.translate(
            offset: Offset(translateX, translateY),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Text(
                item.emoji,
                style: const TextStyle(fontSize: 20),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper: _ActionButton – nút tác vụ có shadow và ripple effect
// ─────────────────────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;

  const _ActionButton({required this.onTap, required this.child});

  @override
  Widget build(BuildContext context) {
    // Without an explicit hit-test behavior, GestureDetector defaults to
    // deferToChild — so only pixels actually painted by the icon + count
    // text receive taps. The transparent gaps inside the column (between
    // icon and number, around the number) silently ignore touches, which
    // is why the heart felt "dead" on web even though the handler is
    // wired up. `opaque` makes the whole column a single hit-test region.
    // PointerInterceptor lets the click reach Flutter's canvas in the
    // first place — needed on Flutter web because the HtmlElementView
    // <video> sits in the same DOM stacking context and otherwise wins
    // the browser's pointer-events race for buttons sitting over the
    // video area (video has pointer-events:none on the element itself,
    // but its host wrapper div still grabs them in some browsers).
    return PointerInterceptor(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data class cho floating emoji
// ─────────────────────────────────────────────────────────────────────────────

class _FloatingEmoji {
  final int id;
  final String emoji;
  final AnimationController controller;
  final double xOffset;

  const _FloatingEmoji({
    required this.id,
    required this.emoji,
    required this.controller,
    required this.xOffset,
  });
}
