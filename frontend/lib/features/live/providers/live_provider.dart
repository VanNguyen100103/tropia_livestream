// =============================================================================
// live_provider.dart – REAL backend: Supabase Realtime + Node.js API
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia/core/config/app_config.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/cart/data/cart_repository.dart';
import 'package:tropia/features/cart/providers/cart_provider.dart';
import 'package:tropia/features/shop/data/shop_repository.dart';
import 'package:tropia/features/live/data/live_repository.dart';
import 'package:tropia/features/live/data/live_socket.dart';
import 'package:tropia/features/live/models/live_stream_model.dart';
import 'package:tropia/features/live/services/chat_command_parser.dart';
import 'package:tropia/features/live/services/ai_suggestion_service.dart';

const _tag = 'LiveProvider';
const _cacheKey = 'live_streams_cache';

class LiveProvider extends ChangeNotifier {
  // ─── State ────────────────────────────────────────────────────────────────

  List<LiveStream> _streams = [];
  LiveTab _activeTab = LiveTab.live;
  LiveStream? _currentStream;
  bool _isLoading = false;
  String? _errorMessage;
  String? _activeProductPopupId;
  String? _activeVoucherPopupId;
  String? _floatingVoucherId;
  final Map<String, int> _liveCart = {};
  // cart_items.id of every item this user added during the CURRENT live
  // session. Used by the floating mini-cart bag to filter the global cart
  // down to "things from this live". Cleared on stream switch/leave so a
  // viewer who hops to another live doesn't see stale items in the bag.
  final Set<String> _liveSessionCartItemIds = {};
  List<String> _aiSuggestions = [];
  bool _isSuggestionsLoading = false;

  // ─── Realtime channels (chat + stats per-session, list platform-wide) ─────
  // Per-session WS push covers chat + stats events. The platform-wide
  // WS pushes a tiny "list_change" ping whenever a host creates / ends
  // / re-pins a session — the client then re-fetches /streams once.
  // Replaces all three polling timers (3s/5s/15s); only one-shot REST
  // calls remain for bootstrap + reconnect gap recovery.
  LiveSocket? _socket;
  LiveListSocket? _listSocket;
  String? _pollingSessionId;

  // Shared CartProvider, injected via ChangeNotifierProxyProvider in main.dart.
  // Lets live add-to-cart update the global cart state (and thus the bottom-nav
  // badge) immediately, instead of waiting for the user to open the cart tab.
  CartProvider? _cartProvider;
  set cartProvider(CartProvider? value) => _cartProvider = value;

  // Callback để live_stream_screen xử lý khi host kết thúc live
  VoidCallback? onSessionEnded;

  // Callback khi host broadcast coupon → viewer screen hiện popup
  void Function(String couponCode)? onCouponBroadcasted;

  // ─── Host-side tracking ───────────────────────────────────────────────────
  String? _hostSessionId;
  String? _hostChannelName;

  // ─── Getters ──────────────────────────────────────────────────────────────

  List<LiveStream> get streams => List.unmodifiable(_streams);
  LiveTab get activeTab => _activeTab;
  LiveStream? get currentStream => _currentStream;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get activeProductPopupId => _activeProductPopupId;
  String? get activeVoucherPopupId => _activeVoucherPopupId;
  Map<String, int> get liveCart => Map.unmodifiable(_liveCart);
  int get liveCartItemCount => _liveCart.values.fold(0, (s, q) => s + q);
  Set<String> get liveSessionCartItemIds => Set.unmodifiable(_liveSessionCartItemIds);
  List<String> get aiSuggestions => List.unmodifiable(_aiSuggestions);
  bool get isSuggestionsLoading => _isSuggestionsLoading;
  String? get floatingVoucherId => _floatingVoucherId;
  String? get hostSessionId => _hostSessionId;
  String? get hostChannelName => _hostChannelName;

  List<LiveStream> get filteredStreams {
    switch (_activeTab) {
      case LiveTab.live:
        return _streams.where((s) => s.status == StreamStatus.live).toList();
      case LiveTab.video:
        return _streams.where((s) => s.status == StreamStatus.ended).toList();
      case LiveTab.following:
        // Followed shops only — live first, then ended so the buyer can
        // jump into a current broadcast or replay one they missed.
        final followed = _streams.where((s) => s.isFollowing).toList();
        followed.sort((a, b) {
          final aLive = a.status == StreamStatus.live ? 0 : 1;
          final bLive = b.status == StreamStatus.live ? 0 : 1;
          if (aLive != bLive) return aLive.compareTo(bLive);
          return b.viewerCount.compareTo(a.viewerCount);
        });
        return followed;
    }
  }

  // ─── Constructor ──────────────────────────────────────────────────────────

  LiveProvider() {
    _loadStreams();
    // Subscribe to the global list_change push. On every event, run a
    // single REST refresh (the backend coalesces concurrent loads via
    // its 3s Redis cache, so the burst doesn't fan out to Postgres).
    _listSocket = LiveListSocket()
      ..onChange = _onListChange
      ..connect();
  }

  bool _refreshing = false;

  // The backend emits list_change on viewer join/leave, stat ticks,
  // comments, pins, etc. — easily several per second during an active
  // stream (observed ~5×/s). Each refresh() rebuilds the whole card list
  // and re-runs the followed-shop fetch, and that rebuild churns the
  // muted card-preview players: VisibilityDetector + _PreviewSlot
  // re-evaluate, flip `_visible`, and the inner HlsViewerWeb
  // unmounts/remounts → hls.js restarts from segment 0 → the endless
  // 0/1/2.ts re-fetch loop the user reported. Throttle to at most one
  // refresh per window (leading edge), with a single trailing refresh so
  // the final state of a burst isn't missed.
  static const _listRefreshWindow = Duration(seconds: 3);
  Timer? _listRefreshThrottle;
  bool _listChangePending = false;

  void _onListChange() {
    if (_listRefreshThrottle?.isActive ?? false) {
      // Inside the cooldown — remember that something changed and let the
      // trailing timer pick it up instead of firing another refresh now.
      _listChangePending = true;
      return;
    }
    _listChangePending = false;
    _listRefreshThrottle = Timer(_listRefreshWindow, () {
      if (_listChangePending && !_refreshing) {
        _listChangePending = false;
        refresh();
      }
    });
    if (!_refreshing) refresh();
  }

  @override
  void dispose() {
    _listSocket?.close();
    _listSocket = null;
    _listRefreshThrottle?.cancel();
    _listRefreshThrottle = null;
    _stopPolling();
    AiSuggestionService.instance.dispose();
    super.dispose();
  }

  // ─── Load streams ─────────────────────────────────────────────────────────

  Future<void> _loadStreams() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      // Cache gives us something to render immediately, but its
      // `isFollowing` snapshot may be stale (the user could have followed
      // a shop from a different screen since last load). Fetch the live
      // follow set first and re-enrich the cached streams before showing
      // them — that way the "+ Theo dõi" pill doesn't flash on shops the
      // user already follows.
      await _loadStreamsFromCache();
      final followedFuture = ShopRepository.instance.getFollowedShopIds();
      final rowsFuture     = LiveRepository.instance.fetchLiveSessions();

      // Apply the follow set to whatever the cache gave us first, so the
      // first frame is correct.
      final followedIds = await followedFuture;
      if (_streams.isNotEmpty) {
        _streams = _enrichFollowStatus(_streams, followedIds);
        notifyListeners();
      }

      // Then merge in the fresh server data.
      final rows  = await rowsFuture;
      final fresh = rows.map(_rowToLiveStream).toList();
      _streams = _enrichFollowStatus(
        fresh.map(_mergeWithExisting).toList(),
        followedIds,
      );
      if (_streams.isEmpty) {
        AppLogger.logInfo(_tag, 'API returned no streams');
        _errorMessage = 'Không có buổi live nào';
      } else {
        await _saveStreamsToCache();
        AppLogger.logInfo(_tag, 'Loaded ${_streams.length} live sessions');
      }
    } catch (e, st) {
      AppLogger.logError(_tag, 'Failed to load sessions', e, st);
      if (_streams.isEmpty) {
        _errorMessage = 'Không thể tải danh sách live. Kiểm tra kết nối mạng.';
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final rowsFuture     = LiveRepository.instance.fetchLiveSessions();
      final followedFuture = ShopRepository.instance.getFollowedShopIds();
      final rows       = await rowsFuture;
      final followedIds = await followedFuture;
      // Always overwrite _streams with what the server returned, including
      // the empty case (so ended sessions disappear from the card list).
      // BUT: merge per-stream so we don't wipe `products`, `vouchers`,
      // `comments` — the /streams list endpoint only returns session meta,
      // not the deep data fetched separately by openStream(). Without this
      // merge, the 15s auto-refresh would blank the viewer mid-watch
      // (products + chat + vouchers all gone until openStream re-runs).
      final fresh = rows.map(_rowToLiveStream).toList();
      _streams = _enrichFollowStatus(
        fresh.map(_mergeWithExisting).toList(),
        followedIds,
      );
      _errorMessage = _streams.isEmpty ? 'Không có buổi live nào' : null;
      await _saveStreamsToCache();
      AppLogger.logInfo(_tag, 'Refreshed ${_streams.length} live sessions');
    } catch (e, st) {
      AppLogger.logError(_tag, 'Refresh failed', e, st);
      _errorMessage = 'Refresh thất bại. Vui lòng thử lại.';
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// Preserves data fields loaded by openStream() (products, vouchers,
  /// comments, isLiked, isFollowing) when the lightweight /streams list
  /// poll comes back with only session meta. Falls through to the fresh
  /// row when there's no in-memory copy yet.
  LiveStream _mergeWithExisting(LiveStream fresh) {
    final idx = _streams.indexWhere((s) => s.id == fresh.id);
    if (idx == -1) return fresh;
    final old = _streams[idx];
    // Always trust the server for products now that /streams returns
    // them inline. Preserving `old.products` when fresh was empty used
    // to mask host edits — the buyer card stuck on the old list until
    // they re-entered the viewer. Comments + isLiked + isFollowing stay
    // local because they're not in the list payload yet.
    return fresh.copyWith(
      vouchers: fresh.vouchers.isEmpty ? old.vouchers : fresh.vouchers,
      comments: old.comments,
      isLiked: old.isLiked,
      isFollowing: old.isFollowing,
    );
  }

  /// Enrich isFollowing cho từng stream dựa vào shopId hoặc sellerId.
  ///
  /// If the user isn't signed in there's nothing to enrich; bail so we
  /// don't blow away any client-side optimistic state. If they ARE signed
  /// in we trust the server set even when it's empty — that's the case
  /// where the user just unfollowed everyone and the pill must flip back
  /// to "+ Theo dõi".
  List<LiveStream> _enrichFollowStatus(List<LiveStream> streams, Set<String> followedShopIds) {
    if (!AuthService.instance.isSignedIn) return streams;
    return streams.map((s) {
      final followed = (s.shopId != null && followedShopIds.contains(s.shopId)) ||
          followedShopIds.contains(s.sellerId);
      return s.copyWith(isFollowing: followed);
    }).toList();
  }

  // ─── Row mappers ──────────────────────────────────────────────────────────

  /// Maps a `session` object from the Go backend to a [LiveStream] view-model.
  ///
  /// The Go backend returns a flat session row (no JOIN to profiles/products
  /// yet). Products are fetched separately via [LiveRepository.fetchSessionProducts].
  LiveStream _rowToLiveStream(Map<String, dynamic> row) {
    final products = (row['products'] as List? ?? row['live_session_products'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(_rowToLiveProduct)
        .toList();

    final category = (row['category'] ?? '') as String;
    final startedAtStr = row['started_at'] as String?;

    final rawPreviewHls = row['playback_hls'] as String?;
    return LiveStream(
      id:              row['id'] as String,
      streamKey:       row['stream_key'] as String?,
      sellerId:        row['seller_id'] as String,
      shopId:          row['shop_id'] as String?,
      // Preview HLS URL injected by /streams so list cards can auto-play
      // muted previews. The backend returns a path-only URL routed
      // through the Tropia HLS proxy (no stream_key in the path), so
      // resolve it to an absolute URL before handing it to video_player.
      streamUrl:       rawPreviewHls == null || rawPreviewHls.isEmpty
                           ? null
                           : AppConfig.resolveBackendUrl(rawPreviewHls),
      // Prefer shop_name over the seller's personal profile name — viewers
      // see the business identity ("Shop của A"), not the owner's full name
      // ("Nguyễn Văn A"). Falls back to seller_name only when the seller
      // hasn't set up a shop yet.
      sellerName:      (row['shop_name'] ?? row['seller_name'] ?? 'Người bán') as String,
      sellerAvatarUrl: (row['shop_logo_url'] ?? row['seller_avatar'] ?? row['avatar_url'] ?? AppUrls.placeholderAvatar) as String,
      isVerified:      false,
      title:           row['title'] as String,
      description:     (row['description'] as String?) ?? '$category – Live shopping',
      thumbnailUrl:    (row['cover_image_url'] as String?) ?? AppUrls.placeholderBanner,
      status:          row['status'] == 'live' ? StreamStatus.live : StreamStatus.ended,
      viewerCount:     (row['viewer_count'] as num? ?? 0).toInt(),
      likeCount:       (row['like_count'] as num? ?? 0).toInt(),
      isLiked:         false,
      isFollowing:     false,
      category:        category,
      gradientColors:  const ['#2E7D32', '#1B5E20'],
      startedAt:       startedAtStr != null ? DateTime.parse(startedAtStr) : DateTime.now(),
      reward: const LiveReward(
        attendanceCoins: 50, watchCoins: 3, watchSeconds: 0,
        totalEarnedCoins: 0, hasAttended: false, nextRewardCoins: 100,
      ),
      vouchers: const [],
      products: products,
      comments: const [],
      // Backend stores a single pinned product (Shopee Live "GẶP LÊN").
      // The model historically holds a list to allow future multi-pin —
      // wrap the scalar into a 1-element list so the rest of the code
      // path (`pinnedProductIds.contains(...)`) keeps working.
      pinnedProductIds: row['pinned_product_id'] is String
          ? [row['pinned_product_id'] as String]
          : const [],
    );
  }

  LiveProduct _rowToLiveProduct(Map<String, dynamic> row) {
    return LiveProduct(
      id:              row['id'] as String,
      productId:       row['product_id'] as String?,
      name:            row['product_name'] as String,
      imageUrl:        (row['image_url'] ?? AppUrls.placeholderProduct) as String,
      originalPrice:   (row['original_price'] as num).toDouble(),
      salePrice:       (row['sale_price'] as num).toDouble(),
      discountPercent: (row['discount_pct'] as num? ?? 0).toInt(),
      stockLeft:       (row['stock_left'] as num? ?? 0).toInt(),
      soldCount:       (row['sold_count'] as num? ?? 0).toInt(),
      unit:            (row['unit'] ?? 'cái') as String,
      category:        (row['category'] ?? '') as String,
    );
  }

  LiveComment _rowToComment(Map<String, dynamic> row) {
    final message  = (row['message'] ?? '') as String;
    final username = (row['username'] ?? row['user_name'] ?? 'Người dùng') as String;
    final isHost   = (row['is_host'] as bool?) == true
        || username == 'Trợ lý AI'
        || message.startsWith('🤖')
        || message.startsWith('🎫 Coupon:');
    return LiveComment(
      id:        (row['id'] ?? '') as String,
      userId:    (row['user_id'] ?? 'anon') as String,
      username:  username,
      message:   message,
      timestamp: row['created_at'] != null
          ? DateTime.parse(row['created_at'] as String)
          : DateTime.now(),
      avatarUrl: (row['avatar_url'] ?? row['user_avatar']) as String?,
      isHost:    isHost,
    );
  }

  LiveVoucher _rowToVoucher(Map<String, dynamic> row) {
    // Backend returns commerce.Coupon JSON:
    //   id, code, discount_type ('percent'|'fixed'), discount_value,
    //   min_order_value, max_uses, expires_at, session_id
    final isPercent = (row['discount_type'] as String?) == 'percent';
    final value = (row['discount_value'] as num? ?? 0).toDouble();
    final minOrder = (row['min_order_value'] as num? ?? 0).toDouble();
    final desc = isPercent
        ? 'Giảm ${value.toInt()}% cho đơn từ ${minOrder.toInt()}đ'
        : 'Giảm ${value.toInt()}đ cho đơn từ ${minOrder.toInt()}đ';
    return LiveVoucher(
      id:           (row['id'] ?? '') as String,
      code:         (row['code'] ?? '') as String,
      description:  desc,
      discountValue: value,
      isPercentage: isPercent,
      minOrderValue: minOrder,
      expiresAt:    row['expires_at'] != null
          ? DateTime.parse(row['expires_at'] as String)
          : DateTime.now().add(const Duration(days: 7)),
    );
  }

  // ─── Tab ──────────────────────────────────────────────────────────────────

  void setActiveTab(LiveTab tab) {
    if (_activeTab == tab) return;
    _activeTab = tab;
    notifyListeners();
  }

  // ─── Open/close stream (buyer) ────────────────────────────────────────────

  Future<void> openStream(String streamId) async {
    try {
      // If the session isn't cached yet (typical for the host who just
      // created a brand-new stream), fetch the row from the backend and
      // insert it into _streams so the rest of this method works the
      // same for host + viewer.
      int idx = _streams.indexWhere((s) => s.id == streamId);
      if (idx == -1) {
        try {
          final all = await LiveRepository.instance.fetchLiveSessions();
          final fresh = all.firstWhere(
            (r) => r['id'] == streamId,
            orElse: () => <String, dynamic>{},
          );
          if (fresh.isNotEmpty) {
            _streams = [..._streams, _rowToLiveStream(fresh)];
            idx = _streams.length - 1;
          }
        } catch (_) {}
      }
      if (idx == -1) {
        AppLogger.logError(_tag, 'openStream: session $streamId not found', null, null);
        return;
      }
      _currentStream = _streams[idx];
      AppLogger.logUserEvent(action: 'stream_opened', context: _tag,
          metadata: {'streamId': streamId});

      // Clear chat cũ trước khi load session mới
      _streams[idx] = _streams[idx].copyWith(comments: []);

      // Load chat + product list + resolve shopId + follow status in parallel.
      // /streams endpoint omits products (separate query), so fetch them
      // explicitly here — otherwise stream.products is always empty and
      // the viewer sees no product cards.
      String resolvedShopId = _streams[idx].shopId ?? '';
      final chatFuture = LiveRepository.instance.fetchRecentChats(streamId);
      final productsFuture = LiveRepository.instance.fetchSessionProducts(streamId);
      final couponsFuture = LiveRepository.instance.fetchLiveCoupons(streamId);

      // Nếu chưa có shopId, resolve từ sellerId
      if (resolvedShopId.isEmpty) {
        try {
          final shopData = await ShopRepository.instance.getBySlug(_streams[idx].sellerId);
          resolvedShopId = shopData.id;
          _streams[idx] = _streams[idx].copyWith(shopId: resolvedShopId);
        } catch (_) {
          // Seller chưa có shop → không check follow
        }
      }

      final chatRows = await chatFuture;
      final comments = chatRows.map(_rowToComment).toList();
      final productRows = await productsFuture;
      final products = productRows.map(_rowToLiveProduct).toList();
      final couponRows = await couponsFuture;
      final vouchers = couponRows.map(_rowToVoucher).toList();

      bool isFollowingShop = false;
      if (resolvedShopId.isNotEmpty) {
        isFollowingShop = await ShopRepository.instance.isFollowing(resolvedShopId);
      }

      _streams[idx] = _streams[idx].copyWith(
        comments: comments,
        products: products,
        vouchers: vouchers,
        isFollowing: isFollowingShop,
      );
      _currentStream = _streams[idx];

      // Order matters here:
      //   1. Open the WS first so we're subscribed to the session hub
      //      BEFORE the join triggers a stats push. Backend fires
      //      `publishStatsEvent` from a goroutine right after the join
      //      row is inserted; if we subscribed after the POST returned,
      //      that first event would race past us and viewer_count
      //      would stay at 0 on this client (the host's overlay still
      //      ticks up because they were already subscribed).
      //   2. Then POST /join so our row lands in live_viewers.
      //   3. Then fetch /stats once to cover the case where the push
      //      did slip past anyway (e.g. WS handshake still in flight).
      _startPolling(streamId);
      await LiveRepository.instance.joinAsViewer(streamId);
      _refreshStatsOnce(streamId);

      startSuggestionRefresh(streamId);
      // Show the first available voucher as a floating banner so viewer
      // can save it on entry (Shopee Live style). Cleared on dismiss/save.
      final vs = _streams[idx].vouchers;
      _floatingVoucherId = vs.isNotEmpty ? vs.first.id : null;
      notifyListeners();
    } catch (e, st) {
      AppLogger.logError(_tag, 'openStream failed', e, st);
    }
  }

  void closeStream() {
    final sid = _currentStream?.id;
    if (sid != null) {
      LiveRepository.instance.leaveAsViewer(sid);
    }
    _stopPolling();
    stopSuggestionRefresh();
    _currentStream = null;
    _activeProductPopupId = null;
    _activeVoucherPopupId = null;
    _floatingVoucherId = null;
    _floatingVoucherId = null;
    _liveCart.clear();
    _liveSessionCartItemIds.clear();
    // closeStream() is called from LiveStreamScreen.dispose(), which means
    // the widget tree is currently locked — notifyListeners() during that
    // phase throws "setState called when widget tree was locked". Defer to
    // a microtask so other listeners (LiveTabScreen, MainScreen badge) get
    // notified after the dispose pass completes.
    scheduleMicrotask(notifyListeners);
  }

  String get _localUserId => AuthService.instance.currentUserId;

  // ─── Realtime channel (replaces chat + stats polling) ─────────────────────

  /// Open the WS for this session + load initial chat history once. The
  /// WS only pushes deltas (new chat / stats updates); the initial 50
  /// messages need a one-shot REST fetch so the viewer doesn't see an
  /// empty chat box until the first new message arrives.
  void _startPolling(String sessionId) {
    _stopPolling();
    _pollingSessionId = sessionId;

    // 1. One-shot REST backfill of recent chat so we don't show empty.
    LiveRepository.instance.fetchRecentChats(sessionId).then((chats) {
      if (_pollingSessionId != sessionId) return;
      final fetched = chats.map(_rowToComment).toList();
      final idx = _streams.indexWhere((s) => s.id == sessionId);
      if (idx == -1) return;
      _streams[idx] = _streams[idx].copyWith(
        comments: fetched.length > 50
            ? fetched.sublist(fetched.length - 50)
            : fetched,
      );
      if (_currentStream?.id == sessionId) _currentStream = _streams[idx];
      notifyListeners();
    }).catchError((_) {/* swallow — WS still works */});

    // 2. WS for live push.
    final sock = LiveSocket(sessionId);
    _socket = sock;
    sock.events.listen((ev) {
      if (_pollingSessionId != sessionId) return;
      switch (ev.type) {
        case 'chat':
          _onChatEvent(sessionId, ev.raw);
          break;
        case 'stats':
          _onStatsEvent(sessionId, ev.raw);
          break;
        case 'coupon_announce':
          _onCouponAnnounce(sessionId, ev.raw);
          break;
      }
    });
    sock.connect();
  }

  void _onChatEvent(String sessionId, Map<String, dynamic> raw) {
    final msg = raw['message'] as Map<String, dynamic>?;
    if (msg == null) return;
    final c = _rowToComment(msg);
    final idx = _streams.indexWhere((s) => s.id == sessionId);
    if (idx == -1) return;
    final existing = _streams[idx].comments;
    // Dedupe by id (server confirms an optimistic insert) + by
    // (userId|message) so the optimistic copy doesn't duplicate the
    // pushed real copy.
    final kept = existing.where((x) {
      if (x.id == c.id) return false;
      if (x.id.startsWith('opt_') && x.userId == c.userId && x.message == c.message) {
        return false;
      }
      return true;
    }).toList();
    final merged = [...kept, c]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final trimmed = merged.length > 50 ? merged.sublist(merged.length - 50) : merged;
    // Detect coupon broadcast trigger (same pattern as old polling).
    if (onCouponBroadcasted != null && c.message.startsWith('🎫 Coupon:')) {
      final match = RegExp(r'🎫 Coupon:\s*([A-Z0-9_-]+)').firstMatch(c.message);
      if (match != null) onCouponBroadcasted?.call(match.group(1)!);
    }
    _streams[idx] = _streams[idx].copyWith(comments: trimmed);
    if (_currentStream?.id == sessionId) _currentStream = _streams[idx];
    notifyListeners();
  }

  void _onStatsEvent(String sessionId, Map<String, dynamic> raw) {
    if (raw['status'] == 'ended') {
      _stopPolling();
      onSessionEnded?.call();
      onSessionEnded = null;
      return;
    }
    final pinId = raw['pinned_product_id'];
    _updateStream(sessionId, (s) => s.copyWith(
      viewerCount: (raw['viewer_count'] as num? ?? s.viewerCount).toInt(),
      likeCount:   (raw['like_count']   as num? ?? s.likeCount).toInt(),
      // Stats event carries the current pin so every viewer's overlay
      // reflects "GẶP LÊN" within ~one round-trip of the host tapping it.
      // null is a real value here (= unpinned), so we always overwrite
      // — using `??` would let the old pin linger after an unpin.
      pinnedProductIds: pinId is String ? [pinId] : const [],
    ));
  }

  /// Host posted (or re-announced) a coupon mid-stream. We splice the
  /// fresh voucher into stream.vouchers + set floatingVoucherId so the
  /// Shopee-style banner pops up over the video for ~30s. If the
  /// coupon was already in the list (re-announce), we just re-trigger
  /// the banner without duplicating.
  void _onCouponAnnounce(String sessionId, Map<String, dynamic> raw) {
    final coupon = raw['coupon'] as Map<String, dynamic>?;
    if (coupon == null) return;
    final id = coupon['id'] as String?;
    if (id == null) return;
    final voucher = LiveVoucher(
      id: id,
      code: (coupon['code'] ?? '') as String,
      // Build a human-readable description from value + min so the
      // banner subtitle says "Đơn tối thiểu 80K đ" without a separate
      // backend field. Override here if the API ever adds one.
      description: _buildCouponDescription(coupon),
      discountValue: (coupon['discount_value'] as num? ?? 0).toDouble(),
      isPercentage: (coupon['discount_type'] as String?) == 'percent',
      minOrderValue: (coupon['min_order_value'] as num? ?? 0).toDouble(),
      expiresAt: DateTime.tryParse(coupon['expires_at'] as String? ?? '')
          ?? DateTime.now().add(const Duration(days: 1)),
    );
    _updateStream(sessionId, (s) {
      final existing = s.vouchers.where((v) => v.id != id).toList();
      return s.copyWith(vouchers: [voucher, ...existing]);
    });
    _floatingVoucherId = id;
    notifyListeners();
  }

  String _buildCouponDescription(Map<String, dynamic> c) {
    final minOrder = (c['min_order_value'] as num? ?? 0).toDouble();
    if (minOrder <= 0) return 'Áp dụng mọi đơn hàng';
    final fmt = minOrder >= 1000000
        ? '${(minOrder / 1000000).toStringAsFixed(1)}tr đ'
        : '${(minOrder / 1000).toInt()}K đ';
    return 'Đơn tối thiểu $fmt';
  }

  void _stopPolling() {
    _socket?.close();
    _socket = null;
    _pollingSessionId = null;
  }

  /// One-shot REST stats fetch used right after openStream(). Closes the
  /// gap when the backend's stats push (fired right after /join) races
  /// past our WS subscription before it's fully attached — without this
  /// the viewer's own count stays at 0 until the NEXT mutate event
  /// (another like, another join). Fire-and-forget; errors are silent
  /// because the WS will eventually deliver an authoritative number.
  Future<void> _refreshStatsOnce(String sessionId) async {
    try {
      final stats = await LiveRepository.instance.fetchSessionStats(sessionId);
      if (_pollingSessionId != sessionId) return;
      _onStatsEvent(sessionId, stats);
    } catch (_) {/* WS will catch up */}
  }

  // ─── Host (seller) ────────────────────────────────────────────────────────

  Future<String> publishHostStream({
    required String title,
    required String category,
    required List<LiveProduct> products,
    String? thumbnailUrl,
    List<Map<String, dynamic>> coupons = const [],
  }) async {
    final authUser = AuthService.instance.currentUser;
    final sellerId   = authUser?.id ?? '';
    final sellerName = authUser?.name ?? 'Seller';

    final result = await LiveRepository.instance.startLive(
      title:    title,
      category: category,
      products: products,
      coupons:  coupons,
    );

    final session      = result['session'] as Map<String, dynamic>;
    final sessionId    = session['id'] as String;
    final streamKey    = (session['stream_key'] as String?) ?? '';

    _hostSessionId   = sessionId;
    _hostChannelName = streamKey;

    // Add stream to top of list so buyer sees it immediately
    final newStream = LiveStream(
      id:              sessionId,
      sellerId:        sellerId,
      sellerName:      sellerName,
      sellerAvatarUrl: authUser?.avatarUrl ?? AppUrls.placeholderAvatar,
      isVerified:      false,
      title:           title,
      description:     '$category – đang phát sóng',
      thumbnailUrl:    thumbnailUrl ?? AppUrls.placeholderBanner,
      status:          StreamStatus.live,
      viewerCount:     0,
      likeCount:       0,
      isLiked:         false,
      isFollowing:     false,
      category:        category,
      gradientColors:  ['#2E7D32', '#1B5E20'],
      startedAt:       DateTime.now(),
      reward: const LiveReward(
        attendanceCoins: 50, watchCoins: 3, watchSeconds: 0,
        totalEarnedCoins: 0, hasAttended: false, nextRewardCoins: 100,
      ),
      vouchers: [],
      products: products,
      comments: [],
    );

    _streams.insert(0, newStream);

    AppLogger.logInfo(_tag, 'Published: $sessionId / streamKey: $streamKey');
    notifyListeners();
    return streamKey;
  }

  Future<void> unpublishHostStream() async {
    if (_hostSessionId == null) return;
    try {
      await LiveRepository.instance.endLive(_hostSessionId!);
    } catch (e) {
      AppLogger.logError(_tag, 'endLive failed', e, null);
    }
    _streams.removeWhere((s) => s.id == _hostSessionId);
    _hostSessionId   = null;
    _hostChannelName = null;
    notifyListeners();
  }

  // ─── Chat ─────────────────────────────────────────────────────────────────

  Future<void> sendComment(String streamId, String message, {String? username}) async {
    if (message.trim().isEmpty) return;

    final authUser  = AuthService.instance.currentUser;
    final senderName = username ?? authUser?.name ?? 'Bạn';
    final isBot = username != null;

    // Optimistic: show immediately
    _addCommentToStream(streamId, LiveComment(
      id:            'opt_${DateTime.now().millisecondsSinceEpoch}',
      userId:        isBot ? 'bot' : _localUserId,
      username:      senderName,
      message:       message.trim(),
      timestamp:     DateTime.now(),
      isCurrentUser: !isBot,
      isHost:        isBot, // bot messages styled như host (gold)
    ));

    // Bot reply chỉ hiện local, không gửi lên server
    if (!isBot) {
      try {
        await LiveRepository.instance.sendChat(
          sessionId: streamId,
          message:   message.trim(),
        );
      } catch (e) {
        AppLogger.logError(_tag, 'sendChat failed', e, null);
      }

      AppLogger.logUserEvent(action: 'comment_sent', context: _tag,
          metadata: {'streamId': streamId});

      final command = ChatCommandParser.parse(message.trim());
      if (command != null) await _handleChatCommand(streamId, command);
    }
  }

  // ─── Orders ───────────────────────────────────────────────────────────────

  Future<bool> placeOrder({
    required String streamId,
    required String productId,
    required int quantity,
  }) async {
    try {
      // Go backend's POST /api/orders takes live_product_id, not session_id+product_id.
      await LiveRepository.instance.placeOrder(
        liveProductId: productId,
        quantity:      quantity,
      );
      _activeProductPopupId = null;
      notifyListeners();
      return true;
    } catch (e) {
      AppLogger.logError(_tag, 'placeOrder failed', e, null);
      return false;
    }
  }

  // ─── Like / Follow ────────────────────────────────────────────────────────

  void toggleLike(String streamId) {
    _updateStream(streamId, (s) {
      // Optimistic update
      final wasLiked = s.isLiked;
      if (!wasLiked) {
        // Chỉ like, không unlike (UX giống TikTok/Shopee Live)
        LiveRepository.instance.likeSession(streamId);
      }
      return s.copyWith(
        isLiked:   !wasLiked,
        likeCount: wasLiked ? s.likeCount - 1 : s.likeCount + 1,
      );
    });
  }

  Future<void> toggleFollow(String streamId) async {
    final stream = _streams.firstWhere(
      (s) => s.id == streamId,
      orElse: () => _currentStream!,
    );
    final wasFollowing = stream.isFollowing;
    // Optimistic update
    _updateStream(streamId, (s) => s.copyWith(isFollowing: !wasFollowing));
    try {
      // shopId phải là shops.id (không phải seller_id/profile UUID)
      // Nếu chưa có shopId, resolve từ seller_id qua API
      String shopId = stream.shopId ?? '';
      if (shopId.isEmpty) {
        try {
          // getBySlug hỗ trợ UUID → backend tự fallback sang seller_id lookup
          final shopData = await ShopRepository.instance.getBySlug(stream.sellerId);
          shopId = shopData.id;
          // Lưu shopId vào stream để không cần resolve lại
          _updateStream(streamId, (s) => s.copyWith(shopId: shopId));
        } catch (_) {
          // Không có shop → revert optimistic và dừng
          _updateStream(streamId, (s) => s.copyWith(isFollowing: wasFollowing));
          AppLogger.logError(_tag, 'toggleFollow: shop not found for sellerId=${stream.sellerId}', null, null);
          return;
        }
      }

      if (wasFollowing) {
        await ShopRepository.instance.unfollow(shopId);
      } else {
        await ShopRepository.instance.follow(shopId);
        // fire-and-forget: không await để tránh race condition khi host end live ngay sau
        LiveRepository.instance.trackFollow(streamId);
      }
    } catch (e) {
      _updateStream(streamId, (s) => s.copyWith(isFollowing: wasFollowing));
      AppLogger.logError(_tag, 'toggleFollow failed', e, null);
    }
  }

  // ─── Product popup ────────────────────────────────────────────────────────

  void showProductPopup(String streamId, String productId) {
    _activeProductPopupId = productId;
    notifyListeners();
  }

  void hideProductPopup() {
    _activeProductPopupId = null;
    notifyListeners();
  }

  void showVoucherPopup(String streamId, String voucherId) {
    _activeVoucherPopupId = voucherId;
    notifyListeners();
  }

  void hideVoucherPopup() {
    _activeVoucherPopupId = null;
    notifyListeners();
  }

  void saveVoucher(String streamId, String voucherId) {
    _updateStream(streamId, (s) {
      final updated = s.vouchers.map((v) =>
          v.id == voucherId ? v.copyWith(isSaved: true) : v).toList();
      return s.copyWith(vouchers: updated);
    });
    _activeVoucherPopupId = null;
    notifyListeners();
  }

  void dismissFloatingVoucher() {
    _floatingVoucherId = null;
    notifyListeners();
  }

  // ─── Cart ─────────────────────────────────────────────────────────────────

  // skuId == variantId trong Supabase product_variants. Khi popup không
  // có skuId (sản phẩm không có biến thể), vẫn route qua addSkuToCart để
  // hit `/api/cart/items/from-live` — trước đây nhánh này chỉ tăng local
  // counter nên item không bao giờ vào giỏ thật. Fire-and-forget vì popup
  // đã đóng trước khi response về.
  void addToCart(String streamId, String productId) {
    unawaited(addSkuToCart(streamId, productId, null, 1));
  }

  Future<void> addSkuToCart(String streamId, String productId, String? skuId, int qty) async {
    // Track cart add luôn, kể cả khi API fail — đếm intent của viewer
    LiveRepository.instance.trackCartAdd(streamId);
    try {
      final item = skuId != null
          ? await CartRepository.instance.addItem(variantId: skuId, quantity: qty)
          : await CartRepository.instance.addItemFromLive(
              liveProductId: productId,
              sessionId:     streamId,
              quantity:      qty,
            );
      // Remember cart_items.id so the floating mini-cart can filter
      // CartProvider.items down to just things added during this live.
      _liveSessionCartItemIds.add(item.id);
      // Push into the shared cart so the bottom-nav badge updates right away,
      // without waiting for the user to open the cart tab (which triggers load()).
      _cartProvider?.ingestItem(item);
    } catch (e) {
      AppLogger.logError(_tag, 'addSkuToCart failed', e, null);
    }
    final key = skuId != null ? '${productId}__$skuId' : productId;
    _liveCart[key] = (_liveCart[key] ?? 0) + qty;
    _activeProductPopupId = null;
    notifyListeners();
  }

  void buyNow(String streamId, String productId) {
    placeOrder(streamId: streamId, productId: productId, quantity: 1);
  }

  void buySkuNow(String streamId, String productId, String skuId) {
    placeOrder(streamId: streamId, productId: productId, quantity: 1);
  }

  void claimAttendanceReward(String streamId) {
    _updateStream(streamId, (s) {
      final r = s.reward;
      if (r.hasAttended) return s;
      return s.copyWith(reward: r.copyWith(
        hasAttended: true,
        totalEarnedCoins: r.totalEarnedCoins + r.attendanceCoins,
      ));
    });
  }

  void toggleAutoOrder(String streamId, String productId) {}
  void placeAutoOrder(String streamId, String productId) {}
  void shareStream(String streamId) {}

  // ─── AI Suggestions ───────────────────────────────────────────────────────

  Timer? _suggestionTimer;

  Future<void> loadAiSuggestions(String streamId) async {
    final idx = _streams.indexWhere((s) => s.id == streamId);
    if (idx == -1 || _streams[idx].products.isEmpty) return;

    final stream = _streams[idx];
    // Ưu tiên: sản phẩm đang ghim (nếu có) → fallback: tất cả sản phẩm của session
    final pinnedProducts = stream.pinnedProductIds.isNotEmpty
        ? stream.products.where((p) => stream.pinnedProductIds.contains(p.id)).toList()
        : stream.products.take(3).toList();

    final primaryProduct = pinnedProducts.first;
    // Gửi tên tất cả sản phẩm để AI generate câu hỏi đa dạng
    final allNames = pinnedProducts.map((p) => p.name).join(', ');

    _isSuggestionsLoading = true;
    notifyListeners();

    final recent = (_currentStream?.comments ?? [])
        .reversed.take(10).map((c) => c.message).toList();

    _aiSuggestions = await AiSuggestionService.instance.getSuggestions(
      streamId: streamId,
      currentProductName: allNames,
      currentProductCategory: primaryProduct.category,
      recentComments: recent,
    );
    _isSuggestionsLoading = false;
    notifyListeners();
  }

  void startSuggestionRefresh(String streamId) {
    _suggestionTimer?.cancel();
    loadAiSuggestions(streamId);
    // Refresh chậm hơn (5 phút) — chủ yếu trigger qua updatePinnedProducts
    _suggestionTimer = Timer.periodic(
        const Duration(minutes: 5), (_) => loadAiSuggestions(streamId));
  }

  void stopSuggestionRefresh() {
    _suggestionTimer?.cancel();
    _aiSuggestions = [];
  }

  // ─── Pinned products ─────────────────────────────────────────────────────

  void updatePinnedProducts(String streamId, Set<String> pinnedIds) {
    _updateStream(streamId, (s) => s.copyWith(pinnedProductIds: pinnedIds.toList()));
    // Refresh AI suggestions ngay khi sản phẩm ghim thay đổi
    loadAiSuggestions(streamId);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  void _updateStream(String streamId, LiveStream Function(LiveStream) updater) {
    final idx = _streams.indexWhere((s) => s.id == streamId);
    if (idx == -1) return;
    _streams[idx] = updater(_streams[idx]);
    if (_currentStream?.id == streamId) _currentStream = _streams[idx];
    notifyListeners();
  }

  void _addCommentToStream(String streamId, LiveComment comment) {
    final idx = _streams.indexWhere((s) => s.id == streamId);
    if (idx == -1) return;
    final list   = [..._streams[idx].comments, comment];
    final trimmed = list.length > 50 ? list.sublist(list.length - 50) : list;
    _streams[idx] = _streams[idx].copyWith(comments: trimmed);
    if (_currentStream?.id == streamId) _currentStream = _streams[idx];
    notifyListeners();
  }

  // ─── Cache helpers ────────────────────────────────────────────────────────

  Future<void> _saveStreamsToCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(
        _streams.map((s) => _liveStreamToJson(s)).toList(),
      );
      await prefs.setString(_cacheKey, json);
      AppLogger.logInfo(_tag, 'Streams cached: ${_streams.length} items');
    } catch (e) {
      AppLogger.logError(_tag, 'Cache save failed', e, null);
    }
  }

  Future<void> _loadStreamsFromCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json == null) return;

      final list = jsonDecode(json) as List;
      _streams = list
          .cast<Map<String, dynamic>>()
          .map(_jsonToLiveStream)
          .toList();
      AppLogger.logInfo(_tag, 'Loaded from cache: ${_streams.length} items');
      notifyListeners();
    } catch (e) {
      AppLogger.logError(_tag, 'Cache load failed', e, null);
    }
  }

  Map<String, dynamic> _liveStreamToJson(LiveStream s) => {
    'id': s.id,
    'sellerId': s.sellerId,
    'sellerName': s.sellerName,
    'sellerAvatarUrl': s.sellerAvatarUrl,
    'isVerified': s.isVerified,
    'title': s.title,
    'description': s.description,
    'thumbnailUrl': s.thumbnailUrl,
    'status': s.status.name,
    'viewerCount': s.viewerCount,
    'likeCount': s.likeCount,
    'isLiked': s.isLiked,
    'isFollowing': s.isFollowing,
    'category': s.category,
    'gradientColors': s.gradientColors,
    'startedAt': s.startedAt.toIso8601String(),
  };

  LiveStream _jsonToLiveStream(Map<String, dynamic> json) => LiveStream(
    id: json['id'] as String,
    sellerId: json['sellerId'] as String,
    sellerName: json['sellerName'] as String,
    sellerAvatarUrl: json['sellerAvatarUrl'] as String,
    isVerified: (json['isVerified'] as bool?) ?? false,
    title: json['title'] as String,
    description: json['description'] as String,
    thumbnailUrl: json['thumbnailUrl'] as String,
    status: json['status'] == 'live' ? StreamStatus.live : StreamStatus.ended,
    viewerCount: (json['viewerCount'] as num).toInt(),
    likeCount: (json['likeCount'] as num).toInt(),
    isLiked: (json['isLiked'] as bool?) ?? false,
    isFollowing: (json['isFollowing'] as bool?) ?? false,
    category: json['category'] as String,
    gradientColors: (json['gradientColors'] as List).cast<String>(),
    startedAt: DateTime.parse(json['startedAt'] as String),
    reward: const LiveReward(
      attendanceCoins: 50, watchCoins: 3, watchSeconds: 0,
      totalEarnedCoins: 0, hasAttended: false, nextRewardCoins: 100,
    ),
    vouchers: [],
    products: [],
    comments: [],
  );

  // ─── Chat command handler ─────────────────────────────────────────────────

  Future<void> _handleChatCommand(String streamId, ChatCommand command) async {
    final stream = _streams.firstWhere(
        (s) => s.id == streamId, orElse: () => _streams.first);
    String botReply;

    switch (command) {
      case BuyCommand(:final productSlot, :final quantity):
        if (productSlot <= 0 || productSlot > stream.products.length) {
          botReply = '❌ Không tìm thấy sản phẩm số $productSlot.'; break;
        }
        final p  = stream.products[productSlot - 1];
        if (p.stockLeft <= 0) {
          botReply = '⚠️ "${p.name}" đã hết hàng!'; break;
        }
        final ok = await placeOrder(streamId: streamId, productId: p.id, quantity: quantity);
        botReply = ok
            ? '✅ Đã đặt "${p.name}" x$quantity!'
            : '❌ Đặt hàng thất bại, thử lại sau.';

      case ViewProductCommand(:final productSlot):
        if (productSlot > stream.products.length) {
          botReply = '❌ Không có sản phẩm số $productSlot.'; break;
        }
        final p = stream.products[productSlot - 1];
        botReply = '📦 #$productSlot: ${p.name}\n💰 ${p.salePrice.toInt()}đ\n📦 Còn: ${p.totalStock} ${p.unit}';

      case PriceCommand(:final productSlot):
        if (productSlot > stream.products.length) {
          botReply = '❌ Không có sản phẩm số $productSlot.'; break;
        }
        final p = stream.products[productSlot - 1];
        botReply = '💰 "${p.name}": ${p.salePrice.toInt()}đ (-${p.discountPercent}%)';

      case StockCommand(:final productSlot):
        if (productSlot > stream.products.length) {
          botReply = '❌ Không có sản phẩm số $productSlot.'; break;
        }
        final p = stream.products[productSlot - 1];
        botReply = p.totalStock <= 0
            ? '❌ Hết hàng!' : '✅ Còn ${p.totalStock} ${p.unit}';

      case VoucherListCommand():
        botReply = '🎟 Chưa có voucher trong live này.';

      case SaveVoucherCommand(:final code):
        botReply = '👆 Nhấn banner để lưu voucher [$code].';

      case CartViewCommand():
        botReply = _liveCart.isEmpty
            ? '🛒 Giỏ trống. Gõ /mua [số] để thêm.' : '🛒 ${_liveCart.length} sp. Gõ /dat để đặt.';

      case CartRemoveCommand():
        botReply = '🗑 Đã xóa khỏi giỏ.';

      case CheckoutCommand():
        if (_liveCart.isEmpty) { botReply = '🛒 Giỏ trống!'; break; }
        int ok = 0;
        for (final entry in Map.from(_liveCart).entries) {
          final pid = (entry.key as String).split('__').first;
          if (await placeOrder(streamId: streamId, productId: pid, quantity: entry.value as int)) ok++;
        }
        _liveCart.clear();
        botReply = ok > 0 ? '✅ Đặt $ok sản phẩm thành công!' : '❌ Đặt hàng thất bại.';
    }

    _addBotMessage(streamId, botReply);
  }

  void _addBotMessage(String streamId, String text) {
    _addCommentToStream(streamId, LiveComment(
      id:           'bot_${DateTime.now().millisecondsSinceEpoch}',
      userId:       'bot',
      username:     '🤖 Trợ lý Live',
      message:      text,
      timestamp:    DateTime.now(),
      isBotMessage: true,
    ));
  }
}
