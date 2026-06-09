// =============================================================================
// video_model.dart
// =============================================================================
// Model cho tính năng Video ngắn (Shopee Video / TikTok style).
//   - [VideoPost]: 1 clip trong feed "video đề xuất"
//   - [VideoComment]: 1 bình luận
//
// Khớp JSON từ Go backend (internal/video/model.go) — snake_case.
// URL trả về có thể là path-relative ("/uploads/...") nên dùng
// [AppConfig.resolveBackendUrl] để ghép host khi phát.
// =============================================================================

import 'package:tropia_mobile_app_android/live_app/core/config/app_config.dart';

/// Ghép host cho URL path-relative rồi CHỈ trả về nếu là http/https. Mọi scheme
/// khác (file:, data:, javascript:, content:...) → '' để không bao giờ đưa vào
/// video_player / image loader (defense-in-depth; backend cũng đã validate).
String _resolveHttp(String raw) {
  if (raw.isEmpty) return '';
  final u = AppConfig.resolveBackendUrl(raw);
  return (u.startsWith('http://') || u.startsWith('https://')) ? u : '';
}

String? _nullable(String s) => s.isEmpty ? null : s;

class VideoPost {
  final String id;
  final String userId;
  final String? shopId;
  final String videoUrl;

  /// Bản clip đã bake lớp overlay tĩnh (shop handle + caption + sản phẩm +
  /// voucher + watermark) do worker tạo async, dùng cho CHIA SẺ / tải ra ngoài
  /// app — nơi không có UI Flutter vẽ đè nên cần thông tin burn sẵn vào video.
  /// null khi chưa bake xong → share fallback về [videoUrl] (clip thô).
  final String? overlayUrl;
  final String? thumbnailUrl;
  final String? caption;
  final List<String> hashtags;
  final int durationSec;
  final int width;
  final int height;
  final bool allowReuse;
  final int viewCount;
  final int likeCount;
  final int commentCount;
  final int shareCount;
  final DateTime createdAt;

  // Joined display info.
  final String? userName;
  final String? userAvatar;
  final String? shopName;
  final String? shopSlug;
  final String? shopAvatar; // logo shop (shops.logo_url), null nếu video cá nhân

  /// Sản phẩm được gắn vào video (Shopee Video "Xem sản phẩm"), theo thứ tự hiển thị.
  final List<VideoProduct> products;

  /// Coupon (voucher shop) được seller gắn vào video, theo thứ tự hiển thị.
  /// Đọc trực tiếp từ bảng coupons nên luôn là trạng thái hiện tại; coupon hết
  /// hạn / tắt sẽ tự rớt khỏi danh sách.
  final List<VideoCoupon> coupons;

  // Viewer-relative flags.
  final bool liked;
  final bool following; // theo dõi CREATOR (user_follows)
  final bool shopFollowing; // theo dõi SHOP (shop_follows)
  final bool shopHasVoucher; // shop có voucher đang chạy → "Mua với Voucher"

  const VideoPost({
    required this.id,
    required this.userId,
    this.shopId,
    required this.videoUrl,
    this.overlayUrl,
    this.thumbnailUrl,
    this.caption,
    this.hashtags = const [],
    this.durationSec = 0,
    this.width = 0,
    this.height = 0,
    this.allowReuse = true,
    this.viewCount = 0,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    required this.createdAt,
    this.userName,
    this.userAvatar,
    this.shopName,
    this.shopSlug,
    this.shopAvatar,
    this.products = const [],
    this.coupons = const [],
    this.liked = false,
    this.following = false,
    this.shopFollowing = false,
    this.shopHasVoucher = false,
  });

  /// URL phát video, đã ghép host. Rỗng nếu không phải http(s) hợp lệ
  /// (chặn các scheme lạ như file:/data:/javascript: trước khi đưa vào player).
  String get playUrl => _resolveHttp(videoUrl);

  /// URL dùng khi CHIA SẺ / SAO CHÉP đường dẫn ra ngoài app: ưu tiên bản đã
  /// bake overlay (để người mở link ngoài app vẫn thấy info burn sẵn trên
  /// video), fallback về clip thô [playUrl] khi overlay chưa bake xong / lỗi.
  String get shareUrl {
    final o = _resolveHttp(overlayUrl ?? '');
    return o.isNotEmpty ? o : playUrl;
  }

  /// URL ảnh bìa (đã ghép host), null nếu không có / không hợp lệ.
  String? get thumbUrl => _nullable(_resolveHttp(thumbnailUrl ?? ''));

  /// URL avatar người đăng (creator) đã ghép host, null nếu không hợp lệ. Dùng
  /// khi mở trang creator (CreatorProfileScreen).
  String? get avatarUrl => _nullable(_resolveHttp(userAvatar ?? ''));

  /// URL logo shop (đã ghép host), null nếu video không gắn shop / không hợp lệ.
  String? get shopAvatarUrl => _nullable(_resolveHttp(shopAvatar ?? ''));

  /// Avatar hiển thị trên THẺ video: ưu tiên logo shop (khi có shop) rồi tới
  /// avatar creator — khớp với [displayName] (ưu tiên tên shop) và nút theo dõi
  /// (ưu tiên theo dõi shop), giống cách feed live hiển thị seller_avatar.
  String? get displayAvatarUrl =>
      hasShop ? (shopAvatarUrl ?? avatarUrl) : avatarUrl;

  /// Tên hiển thị (ưu tiên tên shop, rồi tên user, fallback "Người dùng").
  String get displayName => (shopName?.isNotEmpty ?? false)
      ? shopName!
      : (userName?.isNotEmpty ?? false)
      ? userName!
      : 'Người dùng';

  /// Video có gắn shop (có thể theo dõi shop). Cần cả id lẫn slug để gọi
  /// /api/shops/:slug/follow.
  bool get hasShop =>
      (shopId?.isNotEmpty ?? false) && (shopSlug?.isNotEmpty ?? false);

  /// Trạng thái theo dõi hiệu lực cho nút (+): theo SHOP nếu có shop, ngược lại
  /// fallback theo CREATOR.
  bool get isFollowed => hasShop ? shopFollowing : following;

  factory VideoPost.fromJson(Map<String, dynamic> json) {
    return VideoPost(
      id: json['id'] as String,
      userId: json['user_id'] as String? ?? '',
      shopId: json['shop_id'] as String?,
      videoUrl: json['video_url'] as String? ?? '',
      overlayUrl: json['overlay_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      caption: json['caption'] as String?,
      hashtags:
          (json['hashtags'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      durationSec: (json['duration_sec'] as num?)?.toInt() ?? 0,
      width: (json['width'] as num?)?.toInt() ?? 0,
      height: (json['height'] as num?)?.toInt() ?? 0,
      allowReuse: json['allow_reuse'] as bool? ?? true,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      commentCount: (json['comment_count'] as num?)?.toInt() ?? 0,
      shareCount: (json['share_count'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      userName: json['user_name'] as String?,
      userAvatar: json['user_avatar'] as String?,
      shopName: json['shop_name'] as String?,
      shopSlug: json['shop_slug'] as String?,
      shopAvatar: json['shop_avatar'] as String?,
      products:
          (json['products'] as List?)
              ?.whereType<Map>()
              .map((e) => VideoProduct.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      coupons:
          (json['coupons'] as List?)
              ?.whereType<Map>()
              .map((e) => VideoCoupon.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          const [],
      liked: json['liked'] as bool? ?? false,
      following: json['following'] as bool? ?? false,
      shopFollowing: json['shop_following'] as bool? ?? false,
      shopHasVoucher: json['shop_has_voucher'] as bool? ?? false,
    );
  }

  VideoPost copyWith({
    int? likeCount,
    int? commentCount,
    int? shareCount,
    int? viewCount,
    bool? liked,
    bool? following,
    bool? shopFollowing,
  }) {
    return VideoPost(
      // shopHasVoucher giữ nguyên (cờ theo shop, không đổi qua tương tác).
      id: id,
      userId: userId,
      shopId: shopId,
      videoUrl: videoUrl,
      overlayUrl: overlayUrl,
      thumbnailUrl: thumbnailUrl,
      caption: caption,
      hashtags: hashtags,
      durationSec: durationSec,
      width: width,
      height: height,
      allowReuse: allowReuse,
      viewCount: viewCount ?? this.viewCount,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      createdAt: createdAt,
      userName: userName,
      userAvatar: userAvatar,
      shopName: shopName,
      shopSlug: shopSlug,
      shopAvatar: shopAvatar,
      products: products,
      coupons: coupons,
      liked: liked ?? this.liked,
      following: following ?? this.following,
      shopFollowing: shopFollowing ?? this.shopFollowing,
      shopHasVoucher: shopHasVoucher,
    );
  }
}

/// 1 sản phẩm gắn vào video (Shopee Video "Xem sản phẩm"). Các trường hiển thị
/// được backend đọc trực tiếp từ bảng products nên luôn là giá hiện tại.
class VideoProduct {
  final String productId;
  final String name;
  final String slug;
  final String? imageUrl;
  final int basePrice;
  final int? salePrice;
  final int totalSold;
  final double rating;
  final int reviewCount;

  /// Flash sale đang chạy (Shopee "Flash Sale"): giá flash + thời điểm kết thúc
  /// để chạy countdown. null khi sản phẩm không trong đợt flash sale nào.
  final int? flashPrice;
  final DateTime? flashEndsAt;

  const VideoProduct({
    required this.productId,
    required this.name,
    required this.slug,
    this.imageUrl,
    this.basePrice = 0,
    this.salePrice,
    this.totalSold = 0,
    this.rating = 0,
    this.reviewCount = 0,
    this.flashPrice,
    this.flashEndsAt,
  });

  /// Đang trong flash sale còn hiệu lực (giá flash + thời gian kết thúc còn lại).
  bool get hasFlashSale =>
      flashPrice != null &&
      flashEndsAt != null &&
      flashEndsAt!.isAfter(DateTime.now());

  /// Giá đang bán: ưu tiên giá flash (nếu đang flash sale), rồi salePrice, rồi giá gốc.
  int get displayPrice => hasFlashSale ? flashPrice! : (salePrice ?? basePrice);

  /// Có giảm giá so với giá gốc không (tính cả flash sale).
  bool get hasDiscount => displayPrice < basePrice;

  /// % giảm (làm tròn) so với giá gốc; 0 nếu không giảm hoặc giá gốc <= 0.
  int get discountPercent => (hasDiscount && basePrice > 0)
      ? (((basePrice - displayPrice) / basePrice) * 100).round()
      : 0;

  /// URL ảnh (đã ghép host), null nếu không có / không hợp lệ.
  String? get image => _nullable(_resolveHttp(imageUrl ?? ''));

  factory VideoProduct.fromJson(Map<String, dynamic> json) {
    return VideoProduct(
      productId: json['product_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      slug: json['slug'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      basePrice: (json['base_price'] as num?)?.toInt() ?? 0,
      salePrice: (json['sale_price'] as num?)?.toInt(),
      totalSold: (json['total_sold'] as num?)?.toInt() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      flashPrice: (json['flash_price'] as num?)?.toInt(),
      flashEndsAt: json['flash_ends_at'] != null
          ? DateTime.tryParse(json['flash_ends_at'] as String)
          : null,
    );
  }
}

/// 1 coupon (voucher shop) được gắn vào video (Shopee Video "Voucher"). Các
/// trường hiển thị backend đọc trực tiếp từ bảng coupons nên luôn là hiện tại.
class VideoCoupon {
  final String couponId;
  final String code;
  final String discountType; // 'percent' | 'fixed'
  final double discountValue;
  final int minOrderValue;
  final int? maxDiscount;
  final DateTime expiresAt;

  const VideoCoupon({
    required this.couponId,
    required this.code,
    required this.discountType,
    required this.discountValue,
    this.minOrderValue = 0,
    this.maxDiscount,
    required this.expiresAt,
  });

  /// Label ngắn: "Giảm 20%" hoặc "Giảm 50K".
  String get discountLabel {
    if (discountType == 'percent') return 'Giảm ${discountValue.toInt()}%';
    final v = discountValue.toInt();
    if (v >= 1000000) {
      return 'Giảm ${(v / 1000000).toStringAsFixed(1).replaceAll('.0', '')}tr';
    }
    if (v >= 1000) return 'Giảm ${(v / 1000).toInt()}K';
    return 'Giảm $vđ';
  }

  factory VideoCoupon.fromJson(Map<String, dynamic> json) {
    return VideoCoupon(
      couponId: json['coupon_id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      discountType: json['discount_type'] as String? ?? 'fixed',
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      minOrderValue: (json['min_order_value'] as num?)?.toInt() ?? 0,
      maxDiscount: (json['max_discount'] as num?)?.toInt(),
      expiresAt:
          DateTime.tryParse(json['expires_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

/// 1 báo cáo video (dùng cho hàng đợi kiểm duyệt của admin).
class VideoReport {
  final String id;
  final String videoId;
  final String reporterId;
  final String reason;
  final String status;
  final String? action;
  final DateTime createdAt;
  final String? reporterName;
  final String? videoCaption;
  final String? videoThumbnailUrl;
  final String? videoStatus;
  final String? ownerName;

  const VideoReport({
    required this.id,
    required this.videoId,
    required this.reporterId,
    required this.reason,
    required this.status,
    this.action,
    required this.createdAt,
    this.reporterName,
    this.videoCaption,
    this.videoThumbnailUrl,
    this.videoStatus,
    this.ownerName,
  });

  String? get thumbUrl => _nullable(_resolveHttp(videoThumbnailUrl ?? ''));

  factory VideoReport.fromJson(Map<String, dynamic> json) {
    return VideoReport(
      id: json['id'] as String,
      videoId: json['video_id'] as String? ?? '',
      reporterId: json['reporter_id'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      action: json['action'] as String?,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      reporterName: json['reporter_name'] as String?,
      videoCaption: json['video_caption'] as String?,
      videoThumbnailUrl: json['video_thumbnail_url'] as String?,
      videoStatus: json['video_status'] as String?,
      ownerName: json['owner_name'] as String?,
    );
  }
}

class VideoComment {
  final String id;
  final String videoId;
  final String userId;
  final String content;
  final int likeCount;
  final DateTime createdAt;
  final String? userName;
  final String? userAvatar;

  const VideoComment({
    required this.id,
    required this.videoId,
    required this.userId,
    required this.content,
    this.likeCount = 0,
    required this.createdAt,
    this.userName,
    this.userAvatar,
  });

  String get displayName =>
      (userName?.isNotEmpty ?? false) ? userName! : 'Người dùng';

  String? get avatarUrl => _nullable(_resolveHttp(userAvatar ?? ''));

  factory VideoComment.fromJson(Map<String, dynamic> json) {
    return VideoComment(
      id: json['id'] as String,
      videoId: json['video_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      content: json['content'] as String? ?? '',
      likeCount: (json['like_count'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.now(),
      userName: json['user_name'] as String?,
      userAvatar: json['user_avatar'] as String?,
    );
  }
}

/// 1 gợi ý hashtag cho ô "#" khi soạn mô tả video — [tag] không kèm dấu '#',
/// [videoCount] là số video đang dùng hashtag, [viewCount] là tổng lượt xem của
/// chúng (để hiển thị "1,6k lượt xem" giống Shopee Video).
class HashtagSuggestion {
  final String tag;
  final int videoCount;
  final int viewCount;

  const HashtagSuggestion({
    required this.tag,
    this.videoCount = 0,
    this.viewCount = 0,
  });

  factory HashtagSuggestion.fromJson(Map<String, dynamic> json) {
    return HashtagSuggestion(
      tag: (json['tag'] as String? ?? '').trim(),
      videoCount: (json['video_count'] as num?)?.toInt() ?? 0,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
    );
  }
}
