import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tropia_mobile_app_android/livestream/core/config/app_config.dart';
import 'package:tropia_mobile_app_android/livestream/core/constants/app_constants.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:tropia_mobile_app_android/livestream/core/services/auth_service.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/data/live_repository.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/models/live_stream_model.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/providers/live_provider.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/widgets/hls_viewer.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/widgets/live_actions_widget.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/widgets/live_chat_widget.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/widgets/live_floating_voucher_widget.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/widgets/live_gift_sheet.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/widgets/live_gift_overlay.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/widgets/live_mini_cart_bag.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/widgets/live_product_card_widget.dart';
import 'package:tropia_mobile_app_android/livestream/features/live/widgets/live_product_popup.dart';
import 'package:tropia_mobile_app_android/livestream/features/shop/screens/shop_detail_screen.dart';

import '../widgets/viewer_unload_hook_stub.dart'
    if (dart.library.js_interop) '../widgets/viewer_unload_hook_web.dart';

/// Full viewer screen for an SRS live stream.
///
/// Stack:
///   - [HlsViewer]              fills the background.
///   - Top bar                  back arrow + seller + LIVE badge + viewer count.
///   - Floating product card    bottom-left (taps open [LiveProductPopup]).
///   - [LiveChatWidget]         bottom, last 180 px of comments.
///   - [LiveActionsWidget]      right side (like / share / comment / follow).
///
/// All overlays read state from [LiveProvider], which polls the Go backend.
class LiveStreamScreen extends StatefulWidget {
  final String streamId;

  const LiveStreamScreen({super.key, required this.streamId});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen> {
  String? _hlsUrl;
  String? _error;
  bool _loading = true;
  LiveStream? _stream;

  late final LiveProvider _provider;
  ViewerUnloadHook? _unloadHook;

  // Poll trạng thái phiên như backstop cho WS (WS có thể rớt) — phát hiện
  // host kết thúc live kể cả khi WS không đẩy được event.
  Timer? _statusPoll;
  bool _ended = false;

  // Điều khiển overlay hiệu ứng quà (banner + emoji bay).
  final _giftOverlayKey = GlobalKey<LiveGiftOverlayState>();

  @override
  void initState() {
    super.initState();
    _provider = context.read<LiveProvider>();
    _provider.onSessionEnded = _handleSessionEnded;
    _bootstrap();
  }

  /// The backend now returns the HLS URL as a path-only string (e.g.
  /// `/api/live/streams/<id>/hls/playlist.m3u8`) so the SRS stream_key
  /// never appears anywhere a viewer can see in DevTools. Resolve it
  /// against [AppConfig.backendUrl] for the platform's media stack —
  /// hls.js on web and video_player on mobile both require an absolute
  /// URL.
  String _resolveHlsUrl(String hls) {
    if (hls.isEmpty) return '';
    if (hls.startsWith('http://') || hls.startsWith('https://')) {
      return hls;
    }
    final base = AppConfig.backendUrl.endsWith('/')
        ? AppConfig.backendUrl.substring(0, AppConfig.backendUrl.length - 1)
        : AppConfig.backendUrl;
    final tail = hls.startsWith('/') ? hls : '/$hls';
    return '$base$tail';
  }

  Future<void> _bootstrap() async {
    try {
      final res = await LiveRepository.instance.fetchPlayback(widget.streamId);
      final playback = res['playback'] as Map<String, dynamic>;
      final hls = _resolveHlsUrl((playback['hls'] as String?) ?? '');

      // joinAsViewer is handled inside openStream (it does WS-connect →
      // POST /join → /stats refresh in the right order so the first
      // stats push isn't missed). Calling it here too would double-
      // insert a live_viewers row (ON CONFLICT DO NOTHING absorbs it)
      // and, worse, fire /join BEFORE the WS subscribes → counter
      // sticks at 0 on this client.
      await _provider.openStream(widget.streamId);

      // Web only: register a pagehide/beforeunload handler that fires the
      // /leave call even if the user closes the tab or hits F5 instead of
      // tapping the back button (both bypass State.dispose on Flutter web,
      // leaving viewer_count stuck on the host overlay).
      _unloadHook = installViewerUnloadHook(
        url: '${AppConfig.apiLive}/${widget.streamId}/leave',
        bearerToken: AuthService.instance.accessToken,
      );

      if (!mounted) return;
      setState(() {
        _hlsUrl = hls.isEmpty ? null : hls;
        _stream = _provider.currentStream;
        _loading = false;
      });
      _startStatusPoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _handleSessionEnded() {
    if (!mounted || _ended) return;
    _ended = true;
    _statusPoll?.cancel();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Buổi live đã kết thúc')),
    );
    Navigator.of(context).maybePop();
  }

  // Backstop polling: cứ 5s hỏi /stats; nếu status không còn 'live'
  // (offline/ended) thì coi như host đã kết thúc — không phụ thuộc WS.
  void _startStatusPoll() {
    _statusPoll?.cancel();
    _statusPoll = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (!mounted || _ended) return;
      try {
        final stats = await LiveRepository.instance.fetchSessionStats(widget.streamId);
        final st = stats['status'];
        if (st == 'ended' || st == 'offline') {
          _handleSessionEnded();
        }
      } catch (_) {/* lỗi tạm thời — bỏ qua, lần sau thử lại */}
    });
  }

  /// Re-resolve the HLS playback URL before the player rebuilds. Used by
  /// HlsViewer's "Thử lại" button on web — without this, retry just
  /// reattached hls.js to the same stale URL and immediately errored
  /// again, which is why the button felt broken.
  Future<void> _refetchPlayback() async {
    try {
      final res = await LiveRepository.instance.fetchPlayback(widget.streamId);
      final playback = res['playback'] as Map<String, dynamic>;
      final hls = _resolveHlsUrl((playback['hls'] as String?) ?? '');
      if (!mounted) return;
      if (hls.isEmpty) {
        // Session likely ended or SRS dropped the publisher. Surface the
        // same "buổi live đã kết thúc" path the stats poller uses instead
        // of looping the user back through Thử lại forever.
        _handleSessionEnded();
        return;
      }
      setState(() => _hlsUrl = hls);
    } catch (_) {
      if (!mounted) return;
      _handleSessionEnded();
    }
  }

  @override
  void dispose() {
    _statusPoll?.cancel();
    _provider.onSessionEnded = null;
    _unloadHook?.dispose();
    _unloadHook = null;
    LiveRepository.instance.leaveAsViewer(widget.streamId).catchError((_) {});
    _provider.closeStream();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Colors.white70));
    }
    if (_error != null) {
      return _ErrorState(
        message: _error!,
        onRetry: () {
          setState(() {
            _loading = true;
            _error = null;
          });
          _bootstrap();
        },
      );
    }

    return Consumer<LiveProvider>(
      builder: (context, provider, _) {
        final stream = provider.currentStream ?? _stream;
        if (stream == null) {
          return const Center(
            child: Text('Stream không khả dụng',
                style: TextStyle(color: Colors.white70)),
          );
        }

        return Stack(
          fit: StackFit.expand,
          children: [
            // Video
            if (_hlsUrl != null)
              HlsViewer(
                hlsUrl: _hlsUrl!,
                onRetry: _refetchPlayback,
              )
            else
              Container(
                color: Colors.black,
                alignment: Alignment.center,
                child: const Text(
                  'Stream chưa sẵn sàng',
                  style: TextStyle(color: Colors.white70),
                ),
              ),

            // Top bar
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _TopBar(
                stream: stream,
                onFollowTap: () => provider.toggleFollow(stream.id),
              ),
            ),

            // Shopee Live "GẶP LÊN" banner — when the host pins one
            // product to highlight ("đang giới thiệu"), it floats above
            // the regular product carousel with a pulsing badge so
            // viewers immediately know which item is being demoed.
            if (stream.primaryPinnedProduct != null && stream.pinnedProductIds.isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                top: 70,
                child: Center(
                  child: SizedBox(
                    width: 200,
                    child: _PinnedSpotlight(
                      product: stream.primaryPinnedProduct!,
                      onTap: () => _showProductPopup(stream.primaryPinnedProduct!, stream.id),
                      onBuyNow: () => provider.buyNow(stream.id, stream.primaryPinnedProduct!.id),
                    ),
                  ),
                ),
              ),

            // Right-side actions
            Positioned(
              right: 6,
              bottom: 120,
              child: LiveActionsWidget(
                stream: stream,
                onLike: () => provider.toggleLike(stream.id),
                onShare: () {},
                onCommentTap: () {},
                onFollowTap: () => provider.toggleFollow(stream.id),
                // Tặng quà: chỉ hiện cho viewer (host tự xem stream mình thì
                // ẩn — backend cũng chặn tự tặng).
                onGiftTap: (stream.sellerId == AuthService.instance.currentUserId)
                    ? null
                    : () => LiveGiftSheet.show(
                          context,
                          stream.streamKey,
                          onSent: (g) => _giftOverlayKey.currentState?.addGift(g),
                        ),
              ),
            ),

            // Gift overlay: banner + emoji bay khi có quà (poll gifts/recent
            // + phản hồi tức thì khi chính mình tặng). Phủ toàn màn, không
            // chặn chạm (IgnorePointer bên trong widget).
            Positioned.fill(
              child: LiveGiftOverlay(
                key: _giftOverlayKey,
                streamKey: stream.streamKey,
              ),
            ),

            // NOTE: the "túi đồ live" bag used to live here as a separate
            // Positioned. It now sits inline with the chat composer in
            // Layer B (Row[bag, composer]) so it stays at the same
            // visual level as the input — matches the Shopee Live
            // "bag + chat row" pattern the user asked for.

            // Chat + suggestion chips + input bar at bottom.
            // Gradient scrim from fully transparent at the top to ~70%
            // black at the bottom keeps the chat bubbles + input legible
            // even when the host is streaming a bright background (white
            // wall, daylight) where black-on-white text would be lost.
            //
            // The scrim Container is wrapped in IgnorePointer because
            // its BoxDecoration is opaque to hit-tests across its full
            // width. Stack hit-tests last-child-first, so without this
            // the scrim would eat every tap in its rect — including
            // the heart/share/follow buttons in LiveActionsWidget,
            // which sit at bottom:120 (well inside the scrim's
            // vertical extent). The two PointerInterceptor children
            // (chips + composer) re-enable hit-testing for the only
            // interactive pieces in this layer.
            // Layer A — visual-only chat list + scrim. IgnorePointer
            // because the decorated Container otherwise eats every tap
            // in its full-width rect (heart/share/follow at bottom:120
            // are inside its vertical range; chat messages don't need
            // taps; the dead space between chat bubbles and the
            // composer is pure gradient). Interactive pieces live in
            // Layer B below.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                ignoring: true,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: const [0.0, 0.35, 1.0],
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.45),
                        Colors.black.withValues(alpha: 0.75),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 24, 12, 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LiveChatWidget(
                        comments: stream.comments,
                        // Bumped from default 180 → 200 to lift chat
                        // closer to the carousel without overrunning
                        // the host's face (260 was too tall — voucher
                        // banner ended up overlapping the carousel).
                        maxHeight: 200,
                      ),
                      // Reserve the same vertical footprint the
                      // interactive layer (chips + bag-row) occupies
                      // so the gradient extends behind them visually.
                      // Heights mirror Layer B: chips row 32, bag-row
                      // 56 (bag is the tallest child — composer 44 sits
                      // centered inside it), plus the gaps used there
                      // (4 + 6) and the bottom padding (8).
                      SizedBox(
                        height: (provider.aiSuggestions.isNotEmpty
                                ? (4.0 + 32.0)
                                : 0.0) +
                            6.0 +
                            56.0 +
                            8.0,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Pinned product carousel — horizontal row anchored to the
            // TOP-left, just under the shop bar (or under the pinned
            // spotlight when one is set). Bottom-anchoring overlapped
            // the chat scrim and made messages collide with the cards,
            // so we pin to the top instead — same Shopee Live affordance
            // but out of the chat's vertical lane. Width is capped by
            // `right: 60` so it doesn't run under the right-side actions
            // column; height fits the compact card (image 68 + name 2
            // lines + price + button + paddings).
            if (stream.products.isNotEmpty)
              Positioned(
                left: 8,
                right: 60,
                top: stream.primaryPinnedProduct != null ? 120 : 70,
                height: 165,
                child: PointerInterceptor(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.zero,
                    itemCount: stream.products.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 6),
                    itemBuilder: (_, i) {
                      final p = stream.products[i];
                      // Align wrapper: horizontal ListView stretches items
                      // to fill cross-axis (165px) by default, which left
                      // an empty white tail under each card. Aligning to
                      // topCenter pins the card to natural intrinsic
                      // height and leaves the rest transparent.
                      return Align(
                        alignment: Alignment.topCenter,
                        child: LiveProductCardWidget(
                          product: p,
                          streamId: stream.id,
                          onTap: () => _showProductPopup(p, stream.id),
                          onBuyNow: () => provider.buyNow(stream.id, p.id),
                          onAddToCart: () => _addToCart(p),
                        ),
                      );
                    },
                  ),
                ),
              ),

            // Layer B — interactive chips + bag + composer. Sits at
            // higher z than the scrim so taps land here;
            // PointerInterceptor routes the click through the HTML
            // <video> stacking context on Flutter web. The bag shares
            // the composer's row so both anchor to the same baseline at
            // bottom: 8 (CrossAxisAlignment.end), which is what the
            // user asked for ("dời bag xuống ngang chỗ type chat").
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (provider.aiSuggestions.isNotEmpty) ...[
                    PointerInterceptor(
                      child: _SuggestionChipsRow(
                        suggestions: provider.aiSuggestions,
                        onTap: (q) => provider.sendComment(stream.id, q),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  PointerInterceptor(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        LiveMiniCartBag(streamId: stream.id),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _ChatComposer(
                            onSubmit: (text) => provider.sendComment(stream.id, text),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Floating voucher banner (entry banner). Shown when provider has
            // a non-null floatingVoucherId for this stream.
            if (provider.floatingVoucherId != null && stream.vouchers.isNotEmpty)
              Builder(builder: (_) {
                final vId = provider.floatingVoucherId;
                LiveVoucher? v;
                for (final x in stream.vouchers) {
                  if (x.id == vId) { v = x; break; }
                }
                v ??= stream.vouchers.first;
                // Cap the banner at 360 px so it doesn't stretch the full
                // width of a desktop browser. On mobile the screen is
                // narrower than 360 so this is a no-op there.
                // Banner sits ABOVE the chat composer + suggestion
                // chips. Chat scrim takes ~chat(200) + chips(32) +
                // bag-row(56) + padding ≈ 330px from bottom, so anchor
                // the banner at bottom:350 to clear it. If we don't,
                // the 360×~80 banner rect overlaps the chips/composer
                // and — because Stack hit-tests last-child-first — the
                // banner (even mid-dismiss with opacity≈0) eats taps,
                // making the input and chips look broken.
                return Positioned(
                  left: 12,
                  bottom: 350,
                  width: 360,
                  child: LiveFloatingVoucherWidget(
                    voucher: v,
                    shopName: stream.sellerName,
                    shopLogoUrl: stream.sellerAvatarUrl,
                    onSave: () {
                      provider.saveVoucher(stream.id, v!.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Đã lưu mã ${v.code}'),
                          duration: const Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    onDismiss: () => provider.dismissFloatingVoucher(),
                  ),
                );
              }),
          ],
        );
      },
    );
  }

  /// Add-to-cart shortcut from the live card. Uses the provider's
  /// addSkuToCart with skuId=null so it routes through the live-add
  /// endpoint (the row gets cart_items.variant_id = live_session_products.id
  /// — see CLAUDE.md note on the overload). Variant products are
  /// short-circuited by the card itself: they open the SKU picker
  /// instead of calling this, because we can't put a multi-SKU product
  /// in the cart without a chosen variant.
  Future<void> _addToCart(LiveProduct product) async {
    final stream = _provider.currentStream;
    if (stream == null) return;
    if (!AuthService.instance.isSignedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đăng nhập để thêm vào giỏ hàng')),
      );
      return;
    }
    try {
      await _provider.addSkuToCart(stream.id, product.id, null, 1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã thêm "${product.name}" vào giỏ'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Không thêm được: $e')),
      );
    }
  }

  void _showProductPopup(LiveProduct product, String streamId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetCtx) => LiveProductPopup(
        product: product,
        onBuyNow: (skuId) {
          Navigator.of(sheetCtx).pop();
          if (skuId != null) {
            _provider.buySkuNow(streamId, product.id, skuId);
          } else {
            _provider.buyNow(streamId, product.id);
          }
        },
        onAddToCart: (skuId) {
          Navigator.of(sheetCtx).pop();
          if (skuId != null) {
            _provider.addSkuToCart(streamId, product.id, skuId, 1);
          } else {
            _provider.addToCart(streamId, product.id);
          }
        },
        onClose: () => Navigator.of(sheetCtx).pop(),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final LiveStream stream;
  final VoidCallback onFollowTap;
  const _TopBar({required this.stream, required this.onFollowTap});

  void _openShop(BuildContext context) {
    // Prefer shopId (Shop UUID) — that's what ShopDetailScreen.getBySlug
    // expects. Falls back to sellerId so legacy streams without a shop
    // record still navigate somewhere instead of dead-ending.
    final shopRef = stream.shopId ?? stream.sellerId;
    if (shopRef.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShopDetailScreen(shopId: shopRef),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(24),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        const SizedBox(width: 10),
        // Avatar + tên shop là tap target để mở Shop Detail (Shopee-style).
        // Gộp 2 widget vào một GestureDetector để tap vùng nào của cụm
        // shop info cũng navigate được.
        GestureDetector(
          onTap: () => _openShop(context),
          behavior: HitTestBehavior.opaque,
          child: ClipOval(
            child: Image.network(
              stream.sellerAvatarUrl,
              width: 36,
              height: 36,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 36, height: 36, color: Colors.grey,
                child: const Icon(Icons.person, color: Colors.white70),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () => _openShop(context),
            behavior: HitTestBehavior.opaque,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stream.sellerName,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${_formatViewers(stream.viewerCount)} đang xem',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        // Shopee-style inline follow pill — primary CTA the viewer sees
        // before they even reach the side toolbar. Hides once the user
        // already follows the shop so it doesn't waste space.
        if (!stream.isFollowing) ...[
          const SizedBox(width: 6),
          _FollowPill(onTap: onFollowTap),
        ],
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.error,
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'LIVE',
            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  String _formatViewers(int n) {
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '$n';
  }
}

class _FollowPill extends StatelessWidget {
  final VoidCallback onTap;
  const _FollowPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: AppColors.liveRed,
          borderRadius: BorderRadius.circular(AppSizes.radiusFull),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add, color: Colors.white, size: 14),
            SizedBox(width: 2),
            Text(
              'Theo dõi',
              style: TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 56),
            const SizedBox(height: 12),
            Text(
              'Không vào được phòng:\n$message',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat composer + DeepSeek suggestion chips
// ─────────────────────────────────────────────────────────────────────────────

class _SuggestionChipsRow extends StatelessWidget {
  final List<String> suggestions;
  final void Function(String) onTap;

  const _SuggestionChipsRow({required this.suggestions, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, i) {
          final q = suggestions[i];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onTap(q),
              borderRadius: BorderRadius.circular(AppSizes.radiusFull),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      color: AppColors.gold.withValues(alpha: 0.9),
                      size: 11,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      q,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatComposer extends StatefulWidget {
  final void Function(String) onSubmit;
  const _ChatComposer({required this.onSubmit});

  @override
  State<_ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<_ChatComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit() {
    final t = _controller.text.trim();
    if (t.isEmpty) return;
    widget.onSubmit(t);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              // Frosted-dark pill: 55% black so chat bubbles + video both
              // bleed through subtly, but the input still has enough
              // contrast against white walls / daylight backgrounds that
              // the user reported washed out earlier. White hairline border
              // for the Shopee Live look.
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(AppSizes.radiusFull),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.35),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: Colors.white.withValues(alpha: 0.7),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    focusNode: _focus,
                    cursorColor: Colors.white,
                    cursorWidth: 1.5,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      // Web's <input> defaults inject Chrome's autofill /
                      // platform background. Disable decoration explicitly
                      // by letting the parent Container draw the bg and
                      // forcing the field to be a plain transparent text
                      // surface — that's why we kept seeing a white box
                      // despite setting a dark color in the decoration.
                    ),
                    decoration: InputDecoration(
                      hintText: 'Bình luận trực tiếp...',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                      border: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _submit(),
                    onChanged: (_) => setState(() {}), // refresh send btn glow
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Send button: gradient pill that brightens once there's text.
        // Bigger tap target (44×44) so it's reachable on phones without
        // hunting the thumb.
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _controller.text.trim().isEmpty
                  ? [
                      AppColors.primary.withValues(alpha: 0.45),
                      AppColors.primary.withValues(alpha: 0.45),
                    ]
                  : const [AppColors.primary, AppColors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: _controller.text.trim().isEmpty
                ? null
                : [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.45),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
          ),
          child: Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _submit,
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

/// Shopee Live-style "GẶP LÊN" spotlight banner shown above the product
/// carousel when the host pins one product. Bigger thumbnail + animated
/// "ĐANG GIỚI THIỆU" label so viewers immediately spot the item being
/// demoed. Tapping the banner opens the same product popup as the
/// carousel cards; the inline "Mua" button is for one-tap checkout.
class _PinnedSpotlight extends StatefulWidget {
  final LiveProduct product;
  final VoidCallback onTap;
  final VoidCallback onBuyNow;
  const _PinnedSpotlight({
    required this.product,
    required this.onTap,
    required this.onBuyNow,
  });

  @override
  State<_PinnedSpotlight> createState() => _PinnedSpotlightState();
}

class _PinnedSpotlightState extends State<_PinnedSpotlight>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFF4D4F), width: 1),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.network(
                p.imageUrl,
                width: 32, height: 32, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 32, height: 32, color: Colors.white12,
                  child: const Icon(Icons.image_not_supported, size: 14, color: Colors.white54),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FadeTransition(
                    opacity: Tween<double>(begin: 0.55, end: 1.0).animate(_pulse),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF4D4F),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child: const Text(
                        'ĐANG GIỚI THIỆU',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    p.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600, fontSize: 10,
                    ),
                  ),
                  Text(
                    '${p.salePrice.toInt()}đ',
                    style: const TextStyle(
                      color: Color(0xFFFFD54F),
                      fontWeight: FontWeight.w700,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            ElevatedButton(
              onPressed: widget.onBuyNow,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF4D4F),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'Mua',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
