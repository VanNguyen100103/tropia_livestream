// =============================================================================
// live_stream_screen.dart
// =============================================================================
// Màn hình xem livestream đầy đủ – tương đương Shopee Live viewer screen.
//
// BỐ CỤC (xem từ trên xuống dưới, từ trái sang phải):
//
//   ┌─────────────────────────────────────────────────────────────────────────┐
//   │ [←]    [Video] [Live] [Cho bạn]                       [+ Tạo]          │ ← TOP BAR
//   │─────────────────────────────────────────────────────────────────────────│
//   │                                                                         │
//   │ 🛍 Con Cưng    ✓verified     [12.4K 👁]  [Theo dõi]  [Khám phá]        │ ← STREAM INFO
//   │ 🏆 Top nhà sáng tạo                                                     │ ← BADGE
//   │                                                                         │
//   │         [VIDEO STREAM / GRADIENT PLACEHOLDER]                           │
//   │                                                                         │
//   │ ┌─────────────────┐                        ┌──────────────────────────┐ │
//   │ │ PRODUCT CARD    │                        │  PHẦN THƯỞNG panel       │ │
//   │ │ (left, 40%)     │                        │  (right side, 90px wide) │ │
//   │ └─────────────────┘                        └──────────────────────────┘ │
//   │                                                                         │
//   │                                          ┌─────────┐                   │
//   │                                          │ ❤ Like  │                   │
//   │                                          │ 💬 Chat │                   │ ← ACTIONS
//   │                                          │ ↗ Share │                   │
//   │                                          └─────────┘                   │
//   │─────────────────────────────────────────────────────────────────────────│
//   │ [CHAT OVERLAY]  ← comments                                              │
//   │─────────────────────────────────────────────────────────────────────────│
//   │ 🎟 Voucher bar (dismissible)                                             │ ← VOUCHER BAR
//   │─────────────────────────────────────────────────────────────────────────│
//   │ [🛒 2]  [Bạn đang nghĩ gì...]                          [↗] [❤]         │ ← BOTTOM BAR
//   └─────────────────────────────────────────────────────────────────────────┘
//
// NAVIGATION:
//   Nhận streamId qua constructor, mở stream trong initState.
//   Pop về khi back.
//
// SỬ DỤNG:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => LiveStreamScreen(streamId: 'stream_001'),
//   ));
// =============================================================================

import 'dart:async';

import 'package:livekit_client/livekit_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show Share;
import 'package:provider/provider.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/features/cart/models/cart_item_model.dart';
import 'package:tropia/features/cart/providers/cart_provider.dart';
import 'package:tropia/features/coupon/data/coupon_repository.dart';
import 'package:tropia/features/cart/screens/checkout_screen.dart';
import 'package:tropia/features/live/data/live_repository.dart';
import 'package:tropia/features/live/services/livekit_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';
import 'package:tropia/features/live/providers/live_provider.dart';
import 'package:tropia/features/live/widgets/livekit_web_viewer.dart';
import 'package:tropia/features/live/widgets/live_actions_widget.dart';
import 'package:tropia/features/live/widgets/live_ai_suggestion_widget.dart';
import 'package:tropia/features/live/widgets/live_chat_widget.dart';
import 'package:tropia/features/live/widgets/live_floating_voucher_widget.dart';
import 'package:tropia/features/live/widgets/live_product_card_widget.dart';
import 'package:tropia/features/live/widgets/live_product_popup.dart';
import 'package:tropia/features/live/widgets/live_reward_widget.dart';
import 'package:tropia/features/live/widgets/live_shop_bottom_sheet.dart';
import 'package:tropia/features/shop/screens/shop_detail_screen.dart';
import 'package:tropia/features/live/widgets/live_voucher_popup.dart';

/// Tag log cho màn hình này
const _tag = 'LiveStreamScreen';

class LiveStreamScreen extends StatefulWidget {
  /// ID của stream cần mở
  final String streamId;

  const LiveStreamScreen({super.key, required this.streamId});

  @override
  State<LiveStreamScreen> createState() => _LiveStreamScreenState();
}

class _LiveStreamScreenState extends State<LiveStreamScreen>
    with TickerProviderStateMixin {
  // Controllers
  late TabController _tabController;
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  final ScrollController _productScrollController = ScrollController();

  // Local UI state
  bool _showVoucherBar = false;
  int  _voucherCountdown = 30;
  Timer? _voucherTimer;

  // Coupons from backend
  List<Map<String, dynamic>> _liveCoupons = [];
  int _currentCouponIndex = 0;

  // ─── LiveKit (viewer) ───────────────────────────────────────────────────────
  Room? _room;
  VideoTrack? _remoteVideoTrack;
  bool _liveKitReady = false;
  // Web/Mobile dùng chung token info
  String? _livekitWsUrl;
  String? _livekitToken;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this, initialIndex: 1);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final provider = context.read<LiveProvider>();
      provider.onSessionEnded = _onHostEndedLive;
      provider.onCouponBroadcasted = _onCouponBroadcasted;
      await provider.openStream(widget.streamId);
      AppLogger.logInfo(_tag, 'Opened stream: ${widget.streamId}');
      await _joinLiveKitRoom();
      await _loadCoupons();
    });
  }

  Future<void> _loadCoupons() async {
    final coupons = await LiveRepository.instance.fetchLiveCoupons(widget.streamId);
    if (!mounted) return;
    if (coupons.isNotEmpty) {
      // Chỉ hiện những coupon chưa được lưu (persist trong CartProvider)
      final cart = context.read<CartProvider>();
      final unsaved = coupons.where(
        (c) => !cart.isLiveCouponSaved(c['code'] as String),
      ).toList();
      if (unsaved.isEmpty) return;
      setState(() {
        _liveCoupons = coupons;
        _currentCouponIndex = coupons.indexOf(unsaved.first);
        _showVoucherBar = true;
        _voucherCountdown = 30;
      });
      _startVoucherCountdown();
    }
  }

  void _startVoucherCountdown() {
    _voucherTimer?.cancel();
    _voucherTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_voucherCountdown > 1) {
          _voucherCountdown--;
        } else {
          _showVoucherBar = false;
          _voucherTimer?.cancel();
        }
      });
    });
  }

  // Được gọi từ provider khi phát hiện coupon broadcast trong chat
  void _onCouponBroadcasted(String couponCode) {
    if (!mounted) return;
    // Tìm coupon đã load theo code
    final idx = _liveCoupons.indexWhere(
      (c) => (c['code'] as String).toUpperCase() == couponCode.toUpperCase(),
    );
    _voucherTimer?.cancel();
    setState(() {
      if (idx >= 0) {
        _currentCouponIndex = idx;
      } else {
        // Coupon chưa load → tạo entry tạm với code
        _liveCoupons.insert(0, {'code': couponCode, 'discount_type': 'fixed', 'discount_value': 0.0});
        _currentCouponIndex = 0;
      }
      _showVoucherBar = true;
      _voucherCountdown = 30;
    });
    _startVoucherCountdown();
  }

  // Được gọi từ host broadcast — hiện lại popup với coupon mới
  void showBroadcastedCoupon(Map<String, dynamic> coupon) {
    if (!mounted) return;
    _voucherTimer?.cancel();
    setState(() {
      // Đẩy coupon broadcast lên đầu nếu chưa có
      final exists = _liveCoupons.any((c) => c['id'] == coupon['id']);
      if (!exists) _liveCoupons.insert(0, coupon);
      _currentCouponIndex = _liveCoupons.indexWhere((c) => c['id'] == coupon['id']);
      _showVoucherBar = true;
      _voucherCountdown = 30;
    });
    _startVoucherCountdown();
  }

  // ── Helper: chuyển LiveProduct → CartItemModel để truyền vào CheckoutScreen ──
  CartItemModel _liveProductToCartItem(
    LiveStream stream,
    LiveProduct product, {
    String? skuId,
  }) {
    final sku = skuId != null
        ? product.skus.where((s) => s.skuId == skuId).firstOrNull
        : null;
    final effectiveSkuId = sku?.skuId ?? skuId ?? product.id;
    return CartItemModel(
      id: effectiveSkuId,
      variantId: effectiveSkuId,
      productId: product.id,
      productName: product.name,
      shopId: stream.sellerId,
      shopName: stream.sellerName,
      imageUrl: product.imageUrl,
      attributes: sku?.selections.entries
              .map((e) => CartAttribute(typeName: e.key, value: e.value))
              .toList() ??
          const [],
      unitPrice: (sku?.salePrice ?? product.salePrice).toInt(),
      originalPrice: (sku?.originalPrice ?? product.originalPrice).toInt(),
      quantity: 1,
      isSelected: true,
    );
  }

  void _navigateToCheckout(LiveStream stream, LiveProduct product,
      {String? skuId}) {
    final item = _liveProductToCartItem(stream, product, skuId: skuId);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(
          items: [item],
          liveSessionId: stream.id,
        ),
      ),
    );
  }

  void _onHostEndedLive() {
    if (!mounted) return;
    if (_room != null) LiveKitService.disconnect(_room!);

    // Refresh danh sách — session đã ended sẽ tự biến mất khỏi tab Live
    context.read<LiveProvider>().refresh();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Buổi live đã kết thúc'),
        content: const Text('Người bán đã kết thúc buổi phát sóng.'),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('Đóng'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinLiveKitRoom() async {
    final stream = context.read<LiveProvider>().currentStream;
    if (stream == null) return;
    try {
      final tokenRes = await LiveKitService.fetchTokenBySession(
        sessionId:   stream.id,
        isPublisher: false,
      );

      // Lưu để web viewer dùng
      if (mounted) {
        setState(() {
          _livekitWsUrl = tokenRes.wsUrl;
          _livekitToken = tokenRes.token;
        });
      }

      if (kIsWeb) {
        // Web: LiveKitWebViewer tự connect, chỉ cần set token info
        if (mounted) setState(() => _liveKitReady = true);
        return;
      }

      // Mobile: join room và lắng nghe track
      _room = await LiveKitService.joinAsViewer(
        tokenRes: tokenRes,
        onHostTrackSubscribed: (participant, pub, track) {
          if (track is VideoTrack && mounted) {
            setState(() { _remoteVideoTrack = track; _liveKitReady = true; });
          }
        },
        onHostTrackUnsubscribed: (participant, pub, track) {
          if (track is VideoTrack && mounted) {
            setState(() { _remoteVideoTrack = null; _liveKitReady = false; });
          }
        },
      );

      // Host đã publish trước khi viewer join
      for (final p in _room!.remoteParticipants.values) {
        for (final pub in p.videoTrackPublications) {
          if (pub.subscribed && pub.track != null) {
            if (mounted) setState(() { _remoteVideoTrack = pub.track as VideoTrack; _liveKitReady = true; });
          }
        }
      }
    } catch (e, st) {
      AppLogger.logError(_tag, 'LiveKit viewer join failed', e, st);
    }
  }

  void _sendComment(LiveProvider provider, LiveStream stream, String text) {
    final msg = text.trim();
    if (msg.isEmpty) return;
    AppLogger.logInfo(_tag, 'Sending comment to ${stream.id}: $msg');
    provider.sendComment(stream.id, msg);
    _commentController.clear();
    _commentFocus.unfocus();
  }

  // Viewer nhấn AI chip → gửi câu hỏi vào chat
  // AI reply do host-side bot xử lý (nếu host đã bật Bot AI)
  void _sendAiQuestion(LiveProvider provider, LiveStream stream, String question) {
    provider.sendComment(stream.id, question);
    AppLogger.logUserEvent(
      action: 'ai_question_sent',
      context: 'LiveStreamScreen',
      metadata: {'question': question},
    );
  }

  // Tap avatar hoặc tên shop → mở ShopDetailScreen
  void _navigateToShop(BuildContext context, LiveStream stream) {
    final shopId = stream.shopId ?? stream.sellerId;
    AppLogger.logUserEvent(
      action: 'shop_profile_tapped',
      context: _tag,
      metadata: {'shopId': shopId, 'shopName': stream.sellerName},
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ShopDetailScreen(shopId: shopId),
      ),
    );
  }

  // Chia sẻ link live — native share sheet (mobile) hoặc copy clipboard (web)
  Future<void> _shareLive(LiveStream stream) async {
    final link = 'https://tropia.app/live/${stream.id}';
    final text = '🔴 ${stream.sellerName} đang live: ${stream.title}\n$link';

    if (kIsWeb) {
      await Clipboard.setData(ClipboardData(text: link));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã copy link live vào clipboard!'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      await Share.share(text);
    }

    AppLogger.logUserEvent(
      action: 'live_shared',
      context: 'LiveStreamScreen',
      metadata: {'streamId': stream.id, 'platform': kIsWeb ? 'web' : 'mobile'},
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _commentController.dispose();
    _commentFocus.dispose();
    _productScrollController.dispose();
    _voucherTimer?.cancel();
    if (_room != null) LiveKitService.disconnect(_room!);
    final provider = context.read<LiveProvider>();
    provider.onSessionEnded = null;
    provider.onCouponBroadcasted = null;
    provider.closeStream();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Màn hình toàn full-screen, ẩn status bar
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        // Khôi phục UI khi back
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        context.read<LiveProvider>().closeStream();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: true,
        body: Consumer<LiveProvider>(
          builder: (context, provider, _) {
            final stream = provider.currentStream;

            if (stream == null) {
              return const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primaryLight,
                ),
              );
            }

            return Stack(
              children: [
                // ── 1. Video background (gradient placeholder) ──────────
                _buildVideoBackground(stream),

                // ── 2. Overlay: tất cả UI lên trên video ───────────────
                _buildOverlayUI(context, provider, stream),

                // ── 3. Product popup (khi active) ────────────────────────
                if (provider.activeProductPopupId != null)
                  _buildProductPopupOverlay(context, provider, stream),

                // ── 4. Voucher popup (khi active) ────────────────────────
                if (provider.activeVoucherPopupId != null)
                  _buildVoucherPopupOverlay(context, provider, stream),

                // ── 5. Shopee-style coupon popup (slide từ dưới lên) ────
                if (_showVoucherBar && _liveCoupons.isNotEmpty)
                  _buildShopeeVoucherPopup(context, provider, stream),

                // ── 6. Floating voucher banner (tự hiện sau 3 giây) ──────
                if (provider.floatingVoucherId != null)
                  _buildFloatingVoucherBanner(context, provider, stream),
              ],
            );
          },
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 1. VIDEO BACKGROUND
  // ─────────────────────────────────────────────────────────────────────────

  /// Video background: LiveKit remote stream if available, else gradient fallback.
  Widget _buildVideoBackground(LiveStream stream) {
    // Flutter Web: LiveKitWebViewer tự manage connection
    if (kIsWeb && _liveKitReady && _livekitWsUrl != null && _livekitToken != null) {
      return LiveKitWebViewer(
        wsUrl: _livekitWsUrl!,
        token: _livekitToken!,
        onVideoReady:   () { if (mounted) setState(() {}); },
        onVideoStopped: () { if (mounted) setState(() {}); },
      );
    }

    // Mobile: render VideoTrack từ host
    if (!kIsWeb && _liveKitReady && _remoteVideoTrack != null) {
      return VideoTrackRenderer(_remoteVideoTrack!);
    }

    // Fallback: gradient + loading indicator
    final colors = stream.gradientColors;
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _parseColor(colors.first),
            _parseColor(colors.last),
            Colors.black,
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.live_tv,
              size: 80,
              color: Colors.white.withValues(alpha: 0.2),
            ),
            const SizedBox(height: AppSizes.sm),
            Text(
              stream.isLive ? '🔴 ĐANG PHÁT SÓNG' : '▶ VIDEO',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: AppSizes.fontLg,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: AppSizes.xs),
            Text(
              stream.title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.3),
                fontSize: AppSizes.fontSm,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. OVERLAY UI
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildOverlayUI(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
  ) {
    return SafeArea(
      child: Column(
        children: [
          // ── TOP BAR ─────────────────────────────────────────────────────
          _buildTopBar(stream),

          // ── STREAM INFO (seller + follow + explore) ─────────────────────
          _buildStreamInfo(context, provider, stream),

          // ── MIDDLE CONTENT (product card + reward + actions) ────────────
          Expanded(
            child: Stack(
              children: [
                // Left side: Product cards list
                Positioned(
                  left: 0,
                  bottom: 0,
                  top: 0,
                  child: _buildProductsList(context, provider, stream),
                ),

                // Right side: Reward panel + Actions
                Positioned(
                  right: AppSizes.sm,
                  bottom: AppSizes.md,
                  child: _buildRightSideWidgets(context, provider, stream),
                ),
              ],
            ),
          ),

          // ── CHAT OVERLAY ─────────────────────────────────────────────────
          _buildChatArea(stream),

          // ── AI SUGGESTION CHIPS ──────────────────────────────────────────
          LiveAiSuggestionWidget(
            suggestions: provider.aiSuggestions,
            isLoading: provider.isSuggestionsLoading,
            onSuggestionTapped: (question) => _sendAiQuestion(provider, stream, question),
          ),

          // ── BOTTOM BAR ───────────────────────────────────────────────────
          _buildBottomBar(context, provider, stream),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildTopBar(LiveStream stream) {
    return Container(
      height: AppSizes.tabBarHeight + AppSizes.md,
      padding: const EdgeInsets.symmetric(horizontal: AppSizes.sm),
      child: Row(
        children: [
          // Back button
          _TopBarButton(
            icon: Icons.arrow_back_ios_new,
            onTap: () {
              AppLogger.logInfo(_tag, 'Back button tapped');
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
              Navigator.of(context).pop();
            },
          ),

          // Tab bar: Video | Live | Cho bạn
          Expanded(
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              indicatorWeight: 2,
              labelStyle: const TextStyle(
                fontSize: AppSizes.fontSm,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: AppSizes.fontSm,
                fontWeight: FontWeight.w400,
              ),
              tabs: const [
                Tab(text: AppStrings.liveTabVideo),
                Tab(text: AppStrings.liveTabLive),
                Tab(text: AppStrings.liveTabForYou),
              ],
              onTap: (i) {
                AppLogger.logInfo(
                  _tag,
                  'Tab tapped: ${['Video', 'Live', 'Cho bạn'][i]}',
                );
              },
            ),
          ),

          // Create button
          _TopBarButton(
            icon: Icons.add_box_outlined,
            onTap: () {
              AppLogger.logInfo(_tag, 'Create stream button tapped');
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng tạo live sắp ra mắt!')),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // STREAM INFO (seller, viewer, follow, explore)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildStreamInfo(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.sm,
        vertical: AppSizes.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Avatar + Name + Verified + Viewer count + Follow + Explore
          Row(
            children: [
              // Avatar nhỏ — tap → ShopDetailScreen
              GestureDetector(
                onTap: () => _navigateToShop(context, stream),
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white,
                  child: ClipOval(
                    child: Image.network(
                      stream.sellerAvatarUrl,
                      width: 36,
                      height: 36,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.xs),

              // Name + viewer count — tap → ShopDetailScreen
              GestureDetector(
                onTap: () => _navigateToShop(context, stream),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 110),
                          child: Text(
                            stream.sellerName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: AppSizes.fontSm,
                              fontWeight: FontWeight.w700,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 4),
                              ],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (stream.isVerified) ...[
                          const SizedBox(width: 3),
                          const Icon(
                            Icons.verified,
                            size: 14,
                            color: AppColors.primaryLight,
                          ),
                        ],
                      ],
                    ),
                    // Viewer count
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.remove_red_eye_outlined,
                          size: 10,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${stream.viewerCountFormatted} ${AppStrings.liveViewers}',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: AppSizes.fontXs,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: AppSizes.xs),

              // Stream title — giữa, giữa shop name và các nút
              Expanded(
                child: Text(
                  stream.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppSizes.fontXs,
                    fontWeight: FontWeight.w500,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),

              const SizedBox(width: AppSizes.xs),

              // Follow button — gọi API thực
              GestureDetector(
                onTap: () async {
                  final wasFollowing = stream.isFollowing;
                  await provider.toggleFollow(stream.id);
                  if (!wasFollowing && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(AppStrings.notifFollowSuccess),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
                },
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.sm,
                    vertical: AppSizes.xs,
                  ),
                  decoration: BoxDecoration(
                    color: stream.isFollowing
                        ? Colors.transparent
                        : AppColors.liveRed,
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                    border: Border.all(
                      color: stream.isFollowing
                          ? Colors.white60
                          : AppColors.liveRed,
                    ),
                  ),
                  child: Text(
                    stream.isFollowing
                        ? AppStrings.liveFollowing
                        : AppStrings.liveFollow,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.fontXs,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(width: AppSizes.xs),

              // Explore button
              GestureDetector(
                onTap: () {
                  AppLogger.logUserEvent(
                    action: 'explore_shop_tapped',
                    context: _tag,
                    metadata: {'streamId': stream.id},
                  );
                  showLiveShopBottomSheet(
                    context: context,
                    stream: stream,
                    provider: provider,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.sm,
                    vertical: AppSizes.xs,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                    border: Border.all(color: Colors.white30),
                  ),
                  child: const Text(
                    AppStrings.liveExplore,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: AppSizes.fontXs,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),

          // Row 2: Featured badge
          if (stream.featuredBadge != null) ...[
            const SizedBox(height: AppSizes.xs),
            Row(
              children: [
                const SizedBox(width: 40), // align với tên
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.xs + 2,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🏆', style: TextStyle(fontSize: 10)),
                      const SizedBox(width: 2),
                      Text(
                        stream.featuredBadge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PRODUCTS LIST (left side, vertical scroll)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProductsList(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
  ) {
    if (stream.products.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(left: AppSizes.sm),
      child: SizedBox(
        width: AppSizes.productCardWidth + AppSizes.sm,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Coupon button (nếu có voucher)
            if (stream.vouchers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSizes.md, bottom: AppSizes.xs),
                child: GestureDetector(
                  onTap: () {
                    final voucher = stream.vouchers.first;
                    _showVoucherBottomSheet(context, provider, stream, voucher);
                  },
                  child: Container(
                    width: AppSizes.productCardWidth,
                    padding: const EdgeInsets.symmetric(horizontal: AppSizes.xs + 2, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      border: Border.all(color: AppColors.liveRed.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.local_offer, color: AppColors.liveRed, size: 13),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            stream.vouchers.first.discountDisplay,
                            style: const TextStyle(
                              color: AppColors.liveRed,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (!stream.vouchers.first.isSaved)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.liveRed,
                              borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                            ),
                            child: const Text('Lưu', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

            // Product list
            Expanded(
              child: ListView.separated(
                controller: _productScrollController,
                padding: EdgeInsets.only(
                  top: stream.vouchers.isEmpty ? AppSizes.md : AppSizes.xs,
                  bottom: AppSizes.md,
                ),
                itemCount: stream.products.length,
                separatorBuilder: (_, __) => const SizedBox(height: AppSizes.sm),
                itemBuilder: (context, index) {
                  final product = stream.products[index];
                  return LiveProductCardWidget(
                    product: product,
                    streamId: stream.id,
                    onTap: () {
                      provider.showProductPopup(stream.id, product.id);
                    },
                    onBuyNow: () {
                      _navigateToCheckout(stream, product);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // RIGHT SIDE: Reward panel + Actions
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildRightSideWidgets(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Reward panel
        LiveRewardWidget(
          reward: stream.reward,
          onAttendanceTap: () {
            provider.claimAttendanceReward(stream.id);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(AppStrings.notifRewardClaimed),
                duration: Duration(seconds: 2),
              ),
            );
          },
          onRewardPanelTap: () {
            AppLogger.logInfo(_tag, 'Reward panel tapped');
          },
        ),

        const SizedBox(height: AppSizes.md),

        // Action buttons
        LiveActionsWidget(
          stream: stream,
          onLike: () {
            provider.toggleLike(stream.id);
          },
          onShare: () => _shareLive(stream),
          onCommentTap: () {
            _commentFocus.requestFocus();
          },
          onFollowTap: () async {
            final wasFollowing = stream.isFollowing;
            await provider.toggleFollow(stream.id);
            if (!wasFollowing && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(AppStrings.notifFollowSuccess),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHAT AREA
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildChatArea(LiveStream stream) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.65,
        child: LiveChatWidget(
          comments: stream.comments,
          maxHeight: 160,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHOPEE-STYLE COUPON POPUP (positioned overlay, slide from bottom)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildShopeeVoucherPopup(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
  ) {
    if (_liveCoupons.isEmpty) return const SizedBox.shrink();
    final coupon = _liveCoupons[_currentCouponIndex.clamp(0, _liveCoupons.length - 1)];

    return Positioned(
      left: AppSizes.md,
      right: AppSizes.md,
      bottom: 80 + MediaQuery.of(context).padding.bottom,
      child: _ShopeeVoucherCard(
        coupon: coupon,
        shopName: stream.sellerName,
        countdown: _voucherCountdown,
        onSave: () {
          _voucherTimer?.cancel();
          final code = (coupon['code'] as String).toUpperCase();
          // Lưu vào CartProvider để persist qua nhiều lần vào/ra live
          context.read<CartProvider>().markLiveCouponSaved(code);
          setState(() => _showVoucherBar = false);
          _applyLiveCouponToCart(context, stream, coupon);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã lưu coupon $code!'),
              duration: const Duration(seconds: 2),
            ),
          );
          AppLogger.logUserEvent(
            action: 'coupon_saved',
            context: _tag,
            metadata: {'code': code},
          );
        },
        onDismiss: () {
          _voucherTimer?.cancel();
          setState(() => _showVoucherBar = false);
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BOTTOM BAR (comment input + action buttons)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildBottomBar(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
  ) {
    return Container(
      padding: const EdgeInsets.only(
        left: AppSizes.sm,
        right: AppSizes.sm,
        top: AppSizes.xs,
        bottom: AppSizes.xs,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.black.withValues(alpha: 0.7),
          ],
        ),
      ),
      child: Row(
        children: [
          // Cart button with count
          _BottomBarButton(
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.shopping_cart_outlined,
                  color: Colors.white,
                  size: AppSizes.iconMd,
                ),
                if (provider.liveCartItemCount > 0)
                  Positioned(
                    top: -4,
                    right: -4,
                    child: Container(
                      width: 16,
                      height: 16,
                      decoration: const BoxDecoration(
                        color: AppColors.liveRed,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          provider.liveCartItemCount > 9
                              ? '9+'
                              : '${provider.liveCartItemCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            onTap: () {
              AppLogger.logInfo(_tag, 'Cart button tapped in live stream');
            },
          ),

          const SizedBox(width: AppSizes.xs),

          // Comment input
          // Chat input
          Expanded(
            child: Theme(
              data: ThemeData(
                inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: const Color(0xCC000000),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              child: TextField(
                controller: _commentController,
                focusNode: _commentFocus,
                style: const TextStyle(color: Colors.white, fontSize: AppSizes.fontSm),
                decoration: InputDecoration(
                  hintText: AppStrings.liveCommentHint,
                  hintStyle: const TextStyle(color: Colors.white54, fontSize: AppSizes.fontSm),
                  filled: true,
                  fillColor: const Color(0xCC000000),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.25), width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                    borderSide: const BorderSide(color: Colors.white54, width: 1),
                  ),
                ),
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (text) => _sendComment(provider, stream, text),
              ),
            ),
          ),

          // Nút gửi – luôn hiện, nằm ngoài input
          GestureDetector(
            onTap: () => _sendComment(provider, stream, _commentController.text),
            child: Container(
              width: 36,
              height: 36,
              margin: const EdgeInsets.only(left: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.85),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
            ),
          ),

          const SizedBox(width: AppSizes.xs),

          // Share button
          _BottomBarButton(
            child: const Icon(
              Icons.reply,
              color: Colors.white,
              size: AppSizes.iconMd,
            ),
            onTap: () => _shareLive(stream),
          ),

          const SizedBox(width: AppSizes.xs),

          // Like button
          _BottomBarButton(
            child: Icon(
              stream.isLiked ? Icons.favorite : Icons.favorite_border,
              color: stream.isLiked ? AppColors.liveRed : Colors.white,
              size: AppSizes.iconMd,
            ),
            onTap: () {
              provider.toggleLike(stream.id);
            },
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. PRODUCT POPUP OVERLAY
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildProductPopupOverlay(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
  ) {
    final productId = provider.activeProductPopupId!;
    LiveProduct? product;
    try {
      product = stream.products.firstWhere((p) => p.id == productId);
    } catch (_) {
      product = stream.products.isNotEmpty ? stream.products.first : null;
    }

    if (product == null) return const SizedBox.shrink();

    final finalProduct = product;
    return GestureDetector(
      // Tap outside để đóng popup
      onTap: provider.hideProductPopup,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // prevent tap-through
            child: LiveProductPopup(
              product: finalProduct,
              onBuyNow: (skuId) {
                provider.hideProductPopup();
                _navigateToCheckout(stream, finalProduct, skuId: skuId);
              },
              onAddToCart: (skuId) async {
                await provider.addSkuToCart(
                  stream.id,
                  finalProduct.id,
                  skuId,
                  1,
                );
                provider.hideProductPopup();
                if (context.mounted) {
                  context.read<CartProvider>().load();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(AppStrings.notifAddedToCart),
                      duration: Duration(seconds: 2),
                    ),
                  );
                }
              },
              onClose: provider.hideProductPopup,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. VOUCHER POPUP OVERLAY
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildVoucherPopupOverlay(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
  ) {
    final voucherId = provider.activeVoucherPopupId!;
    LiveVoucher? voucher;
    try {
      voucher = stream.vouchers.firstWhere((v) => v.id == voucherId);
    } catch (_) {
      voucher = stream.vouchers.isNotEmpty ? stream.vouchers.first : null;
    }

    if (voucher == null) return const SizedBox.shrink();

    final finalVoucher = voucher;
    return GestureDetector(
      onTap: provider.hideVoucherPopup,
      child: Container(
        color: Colors.black54,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {},
            child: LiveVoucherPopup(
              voucher: finalVoucher,
              onSave: () {
                provider.saveVoucher(stream.id, finalVoucher.id);
                _applyLiveVoucherToCart(context, stream, finalVoucher);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(AppStrings.notifVoucherSaved),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              onClose: provider.hideVoucherPopup,
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 5. FLOATING VOUCHER BANNER
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildFloatingVoucherBanner(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
  ) {
    final voucherId = provider.floatingVoucherId!;
    LiveVoucher? voucher;
    try {
      voucher = stream.vouchers.firstWhere((v) => v.id == voucherId);
    } catch (_) {
      return const SizedBox.shrink();
    }

    final finalVoucher = voucher;
    return Positioned(
      left: 0,
      right: 0,
      // Đặt ngay phía trên bottom bar (ước tính ~56px + safe area)
      bottom: 56 + MediaQuery.of(context).padding.bottom,
      child: SafeArea(
        top: false,
        child: LiveFloatingVoucherWidget(
          voucher: finalVoucher,
          shopName: stream.sellerName,
          onSave: () {
            provider.saveVoucher(stream.id, finalVoucher.id);
            provider.dismissFloatingVoucher();
            _applyLiveVoucherToCart(context, stream, finalVoucher);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(AppStrings.notifVoucherSaved),
                duration: Duration(seconds: 2),
              ),
            );
          },
          onDismiss: provider.dismissFloatingVoucher,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helper: Voucher bottom sheet
  // ─────────────────────────────────────────────────────────────────────────

  void _showVoucherBottomSheet(
    BuildContext context,
    LiveProvider provider,
    LiveStream stream,
    LiveVoucher voucher,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => LiveVoucherPopup(
        voucher: voucher,
        onSave: () {
          provider.saveVoucher(stream.id, voucher.id);
          _applyLiveVoucherToCart(context, stream, voucher);
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(AppStrings.notifVoucherSaved),
              duration: Duration(seconds: 2),
            ),
          );
        },
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────

  /// Khi user lưu voucher từ live → apply ngay vào CartProvider nếu có shopId
  void _applyLiveCouponToCart(
    BuildContext context,
    LiveStream stream,
    Map<String, dynamic> coupon,
  ) {
    final shopId = stream.shopId;
    if (shopId == null) return;
    final cm = _couponModelFromMap(coupon);
    if (cm == null) return;
    context.read<CartProvider>().applyShopCoupon(shopId, cm);
  }

  void _applyLiveVoucherToCart(
    BuildContext context,
    LiveStream stream,
    LiveVoucher voucher,
  ) {
    final shopId = stream.shopId;
    if (shopId == null) return;
    context.read<CartProvider>().applyShopCoupon(shopId, _couponModelFromVoucher(voucher));
  }

  CouponModel? _couponModelFromMap(Map<String, dynamic> c) {
    try {
      final code = c['code'] as String? ?? '';
      if (code.isEmpty) return null;
      // Backend trả về snake_case (discount_type, discount_value, min_order_value)
      final discountType = c['discount_type'] as String? ?? 'fixed';
      final val = (c['discount_value'] as num?)?.toDouble() ?? 0;
      DateTime expiresAt;
      try {
        expiresAt = DateTime.parse(c['expires_at'] as String);
      } catch (_) {
        expiresAt = DateTime.now().add(const Duration(days: 7));
      }
      return CouponModel(
        id: c['id'] as String? ?? code,
        code: code,
        discountType: discountType,
        discountValue: val,
        minOrderValue: (c['min_order_value'] as num?)?.toInt() ?? 0,
        maxDiscount: (c['max_discount'] as num?)?.toDouble(),
        expiresAt: expiresAt,
      );
    } catch (_) { return null; }
  }

  CouponModel _couponModelFromVoucher(LiveVoucher v) => CouponModel(
    id: v.id,
    code: v.code,
    discountType: v.isPercentage ? 'percent' : 'fixed',
    discountValue: v.discountValue,
    minOrderValue: v.minOrderValue.toInt(),
    expiresAt: v.expiresAt,
  );

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      return Color(int.parse('FF$h', radix: 16));
    } catch (_) {
      return AppColors.primaryDark;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shopee-style coupon popup card
// ─────────────────────────────────────────────────────────────────────────────

class _ShopeeVoucherCard extends StatefulWidget {
  final Map<String, dynamic> coupon;
  final String shopName;
  final int countdown;
  final VoidCallback onSave;
  final VoidCallback onDismiss;

  const _ShopeeVoucherCard({
    required this.coupon,
    required this.shopName,
    required this.countdown,
    required this.onSave,
    required this.onDismiss,
  });

  @override
  State<_ShopeeVoucherCard> createState() => _ShopeeVoucherCardState();
}

class _ShopeeVoucherCardState extends State<_ShopeeVoucherCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 350));
    _slide = Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeIn));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    await _ctrl.reverse();
    widget.onDismiss();
  }

  Future<void> _save() async {
    widget.onSave();
    await _ctrl.reverse();
  }

  String _formatCouponDiscount(Map<String, dynamic> c) {
    final type  = c['discount_type'] as String? ?? 'fixed';
    final value = (c['discount_value'] as num?)?.toDouble() ?? 0;
    if (type == 'percent') return 'Giảm ${value.toInt()}%';
    if (value >= 1000000) return 'Giảm ${(value / 1000000).toStringAsFixed(1)}tr đ';
    if (value >= 1000)    return 'Giảm ${(value / 1000).toInt()}K đ';
    return 'Giảm ${value.toInt()}đ';
  }

  String _formatCouponDesc(Map<String, dynamic> c) {
    final min = (c['min_order_value'] as num?)?.toDouble() ?? 0;
    final max = (c['max_discount'] as num?)?.toDouble();
    final type = c['discount_type'] as String? ?? 'fixed';
    final parts = <String>[];
    if (min > 0) {
      final minStr = min >= 1000 ? '${(min / 1000).toInt()}K' : '${min.toInt()}';
      parts.add('Đơn từ ${minStr}đ'); // ignore: unnecessary_brace_in_string_interps
    }
    if (type == 'percent' && max != null && max > 0) {
      final maxStr = max >= 1000 ? '${(max / 1000).toInt()}K' : '${max.toInt()}';
      parts.add('Tối đa ${maxStr}đ'); // ignore: unnecessary_brace_in_string_interps
    }
    return parts.isEmpty ? 'Áp dụng cho đơn hàng' : parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(AppSizes.radiusMd),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Shopee-red left block ──────────────────────────────────
                Container(
                  width: 72,
                  color: AppColors.liveRed,
                  child: const Center(
                    child: Icon(Icons.local_offer, color: Colors.white, size: 28),
                  ),
                ),

                // ── Content ───────────────────────────────────────────────
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
                          _formatCouponDiscount(widget.coupon),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: AppSizes.fontLg,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        // Conditions
                        Text(
                          _formatCouponDesc(widget.coupon),
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: AppSizes.fontXs,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        // Tags row
                        Row(
                          children: [
                            const _VoucherTag(label: 'Live', color: AppColors.liveRed),
                            const SizedBox(width: 4),
                            _VoucherTag(label: widget.coupon['code'] as String, color: AppColors.primary),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Save + countdown + close ───────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.sm,
                    vertical: AppSizes.sm,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Lưu button
                      GestureDetector(
                        onTap: _save,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSizes.md,
                            vertical: AppSizes.xs + 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.liveRed,
                            borderRadius: BorderRadius.circular(AppSizes.radiusFull),
                          ),
                          child: const Text(
                            'Lưu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: AppSizes.fontSm,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Countdown
                      Text(
                        '${widget.countdown}s',
                        style: const TextStyle(
                          color: AppColors.liveRed,
                          fontSize: AppSizes.fontXs,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Dismiss X ─────────────────────────────────────────────
                GestureDetector(
                  onTap: _dismiss,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(0, AppSizes.xs, AppSizes.xs, 0),
                    child: Icon(Icons.close, size: 16, color: AppColors.textHint),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _VoucherTag extends StatelessWidget {
  final String label;
  final Color color;
  const _VoucherTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSizes.radiusSm),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.5),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Private helper widgets
// ─────────────────────────────────────────────────────────────────────────────

/// Nút tròn nhỏ trên top bar (back, create)
class _TopBarButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopBarButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
  }
}

/// Nút tác vụ ở bottom bar
class _BottomBarButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;

  const _BottomBarButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.xs),
        child: child,
      ),
    );
  }
}
