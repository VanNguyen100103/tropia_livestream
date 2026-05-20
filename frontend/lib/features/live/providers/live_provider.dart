// =============================================================================
// live_provider.dart – REAL backend: Supabase Realtime + Node.js API
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tropia/core/constants/app_constants.dart';
import 'package:tropia/core/services/auth_service.dart';
import 'package:tropia/core/utils/logger.dart';
import 'package:tropia/features/cart/data/cart_repository.dart';
import 'package:tropia/features/shop/data/shop_repository.dart';
import 'package:tropia/features/live/data/live_repository.dart';
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
  List<String> _aiSuggestions = [];
  bool _isSuggestionsLoading = false;

  // ─── Polling timers ───────────────────────────────────────────────────────
  Timer? _chatTimer;
  Timer? _statsTimer;
  String? _pollingSessionId;

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
      case LiveTab.forYou:
        final live  = _streams.where((s) => s.status == StreamStatus.live).toList();
        final ended = _streams.where((s) => s.status != StreamStatus.live).toList();
        return [...live, ...ended];
    }
  }

  // ─── Constructor ──────────────────────────────────────────────────────────

  LiveProvider() {
    _loadStreams();
  }

  @override
  void dispose() {
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
      await _loadStreamsFromCache();
      // Fetch streams và followed shop IDs song song
      final rowsFuture      = LiveRepository.instance.fetchLiveSessions();
      final followedFuture  = ShopRepository.instance.getFollowedShopIds();
      final rows       = await rowsFuture;
      final followedIds = await followedFuture;
      if (rows.isEmpty) {
        AppLogger.logInfo(_tag, 'API returned no streams');
        if (_streams.isEmpty) {
          _errorMessage = 'Không có buổi live nào';
        }
      } else {
        _streams = _enrichFollowStatus(rows.map(_rowToLiveStream).toList(), followedIds);
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
    try {
      final rowsFuture     = LiveRepository.instance.fetchLiveSessions();
      final followedFuture = ShopRepository.instance.getFollowedShopIds();
      final rows       = await rowsFuture;
      final followedIds = await followedFuture;
      if (rows.isNotEmpty) {
        _streams = _enrichFollowStatus(rows.map(_rowToLiveStream).toList(), followedIds);
        _errorMessage = null;
        await _saveStreamsToCache();
        AppLogger.logInfo(_tag, 'Refreshed ${_streams.length} live sessions');
      } else {
        _errorMessage = 'Không có buổi live nào';
      }
    } catch (e, st) {
      AppLogger.logError(_tag, 'Refresh failed', e, st);
      _errorMessage = 'Refresh thất bại. Vui lòng thử lại.';
    } finally {
      notifyListeners();
    }
  }

  /// Enrich isFollowing cho từng stream dựa vào shopId hoặc sellerId
  List<LiveStream> _enrichFollowStatus(List<LiveStream> streams, Set<String> followedShopIds) {
    if (followedShopIds.isEmpty) return streams;
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

    return LiveStream(
      id:              row['id'] as String,
      sellerId:        row['seller_id'] as String,
      shopId:          row['shop_id'] as String?,
      sellerName:      (row['seller_name'] ?? row['shop_name'] ?? 'Người bán') as String,
      sellerAvatarUrl: (row['seller_avatar'] ?? row['avatar_url'] ?? AppUrls.placeholderAvatar) as String,
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

  // ─── Tab ──────────────────────────────────────────────────────────────────

  void setActiveTab(LiveTab tab) {
    if (_activeTab == tab) return;
    _activeTab = tab;
    notifyListeners();
  }

  // ─── Open/close stream (buyer) ────────────────────────────────────────────

  Future<void> openStream(String streamId) async {
    try {
      final idx = _streams.indexWhere((s) => s.id == streamId);
      if (idx == -1) return;
      _currentStream = _streams[idx];
      AppLogger.logUserEvent(action: 'stream_opened', context: _tag,
          metadata: {'streamId': streamId});

      // Clear chat cũ trước khi load session mới
      _streams[idx] = _streams[idx].copyWith(comments: []);

      // Load initial chat + resolve shopId + follow status song song
      // shopId trong stream có thể là null nếu shop chưa được enrich
      // getBySlug hỗ trợ UUID → backend fallback tìm theo seller_id
      String resolvedShopId = _streams[idx].shopId ?? '';
      final chatFuture = LiveRepository.instance.fetchRecentChats(streamId);

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

      bool isFollowingShop = false;
      if (resolvedShopId.isNotEmpty) {
        isFollowingShop = await ShopRepository.instance.isFollowing(resolvedShopId);
      }

      _streams[idx] = _streams[idx].copyWith(
        comments: comments,
        isFollowing: isFollowingShop,
      );
      _currentStream = _streams[idx];

      // Viewer presence
      await LiveRepository.instance.joinAsViewer(streamId);

      // Start polling
      _startPolling(streamId);

      startSuggestionRefresh(streamId);
      _floatingVoucherId = null;
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
    notifyListeners();
  }

  String get _localUserId => AuthService.instance.currentUserId;

  // ─── Polling (thay Supabase Realtime) ────────────────────────────────────

  void _startPolling(String sessionId) {
    _stopPolling();
    _pollingSessionId = sessionId;

    // Chat: poll mỗi 3 giây
    _chatTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_pollingSessionId != sessionId) return;
      try {
        final chats = await LiveRepository.instance.fetchRecentChats(sessionId);
        final fetched = chats.map(_rowToComment).toList();
        final idx = _streams.indexWhere((s) => s.id == sessionId);
        if (idx == -1) return;

        // Merge: append tin mới từ server, xóa optimistic đã được server confirm
        final existing = _streams[idx].comments;
        final fetchedIds = fetched.map((c) => c.id).toSet();
        final fetchedKeys = fetched.map((c) => '${c.userId}|${c.message}').toSet();

        // Giữ lại: tin real (có trong fetched) + tin optimistic chưa được confirm + tin bot local
        final kept = existing.where((c) {
          if (fetchedIds.contains(c.id)) return true; // đã sync
          if (c.id.startsWith('opt_') && fetchedKeys.contains('${c.userId}|${c.message}')) return false; // optimistic đã confirm → bỏ
          return true; // giữ lại (bot local, optimistic chưa confirm)
        }).toList();

        final keptIds = kept.map((c) => c.id).toSet();
        final newOnes = fetched.where((c) => !keptIds.contains(c.id)).toList();

        // Detect coupon broadcast từ host → trigger popup trên viewer
        if (onCouponBroadcasted != null) {
          for (final c in newOnes) {
            if (c.message.startsWith('🎫 Coupon:')) {
              final match = RegExp(r'🎫 Coupon:\s*([A-Z0-9_-]+)').firstMatch(c.message);
              if (match != null) onCouponBroadcasted?.call(match.group(1)!);
            }
          }
        }

        if (newOnes.isEmpty && kept.length == existing.length) return;

        final merged = [...kept, ...newOnes]
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        final trimmed = merged.length > 50 ? merged.sublist(merged.length - 50) : merged;
        _streams[idx] = _streams[idx].copyWith(comments: trimmed);
        if (_currentStream?.id == sessionId) _currentStream = _streams[idx];
        notifyListeners();
      } catch (_) {}
    });

    // Stats: poll mỗi 5 giây
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_pollingSessionId != sessionId) return;
      try {
        final stats = await LiveRepository.instance.fetchSessionStats(sessionId);

        // Host đã kết thúc live → thông báo cho viewer
        if (stats['status'] == 'ended') {
          _stopPolling();
          onSessionEnded?.call();
          onSessionEnded = null;
          return;
        }

        _updateStream(sessionId, (s) => s.copyWith(
          viewerCount: (stats['viewer_count'] as num? ?? s.viewerCount).toInt(),
          likeCount:   (stats['like_count']   as num? ?? s.likeCount).toInt(),
        ));
      } catch (_) {}
    });
  }

  void _stopPolling() {
    _chatTimer?.cancel();
    _statsTimer?.cancel();
    _chatTimer = _statsTimer = null;
    _pollingSessionId = null;
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
    // Go backend returns the stream key as session.agora_channel (legacy name).
    final streamKey    = (session['agora_channel'] as String?) ?? '';

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

  // skuId == variantId trong Supabase product_variants
  void addToCart(String streamId, String productId) {
    // Không có variantId cụ thể → không thể gọi API, chỉ cập nhật local count
    _liveCart[productId] = (_liveCart[productId] ?? 0) + 1;
    _activeProductPopupId = null;
    notifyListeners();
  }

  Future<void> addSkuToCart(String streamId, String productId, String? skuId, int qty) async {
    // Track cart add luôn, kể cả khi API fail — đếm intent của viewer
    LiveRepository.instance.trackCartAdd(streamId);
    try {
      if (skuId != null) {
        await CartRepository.instance.addItem(variantId: skuId, quantity: qty);
      } else {
        await CartRepository.instance.addItemFromLive(
          liveProductId: productId,
          sessionId:     streamId,
          quantity:      qty,
        );
      }
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
