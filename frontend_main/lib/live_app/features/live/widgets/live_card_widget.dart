import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:tropia_mobile_app_android/live_app/core/constants/app_constants.dart';
import 'package:tropia_mobile_app_android/live_app/features/live/models/live_stream_model.dart';

import 'hls_viewer_web_stub.dart'
    if (dart.library.js_interop) 'hls_viewer_web.dart';

// Shopee-style full-width live card:
//   Row 1: avatar (ring đỏ nếu live) + tên + verified + viewer count + nút Theo dõi
//   Row 2: ranking badge (nếu có)
//   Thumbnail 16:9 full-width với LIVE badge + featured product overlay

class LiveCardWidget extends StatelessWidget {
  final LiveStream stream;
  final VoidCallback onTap;
  final VoidCallback? onFollowTap;

  const LiveCardWidget({super.key, required this.stream, required this.onTap, this.onFollowTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        color: AppColors.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            _buildThumbnail(),
            const SizedBox(height: AppSizes.xs),
          ],
        ),
      ),
    );
  }

  // ── Header row: avatar + info + follow button ─────────────────────────────

  Widget _buildHeader() {
    final isLive = stream.status == StreamStatus.live;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSizes.md, AppSizes.sm, AppSizes.md, AppSizes.xs),
      child: Row(
        children: [
          // Avatar với ring đỏ khi live
          _buildAvatar(isLive),
          const SizedBox(width: AppSizes.sm),

          // Tên + viewer count
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        stream.sellerName,
                        style: const TextStyle(
                          fontSize: AppSizes.fontMd,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (stream.isVerified) ...[
                      const SizedBox(width: 3),
                      const Icon(Icons.verified, size: 14, color: AppColors.primary),
                    ],
                  ],
                ),
                // Hàng phụ: lượt xem + danh mục. Chỉ hiện khi có dữ liệu thật —
                // tránh để lại icon mắt cô đơn + pill rỗng ("dư ra") khi
                // viewerCount = 0 hoặc category trống.
                if (_buildMeta() case final meta?) ...[
                  const SizedBox(height: 2),
                  meta,
                ],
              ],
            ),
          ),

          const SizedBox(width: AppSizes.sm),

          // Nút Theo dõi
          GestureDetector(
            onTap: onFollowTap,
            child: _buildFollowButton(isLive),
          ),
        ],
      ),
    );
  }

  /// Lượt xem + danh mục. Trả về null khi cả hai đều rỗng để không render
  /// hàng trống. Mỗi phần tử cũng tự ẩn riêng nếu thiếu dữ liệu.
  Widget? _buildMeta() {
    final hasViewers = stream.viewerCount > 0;
    final hasCategory = stream.category.trim().isNotEmpty;
    if (!hasViewers && !hasCategory) return null;

    return Row(
      children: [
        if (hasViewers) ...[
          const Icon(Icons.remove_red_eye_outlined, size: 12, color: AppColors.textHint),
          const SizedBox(width: 3),
          Text(
            stream.viewerCountFormatted,
            style: const TextStyle(fontSize: AppSizes.fontXs, color: AppColors.textHint),
          ),
        ],
        if (hasViewers && hasCategory) const SizedBox(width: AppSizes.sm),
        if (hasCategory)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppSizes.radiusFull),
            ),
            child: Text(
              stream.category,
              style: const TextStyle(
                color: AppColors.primary,
                fontSize: 9,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar(bool isLive) {
    const avatarSize = 44.0;
    const ringSize = 50.0;
    const borderSize = 2.0;

    return SizedBox(
      width: ringSize,
      height: ringSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ring đỏ gradient khi live
          if (isLive)
            Container(
              width: ringSize,
              height: ringSize,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [AppColors.liveRed, Color(0xFFFF6B35)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
            ),
          // Viền trắng cách ly
          Container(
            width: avatarSize + borderSize * 2,
            height: avatarSize + borderSize * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isLive ? Colors.white : Colors.transparent,
            ),
          ),
          // Avatar
          ClipOval(
            child: CachedNetworkImage(
              imageUrl: stream.sellerAvatarUrl,
              width: avatarSize,
              height: avatarSize,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                width: avatarSize,
                height: avatarSize,
                color: AppColors.primaryContainer,
                child: const Icon(Icons.storefront, color: AppColors.primary, size: 22),
              ),
            ),
          ),
          // Badge LIVE dưới avatar
          if (isLive)
            Positioned(
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.liveRed,
                  borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                ),
                child: const Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFollowButton(bool isLive) {
    final following = stream.isFollowing;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 6),
      decoration: BoxDecoration(
        color: following
            ? AppColors.surfaceVariant
            : (isLive ? AppColors.liveRed : AppColors.primary),
        borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        border: following ? Border.all(color: AppColors.divider) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            following ? Icons.check : Icons.add,
            color: following ? AppColors.textSecondary : Colors.white,
            size: 14,
          ),
          const SizedBox(width: 2),
          Text(
            following ? 'Đang theo' : 'Theo dõi',
            style: TextStyle(
              color: following ? AppColors.textSecondary : Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  // ── Thumbnail 16:9 full-width ─────────────────────────────────────────────

  Widget _buildThumbnail() {
    final hlsUrl   = stream.streamUrl;
    final isLive   = stream.status == StreamStatus.live;
    final canAutoplay = isLive && hlsUrl != null && hlsUrl.isNotEmpty;

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Auto-playing muted HLS preview when live; otherwise just
          // the cover image. Wrapped in a VisibilityDetector so a card
          // off-screen tears the video down (saves bandwidth / CPU).
          if (canAutoplay)
            _LivePreviewVideo(
              key: ValueKey(hlsUrl),
              hlsUrl: hlsUrl,
              posterUrl: stream.thumbnailUrl,
              gradientFallback: _buildGradientFallback,
            )
          else
            CachedNetworkImage(
              imageUrl: stream.thumbnailUrl,
              fit: BoxFit.cover,
              placeholder: (_, __) => _buildShimmer(),
              errorWidget: (_, __, ___) => _buildGradientFallback(),
            ),

          // Gradient overlay dưới
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 60,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0xCC000000)],
                ),
              ),
            ),
          ),

          // LIVE / VIDEO badge góc trên trái
          Positioned(
            top: AppSizes.xs,
            left: AppSizes.sm,
            child: _buildStatusBadge(),
          ),

          // Ranking badge nếu có — góc trên phải
          if (stream.featuredBadge != null)
            Positioned(
              top: AppSizes.xs,
              right: AppSizes.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.gold,
                  borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                ),
                child: Text(
                  stream.featuredBadge!,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),

          // Title ở dưới thumbnail
          Positioned(
            bottom: AppSizes.xs,
            left: AppSizes.sm,
            right: AppSizes.sm,
            child: Text(
              stream.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: AppSizes.fontSm,
                fontWeight: FontWeight.w600,
                shadows: [Shadow(blurRadius: 4, color: Colors.black)],
              ),
            ),
          ),

          // Pinned products carousel — góc dưới, scroll ngang khi host
          // ghim nhiều SP. Trước đây chỉ hiện 1 SP featured nên buyer không
          // thấy được host đang bán những gì khác.
          if (stream.products.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 28,
              child: SizedBox(
                height: 100,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
                  itemCount: stream.products.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (_, i) =>
                      _FeaturedProductBadge(product: stream.products[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge() {
    final isLive = stream.status == StreamStatus.live;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm, vertical: 3),
      decoration: BoxDecoration(
        color: isLive ? AppColors.liveRed : AppColors.textSecondary,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            ),
            const SizedBox(width: 3),
          ],
          Text(
            isLive ? 'LIVE' : 'VIDEO',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppSizes.fontXs,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: const ColoredBox(color: Colors.white),
    );
  }

  Widget _buildGradientFallback() {
    final colors = stream.gradientColors;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_parseColor(colors.first), _parseColor(colors.last)],
        ),
      ),
      child: Center(
        child: Icon(Icons.live_tv, color: Colors.white.withValues(alpha: 0.7), size: AppSizes.iconXl),
      ),
    );
  }

  Color _parseColor(String hex) {
    try {
      return Color(int.parse('FF${hex.replaceAll('#', '')}', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Featured product badge — góc dưới trái thumbnail
// ─────────────────────────────────────────────────────────────────────────────

class _FeaturedProductBadge extends StatelessWidget {
  final LiveProduct product;
  const _FeaturedProductBadge({required this.product});

  @override
  Widget build(BuildContext context) {
    final hasDiscount = product.discountPercent > 0;

    return Container(
      width: 110,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(AppSizes.radiusSm)),
                child: CachedNetworkImage(
                  imageUrl: product.imageUrl,
                  width: 110, height: 58, fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => Container(
                    width: 110, height: 58,
                    color: AppColors.surfaceVariant,
                    child: const Icon(Icons.image_outlined, color: AppColors.textHint, size: 20),
                  ),
                ),
              ),
              if (hasDiscount)
                Positioned(
                  top: 0, right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    decoration: const BoxDecoration(
                      color: AppColors.liveRed,
                      borderRadius: BorderRadius.only(
                        topRight: Radius.circular(AppSizes.radiusSm),
                        bottomLeft: Radius.circular(AppSizes.radiusSm),
                      ),
                    ),
                    child: Text('-${product.discountPercent}%',
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),
            child: Text(
              _formatPrice(product.salePrice.toInt()),
              style: const TextStyle(color: AppColors.secondary, fontSize: 10, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: const BoxDecoration(
              color: AppColors.secondary,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppSizes.radiusSm)),
            ),
            child: const Text('Mua ngay',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  String _formatPrice(int price) {
    final s = price.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return '${buf.toString()}đ';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auto-playing muted HLS preview for list cards (TikTok feed style)
// ─────────────────────────────────────────────────────────────────────────────
//
// Loads only when ≥50% of the card is visible on screen and tears down when
// it scrolls away. Always muted — viewer taps the card to open full-screen
// with sound. While the player is initializing or the stream is offline the
// poster image is shown so the layout never flashes black.
//
// ONE-AT-A-TIME RULE (web): SRS responds with `Connection: close` on every
// HLS request, and hls.js makes ~1 request/sec. Five card previews running
// in parallel were exhausting Windows' ephemeral TCP port pool
// (ERR_ADDRESS_IN_USE in Chrome's console). The static [_PreviewSlot]
// holds the single most-visible card; less-visible cards get evicted to
// poster mode so we keep one steady connection instead of five churning.

class _PreviewSlot {
  static _LivePreviewVideoState? _holder;
  static double _holderFraction = 0;

  static void claim(_LivePreviewVideoState s, double fraction) {
    // Same widget re-asserting itself — just update the fraction.
    if (_holder == s) {
      _holderFraction = fraction;
      return;
    }
    // Slot already taken by a more-visible card. Caller stays in poster
    // mode until either it scrolls more into view or the current holder
    // releases.
    if (_holder != null && _holderFraction >= fraction) {
      return;
    }
    _holder?.forceStop();
    _holder = s;
    _holderFraction = fraction;
    s.actuallyStart();
  }

  static void release(_LivePreviewVideoState s) {
    if (_holder == s) {
      _holder = null;
      _holderFraction = 0;
    }
  }
}
class _LivePreviewVideo extends StatefulWidget {
  final String hlsUrl;
  final String posterUrl;
  final Widget Function() gradientFallback;

  const _LivePreviewVideo({
    super.key,
    required this.hlsUrl,
    required this.posterUrl,
    required this.gradientFallback,
  });

  @override
  State<_LivePreviewVideo> createState() => _LivePreviewVideoState();
}

class _LivePreviewVideoState extends State<_LivePreviewVideo> {
  VideoPlayerController? _ctrl;
  bool _ready = false;
  bool _failed = false;
  bool _visible = false;

  /// Spin the player up. On web that's just flipping `_visible` to true so
  /// the build method renders [HlsViewerWeb]; on mobile it actually opens
  /// the video_player network connection.
  Future<void> actuallyStart() async {
    if (kIsWeb) {
      if (mounted) setState(() => _visible = true);
      return;
    }
    if (_ctrl != null) return;
    try {
      final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.hlsUrl));
      _ctrl = ctrl;
      await ctrl.initialize();
      await ctrl.setVolume(0);
      await ctrl.setLooping(true);
      await ctrl.play();
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  /// Counterpart to [actuallyStart]. Called by [_PreviewSlot] when a more-
  /// visible card displaces us, and by [dispose] for cleanup.
  ///
  /// [notify] is false when called from `dispose()` — at that point the
  /// element is about to be defunct and `setState` would trigger
  /// `_lifecycleState != _ElementLifecycle.defunct` assertion. We still
  /// update the bare fields so any in-flight build doesn't see stale
  /// values, but skip the notify.
  Future<void> forceStop({bool notify = true}) async {
    if (kIsWeb) {
      _visible = false;
      if (notify && mounted) setState(() {});
      return;
    }
    final c = _ctrl;
    _ctrl = null;
    _ready = false;
    if (notify && mounted) setState(() {});
    try { await c?.pause(); } catch (_) {}
    try { await c?.dispose(); } catch (_) {}
  }

  void _onVisibility(VisibilityInfo info) {
    // VisibilityDetector can fire one last callback while we're being
    // disposed (during ListView scroll). Drop those so the slot logic
    // doesn't try to setState on a dead widget.
    if (!mounted) return;
    final fraction = info.visibleFraction;
    // <50% visible: definitely poster mode, free the slot if we own it.
    if (fraction <= 0.5) {
      _PreviewSlot.release(this);
      forceStop();
      return;
    }
    // ≥50% visible: bid for the slot. claim() decides whether we actually
    // get to play, based on whether we're more visible than the current
    // holder. Less-visible cards stay in poster mode.
    _PreviewSlot.claim(this, fraction);
  }

  @override
  void dispose() {
    _PreviewSlot.release(this);
    // Fire-and-forget — we can't await an async method here, and the
    // `notify: false` flavor doesn't touch setState, so it's safe to let
    // the camera controller cleanup happen in the background.
    forceStop(notify: false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: Key('live-preview-${widget.hlsUrl}'),
      onVisibilityChanged: _onVisibility,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Poster underneath — shown until video is ready, or forever if
          // the stream is offline / errored.
          CachedNetworkImage(
            imageUrl: widget.posterUrl,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: Colors.black12),
            errorWidget: (_, __, ___) => widget.gradientFallback(),
          ),
          if (kIsWeb && _visible)
            // hls.js-backed muted autoplay preview. Browser autoplay policy
            // allows muted videos to start without a user gesture.
            //
            // loop is intentionally FALSE: a live stream never "ends" so
            // looping is meaningless for it, but the moment the host stops,
            // SRS finalizes the playlist with #EXT-X-ENDLIST and only a
            // couple of segments (0.ts, 1.ts). With loop:true the <video>
            // would replay those forever, hammering the proxy with an
            // endless 0.ts→1.ts→0.ts re-fetch loop. loop:false lets the
            // preview stop on the last frame once the stream is over.
            HlsViewerWeb(
              key: ValueKey('card-${widget.hlsUrl}'),
              hlsUrl: widget.hlsUrl,
              fit: BoxFit.cover,
              autoplay: true,
              muted: true,
              loop: false,
              posterUrl: widget.posterUrl,
            )
          else if (!kIsWeb && _ready && !_failed && _ctrl != null)
            FittedBox(
              fit: BoxFit.cover,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: _ctrl!.value.size.width > 0 ? _ctrl!.value.size.width : 360,
                height: _ctrl!.value.size.height > 0 ? _ctrl!.value.size.height : 640,
                child: VideoPlayer(_ctrl!),
              ),
            ),
        ],
      ),
    );
  }
}
