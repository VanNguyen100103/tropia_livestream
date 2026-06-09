// =============================================================================
// video_player_item.dart
// =============================================================================
// 1 trang video full-screen trong feed dọc (Shopee Video / TikTok style):
//   - Video phủ kín màn (BoxFit.cover), loop, tap để tạm dừng, double-tap để tim
//   - Action rail bên phải: avatar + follow, ♥ like, 💬 comment, ↗ share, đĩa nhạc
//   - Caption + #hashtag góc trái dưới
//
// Controller chỉ phát khi [isActive] = true (trang đang hiển thị trong PageView).
// =============================================================================

import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/models/video_model.dart';
import 'package:tropia_mobile_app_android/live_app/features/video/widgets/initials_avatar.dart';

class VideoPlayerItem extends StatefulWidget {
  final VideoPost video;
  final bool isActive;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onFollow;
  final VoidCallback onOpenProfile;
  final VoidCallback onReport;
  final void Function(VideoProduct product) onOpenProduct;
  final void Function(VideoProduct product) onAddToCart;
  final VoidCallback? onViewed;
  // Nút "..." (Xem thêm) — mở share sheet kiểu Shopee. Ẩn khi null.
  final VoidCallback? onMore;

  const VideoPlayerItem({
    super.key,
    required this.video,
    required this.isActive,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onFollow,
    required this.onOpenProfile,
    required this.onReport,
    required this.onOpenProduct,
    required this.onAddToCart,
    this.onViewed,
    this.onMore,
  });

  @override
  State<VideoPlayerItem> createState() => _VideoPlayerItemState();
}

class _VideoPlayerItemState extends State<VideoPlayerItem> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _errored = false;
  bool _manuallyPaused = false;
  bool _showHeart = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final url = widget.video.playUrl;
    // playUrl is '' when the source isn't a valid http(s) URL — never hand a
    // foreign scheme to the platform player.
    if (url.isEmpty) {
      setState(() => _errored = true);
      return;
    }
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = ctrl;
      await ctrl.initialize();
      await ctrl.setLooping(true);
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _initialized = true);
      if (widget.isActive) {
        ctrl.play();
        widget.onViewed?.call();
      }
    } catch (_) {
      if (mounted) setState(() => _errored = true);
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ctrl = _controller;
    if (ctrl == null || !_initialized) return;
    if (widget.isActive && !oldWidget.isActive) {
      // Became the visible page → restart from top and play.
      _manuallyPaused = false;
      ctrl.seekTo(Duration.zero);
      ctrl.play();
      widget.onViewed?.call();
    } else if (!widget.isActive && oldWidget.isActive) {
      ctrl.pause();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final ctrl = _controller;
    if (ctrl == null || !_initialized) return;
    setState(() {
      if (ctrl.value.isPlaying) {
        ctrl.pause();
        _manuallyPaused = true;
      } else {
        ctrl.play();
        _manuallyPaused = false;
      }
    });
  }

  void _onDoubleTap() {
    if (!widget.video.liked) widget.onLike();
    setState(() => _showHeart = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showHeart = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    return GestureDetector(
      onTap: _togglePlay,
      onDoubleTap: _onDoubleTap,
      onLongPress: widget.onReport,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video / thumbnail / loading ──────────────────────────────────
          Container(color: Colors.black),
          if (_initialized && _controller != null)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _controller!.value.size.width == 0
                    ? 360
                    : _controller!.value.size.width,
                height: _controller!.value.size.height == 0
                    ? 640
                    : _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else
            _buildPlaceholder(v),
          if (!_initialized && !_errored)
            const Center(
              child: SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: Colors.white70,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          if (_errored)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off, color: Colors.white38, size: 44),
                  SizedBox(height: 8),
                  Text(
                    'Không thể phát video',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),

          // ── Paused play icon ─────────────────────────────────────────────
          if (_initialized && _manuallyPaused)
            const Center(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white70,
                size: 84,
              ),
            ),

          // ── Double-tap heart burst ───────────────────────────────────────
          if (_showHeart)
            Center(
              child: AnimatedScale(
                scale: _showHeart ? 1.0 : 0.4,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutBack,
                child: const Icon(
                  Icons.favorite,
                  color: AppColors.liveRed,
                  size: 110,
                ),
              ),
            ),

          // Bottom gradient for caption legibility.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 220,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Right action rail ────────────────────────────────────────────
          Positioned(
            right: AppSizes.sm,
            bottom: 24,
            child: _ActionRail(
              video: v,
              onLike: widget.onLike,
              onComment: widget.onComment,
              onShare: widget.onShare,
              onFollow: widget.onFollow,
              onOpenProfile: widget.onOpenProfile,
              onMore: widget.onMore,
            ),
          ),

          // ── Product overlay + caption (bottom-left) ──────────────────────
          Positioned(
            left: AppSizes.md,
            right: 80,
            bottom: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (v.coupons.isNotEmpty) ...[
                  _CouponStrip(coupons: v.coupons),
                  const SizedBox(height: AppSizes.sm),
                ],
                if (v.products.isNotEmpty) ...[
                  _ProductsOverlay(
                    products: v.products,
                    onOpenProduct: widget.onOpenProduct,
                    onAddToCart: widget.onAddToCart,
                    hasVoucher: v.shopHasVoucher,
                  ),
                  const SizedBox(height: AppSizes.sm),
                ],
                _Caption(video: v, onOpenProfile: widget.onOpenProfile),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholder(VideoPost v) {
    final thumb = v.thumbUrl;
    if (thumb == null) return const SizedBox.shrink();
    return CachedNetworkImage(
      imageUrl: thumb,
      fit: BoxFit.cover,
      errorWidget: (_, __, ___) => const SizedBox.shrink(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ActionRail extends StatelessWidget {
  final VideoPost video;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onFollow;
  final VoidCallback onOpenProfile;
  final VoidCallback? onMore;

  const _ActionRail({
    required this.video,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onFollow,
    required this.onOpenProfile,
    this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AvatarWithFollow(
          // Avatar + theo dõi đều ưu tiên SHOP khi video có shop (ngược lại
          // CREATOR) — avatar shop lấy từ shops.logo_url qua API.
          avatarUrl: video.displayAvatarUrl,
          displayName: video.displayName,
          following: video.isFollowed,
          onTapAvatar: onOpenProfile,
          onTapFollow: onFollow,
        ),
        const SizedBox(height: AppSizes.lg),
        _RailButton(
          icon: video.liked ? Icons.favorite : Icons.favorite_border,
          color: video.liked ? AppColors.liveRed : Colors.white,
          label: _fmt(video.likeCount),
          onTap: onLike,
        ),
        const SizedBox(height: AppSizes.md),
        _RailButton(
          icon: Icons.mode_comment_outlined,
          label: _fmt(video.commentCount),
          onTap: onComment,
        ),
        const SizedBox(height: AppSizes.md),
        _RailButton(
          icon: Icons.reply,
          label: _fmt(video.shareCount),
          onTap: onShare,
        ),
        if (onMore != null) ...[
          const SizedBox(height: AppSizes.md),
          _RailButton(
            icon: Icons.more_horiz,
            label: 'Xem thêm',
            onTap: onMore!,
          ),
        ],
        const SizedBox(height: AppSizes.lg),
        const _MusicDisc(),
      ],
    );
  }
}

class _AvatarWithFollow extends StatelessWidget {
  final String? avatarUrl;
  final String displayName;
  final bool following;
  final VoidCallback onTapAvatar;
  final VoidCallback onTapFollow;

  const _AvatarWithFollow({
    required this.avatarUrl,
    required this.displayName,
    required this.following,
    required this.onTapAvatar,
    required this.onTapFollow,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 64,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          GestureDetector(
            onTap: onTapAvatar,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              // Logo shop / avatar creator; fallback initials cục bộ khi ảnh
              // ngoài (ui-avatars) bị CORS chặn trên web. radius 24 → 48px.
              child: InitialsAvatar(
                imageUrl: avatarUrl,
                name: displayName,
                radius: 24,
              ),
            ),
          ),
          if (!following)
            Positioned(
              bottom: 0,
              child: GestureDetector(
                onTap: onTapFollow,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    color: AppColors.liveRed,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add, color: Colors.white, size: 16),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _RailButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 34,
            shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
          ),
          const SizedBox(height: 3),
          Text(
            label,
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
}

class _MusicDisc extends StatefulWidget {
  const _MusicDisc();

  @override
  State<_MusicDisc> createState() => _MusicDiscState();
}

class _MusicDiscState extends State<_MusicDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 6),
  )..repeat();

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _spin,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF3A3A3A), Color(0xFF1A1A1A)],
          ),
          border: Border.all(color: Colors.white24, width: 4),
        ),
        child: const Icon(Icons.music_note, color: Colors.white, size: 18),
      ),
    );
  }
}

class _Caption extends StatefulWidget {
  final VideoPost video;
  final VoidCallback onOpenProfile;

  const _Caption({required this.video, required this.onOpenProfile});

  @override
  State<_Caption> createState() => _CaptionState();
}

class _CaptionState extends State<_Caption> {
  static const int _collapsedLines = 2;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final v = widget.video;
    final caption = v.caption?.trim() ?? '';
    final hashtagText = v.hashtags.map((h) => '#$h').join(' ');
    final hasCaption = caption.isNotEmpty;
    final hasTags = hashtagText.isNotEmpty;

    // Mô tả + hashtag gộp 1 khối: caption trắng, #hashtag màu gold (kiểu Shopee).
    const baseStyle = TextStyle(
      color: Colors.white,
      fontSize: AppSizes.fontMd,
      height: 1.35,
      shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
    );
    final span = TextSpan(
      style: baseStyle,
      children: [
        if (hasCaption) TextSpan(text: caption),
        if (hasCaption && hasTags) const TextSpan(text: '  '),
        if (hasTags)
          TextSpan(
            text: hashtagText,
            style: const TextStyle(
              color: AppColors.gold,
              fontWeight: FontWeight.w600,
            ),
          ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: widget.onOpenProfile,
          child: Text(
            '@${v.displayName}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontLg,
              fontWeight: FontWeight.w700,
              shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
            ),
          ),
        ),
        if (hasCaption || hasTags) ...[
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, constraints) {
              // Đo thử ở chế độ rút gọn để biết có cần nút "Xem thêm" không.
              final tp = TextPainter(
                text: span,
                maxLines: _collapsedLines,
                textDirection: Directionality.of(context),
              )..layout(maxWidth: constraints.maxWidth);
              final overflows = tp.didExceedMaxLines;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    span,
                    maxLines: _expanded ? null : _collapsedLines,
                    overflow: _expanded
                        ? TextOverflow.clip
                        : TextOverflow.ellipsis,
                  ),
                  if (overflows)
                    GestureDetector(
                      onTap: () => setState(() => _expanded = !_expanded),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _expanded ? 'Thu gọn' : 'Xem thêm',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: AppSizes.fontSm,
                            fontWeight: FontWeight.w700,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

String _fmt(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
  return '$n';
}

/// Định dạng giá VND có dấu chấm phân nhóm: 75000 → "75.000đ".
String _fmtVnd(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
    buf.write(s[i]);
  }
  buf.write('đ');
  return buf.toString();
}

// ─────────────────────────────────────────────────────────────────────────────
// Coupon strip — Shopee Video "Voucher": chip mã giảm giá seller gắn vào clip.
// Chạm 1 chip → copy mã vào clipboard để viewer dán lúc thanh toán.
// ─────────────────────────────────────────────────────────────────────────────

class _CouponStrip extends StatelessWidget {
  final List<VideoCoupon> coupons;

  const _CouponStrip({required this.coupons});

  Future<void> _copy(BuildContext context, VideoCoupon c) async {
    await Clipboard.setData(ClipboardData(text: c.code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép mã ${c.code}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSizes.xs,
      runSpacing: AppSizes.xs,
      children: [
        for (final c in coupons)
          GestureDetector(
            onTap: () => _copy(context, c),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 5),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.secondaryLight, AppColors.secondaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.local_offer, size: 12, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    c.discountLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.fontXs,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.copy, size: 11, color: Colors.white70),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product overlay — Shopee Video "Xem sản phẩm (N)"
// ─────────────────────────────────────────────────────────────────────────────

class _ProductsOverlay extends StatefulWidget {
  final List<VideoProduct> products;
  final void Function(VideoProduct) onOpenProduct;
  final void Function(VideoProduct) onAddToCart;
  final bool hasVoucher;

  const _ProductsOverlay({
    required this.products,
    required this.onOpenProduct,
    required this.onAddToCart,
    this.hasVoucher = false,
  });

  @override
  State<_ProductsOverlay> createState() => _ProductsOverlayState();
}

class _ProductsOverlayState extends State<_ProductsOverlay> {
  // The floating card (1 sản phẩm nổi bật) có thể đóng; chip "Xem sản phẩm"
  // luôn còn để mở lại danh sách đầy đủ.
  bool _cardDismissed = false;

  void _openSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusLg),
        ),
      ),
      builder: (_) => _VideoProductsSheet(
        products: widget.products,
        hasVoucher: widget.hasVoucher,
        onOpenProduct: (p) {
          Navigator.pop(context);
          widget.onOpenProduct(p);
        },
        onAddToCart: (p) {
          Navigator.pop(context);
          widget.onAddToCart(p);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_cardDismissed) ...[
          _MiniProductCard(
            product: widget.products.first,
            hasVoucher: widget.hasVoucher,
            onTap: () => widget.onOpenProduct(widget.products.first),
            onAddToCart: () => widget.onAddToCart(widget.products.first),
            onClose: () => setState(() => _cardDismissed = true),
          ),
          const SizedBox(height: AppSizes.xs),
        ],
        _ViewProductsChip(count: widget.products.length, onTap: _openSheet),
      ],
    );
  }
}

class _MiniProductCard extends StatelessWidget {
  final VideoProduct product;
  final bool hasVoucher;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;
  final VoidCallback onClose;

  const _MiniProductCard({
    required this.product,
    required this.hasVoucher,
    required this.onTap,
    required this.onAddToCart,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final img = product.image;
    final flash = product.hasFlashSale;
    return GestureDetector(
      onTap: onTap,
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Thanh flash-sale (Giảm X% + countdown) — chỉ khi đang flash sale.
            if (flash) _FlashSaleBar(product: product),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: flash
                    ? const BorderRadius.vertical(
                        bottom: Radius.circular(AppSizes.radiusMd),
                      )
                    : BorderRadius.circular(AppSizes.radiusMd),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                        child: SizedBox(
                          width: 46,
                          height: 46,
                          child: img != null
                              ? CachedNetworkImage(
                                  imageUrl: img,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) => _imgFallback(),
                                )
                              : _imgFallback(),
                        ),
                      ),
                      if (product.hasDiscount)
                        Positioned(
                          left: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 3,
                              vertical: 1,
                            ),
                            decoration: const BoxDecoration(
                              color: AppColors.secondary,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(AppSizes.radiusSm),
                                bottomRight: Radius.circular(AppSizes.radiusSm),
                              ),
                            ),
                            child: Text(
                              '-${product.discountPercent}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: AppSizes.xs),
                  Flexible(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppSizes.fontXs,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _fmtVnd(product.displayPrice),
                          style: const TextStyle(
                            fontSize: AppSizes.fontSm,
                            fontWeight: FontWeight.w700,
                            color: AppColors.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSizes.xs),
                  // Icon giỏ → mở sheet chọn biến thể → thêm vào giỏ (chỉ gọi API).
                  GestureDetector(
                    onTap: onAddToCart,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: AppColors.secondary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.add_shopping_cart,
                        size: 18,
                        color: AppColors.secondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // "Mua ngay" → mở chi tiết sản phẩm (chọn biến thể / mua tại đó).
                  ElevatedButton(
                    onPressed: onTap,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSizes.sm,
                        vertical: 6,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppSizes.radiusFull,
                        ),
                      ),
                      textStyle: const TextStyle(
                        fontSize: AppSizes.fontXs,
                        fontWeight: FontWeight.w700,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(hasVoucher ? 'Mua với Voucher' : 'Mua ngay'),
                  ),
                  GestureDetector(
                    onTap: onClose,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 2),
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
          ],
        ),
      ),
    );
  }

  Widget _imgFallback() => Container(
    color: AppColors.surfaceVariant,
    child: const Icon(
      Icons.image_outlined,
      color: AppColors.textHint,
      size: 18,
    ),
  );
}

/// Thanh đầu thẻ khi sản phẩm đang Flash Sale: "⚡ Giảm X%" + countdown HH:MM:SS.
class _FlashSaleBar extends StatelessWidget {
  final VideoProduct product;
  const _FlashSaleBar({required this.product});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 5),
      decoration: const BoxDecoration(
        color: AppColors.secondary,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.radiusMd),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.bolt, color: Colors.white, size: 16),
          const SizedBox(width: 2),
          Text(
            product.discountPercent > 0
                ? 'Giảm ${product.discountPercent}%'
                : 'FLASH SALE',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          if (product.flashEndsAt != null)
            _FlashCountdown(endsAt: product.flashEndsAt!),
        ],
      ),
    );
  }
}

/// Đồng hồ đếm ngược tới [endsAt], cập nhật mỗi giây, hiển thị HH:MM:SS trong
/// các ô tối (kiểu Shopee). Tự dừng timer khi hết giờ.
class _FlashCountdown extends StatefulWidget {
  final DateTime endsAt;
  const _FlashCountdown({required this.endsAt});

  @override
  State<_FlashCountdown> createState() => _FlashCountdownState();
}

class _FlashCountdownState extends State<_FlashCountdown> {
  Timer? _timer;
  late Duration _remaining = _calc();

  Duration _calc() {
    final d = widget.endsAt.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final r = _calc();
      setState(() => _remaining = r);
      if (r == Duration.zero) _timer?.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final h = _two(_remaining.inHours);
    final m = _two(_remaining.inMinutes % 60);
    final s = _two(_remaining.inSeconds % 60);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [_box(h), _sep(), _box(m), _sep(), _box(s)],
    );
  }

  Widget _box(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(3),
    ),
    child: Text(
      t,
      style: const TextStyle(
        color: Colors.white,
        fontSize: AppSizes.fontXs,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _sep() => const Padding(
    padding: EdgeInsets.symmetric(horizontal: 2),
    child: Text(
      ':',
      style: TextStyle(
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: AppSizes.fontXs,
      ),
    ),
  );
}

class _ViewProductsChip extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _ViewProductsChip({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.sm,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.secondaryLight, AppColors.secondaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.22),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shopping_bag, color: Colors.white, size: 16),
            const SizedBox(width: 4),
            Text(
              'Xem sản phẩm ($count)',
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppSizes.fontXs,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.keyboard_arrow_up, color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet liệt kê toàn bộ sản phẩm gắn trong video.
class _VideoProductsSheet extends StatelessWidget {
  final List<VideoProduct> products;
  final void Function(VideoProduct) onOpenProduct;
  final void Function(VideoProduct) onAddToCart;
  final bool hasVoucher;

  const _VideoProductsSheet({
    required this.products,
    required this.onOpenProduct,
    required this.onAddToCart,
    this.hasVoucher = false,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSizes.md,
              AppSizes.md,
              AppSizes.md,
              AppSizes.sm,
            ),
            child: Row(
              children: [
                Text(
                  'Sản phẩm (${products.length})',
                  style: const TextStyle(
                    fontSize: AppSizes.fontLg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: AppSizes.xs),
              itemCount: products.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (_, i) => _SheetProductRow(
                product: products[i],
                hasVoucher: hasVoucher,
                onTap: () => onOpenProduct(products[i]),
                onAddToCart: () => onAddToCart(products[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetProductRow extends StatelessWidget {
  final VideoProduct product;
  final bool hasVoucher;
  final VoidCallback onTap;
  final VoidCallback onAddToCart;

  const _SheetProductRow({
    required this.product,
    required this.hasVoucher,
    required this.onTap,
    required this.onAddToCart,
  });

  @override
  Widget build(BuildContext context) {
    final img = product.image;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.md,
          vertical: AppSizes.sm,
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              child: SizedBox(
                width: 64,
                height: 64,
                child: img != null
                    ? CachedNetworkImage(
                        imageUrl: img,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => _fallback(),
                      )
                    : _fallback(),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: AppSizes.fontSm,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Đã bán ${product.totalSold}',
                    style: const TextStyle(
                      fontSize: AppSizes.fontXs,
                      color: AppColors.textHint,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _fmtVnd(product.displayPrice),
                        style: const TextStyle(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppSizes.fontSm,
                        ),
                      ),
                      if (product.hasDiscount) ...[
                        const SizedBox(width: 6),
                        Text(
                          _fmtVnd(product.basePrice),
                          style: const TextStyle(
                            color: AppColors.textHint,
                            fontSize: AppSizes.fontXs,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            // Icon giỏ → sheet chọn biến thể → thêm vào giỏ (chỉ gọi API).
            GestureDetector(
              onTap: onAddToCart,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_shopping_cart,
                  size: 19,
                  color: AppColors.secondary,
                ),
              ),
            ),
            const SizedBox(width: AppSizes.sm),
            SizedBox(
              height: 34,
              child: ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.secondary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  ),
                  textStyle: const TextStyle(
                    fontSize: AppSizes.fontXs,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text(hasVoucher ? 'Mua với Voucher' : 'Mua ngay'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
    color: AppColors.surfaceVariant,
    child: const Icon(
      Icons.image_outlined,
      color: AppColors.textHint,
      size: 22,
    ),
  );
}
