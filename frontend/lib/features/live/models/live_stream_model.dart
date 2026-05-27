// =============================================================================
// live_stream_model.dart
// =============================================================================
// Model cho toàn bộ dữ liệu của tính năng Live & Video.
//
// Bao gồm các class:
//   - [LiveStream]: Thông tin buổi phát sóng trực tiếp
//   - [LiveProduct]: Sản phẩm được hiển thị trong buổi live
//   - [LiveComment]: Bình luận của người xem
//   - [LiveReward]: Phần thưởng / xu trong buổi live
//   - [LiveVoucher]: Voucher/coupon được phát trong live
//   - [LiveTab]: Enum cho các tab (Video / Live / Theo dõi)
//   - [StreamStatus]: Trạng thái luồng (live, ended, upcoming)
//
// THIẾT KẾ:
//   - Tất cả model dùng [final] fields + constructor có named params
//   - Có [copyWith] để dễ cập nhật trạng thái trong Provider
//   - Có [fromJson] / [toJson] sẵn sàng cho API thực tế
//   - Dùng [freezed-like] immutable pattern (không dùng freezed package để
//     tránh phức tạp cho nhân viên mới – tự implement thủ công)
// =============================================================================

/// Trạng thái của một buổi livestream.
enum StreamStatus {
  /// Đang phát sóng trực tiếp
  live,

  /// Đã kết thúc – có thể xem lại (VOD)
  ended,

  /// Sắp diễn ra
  upcoming,
}

/// Các tab trong màn hình Live & Video.
enum LiveTab {
  video,
  live,
  // Shopee-style: only streams from shops the buyer already follows. Live
  // ones first, then ended (so the user can catch a VOD they missed).
  following,
}

// ─────────────────────────────────────────────────────────────────────────────
// ProductVariantOption – một giá trị trong một trục biến thể
// ─────────────────────────────────────────────────────────────────────────────

/// Một lựa chọn cụ thể trong trục biến thể, ví dụ "Đỏ", "M", "128GB".
class ProductVariantOption {
  /// Giá trị hiển thị (ví dụ: "Đỏ", "XL", "256GB")
  final String label;

  /// Mã màu hex nếu là trục màu sắc (ví dụ: "#FF0000"). Null nếu không phải màu.
  final String? colorHex;

  /// URL ảnh swatch nếu có (thumbnail nhỏ cho màu/pattern)
  final String? swatchImageUrl;

  /// Có available không (false = đã hết, hiện gạch chéo)
  final bool isAvailable;

  const ProductVariantOption({
    required this.label,
    this.colorHex,
    this.swatchImageUrl,
    this.isAvailable = true,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'colorHex': colorHex,
    'swatchImageUrl': swatchImageUrl,
    'isAvailable': isAvailable,
  };

  factory ProductVariantOption.fromJson(Map<String, dynamic> json) =>
      ProductVariantOption(
        label: json['label'] as String,
        colorHex: json['colorHex'] as String?,
        swatchImageUrl: json['swatchImageUrl'] as String?,
        isAvailable: json['isAvailable'] as bool? ?? true,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ProductVariantAxis – một trục biến thể (ví dụ: "Màu sắc", "Size")
// ─────────────────────────────────────────────────────────────────────────────

/// Một chiều biến thể của sản phẩm.
///
/// Ví dụ:
///   ProductVariantAxis(name: 'Màu sắc', type: VariantAxisType.color,
///     options: [ProductVariantOption(label:'Đỏ', colorHex:'#E53935'), ...])
///   ProductVariantAxis(name: 'Size', type: VariantAxisType.size,
///     options: [ProductVariantOption(label:'S'), ProductVariantOption(label:'M'), ...])
class ProductVariantAxis {
  /// Tên trục (ví dụ: "Màu sắc", "Kích cỡ", "Dung lượng")
  final String name;

  /// Kiểu hiển thị UI cho trục này
  final VariantAxisType type;

  /// Danh sách các lựa chọn trong trục này
  final List<ProductVariantOption> options;

  const ProductVariantAxis({
    required this.name,
    required this.type,
    required this.options,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.name,
    'options': options.map((o) => o.toJson()).toList(),
  };

  factory ProductVariantAxis.fromJson(Map<String, dynamic> json) =>
      ProductVariantAxis(
        name: json['name'] as String,
        type: VariantAxisType.values.byName(json['type'] as String),
        options: (json['options'] as List)
            .map((o) => ProductVariantOption.fromJson(o as Map<String, dynamic>))
            .toList(),
      );
}

/// Kiểu UI cho trục biến thể.
enum VariantAxisType {
  /// Hiển thị ô màu (tròn hoặc vuông có border)
  color,

  /// Hiển thị chip chữ (S / M / L / XL)
  size,

  /// Hiển thị chip chữ thông thường (cho dung lượng, loại, ...)
  text,

  /// Hiển thị ảnh thumbnail nhỏ
  image,
}

// ─────────────────────────────────────────────────────────────────────────────
// ProductSku – một tổ hợp biến thể cụ thể với giá & tồn kho riêng
// ─────────────────────────────────────────────────────────────────────────────

/// Một SKU = tổ hợp cụ thể của các lựa chọn từ tất cả các trục.
///
/// Ví dụ: { "Màu sắc": "Đỏ", "Size": "M" } → giá 350.000đ, còn 12 cái.
///
/// KEY INSIGHT: Giá và tồn kho nằm ở SKU, KHÔNG nằm ở LiveProduct.
/// LiveProduct chỉ lưu giá hiển thị mặc định (giá thấp nhất / giá SKU đầu tiên).
class ProductSku {
  /// ID duy nhất của SKU này (dùng để giảm stock chính xác)
  final String skuId;

  /// Map từ tên trục → label được chọn.
  /// Ví dụ: {"Màu sắc": "Đỏ", "Size": "M"}
  final Map<String, String> selections;

  /// Giá gốc của SKU này (VND) – có thể khác nhau giữa các SKU
  final double originalPrice;

  /// Giá sale của SKU này trong live (VND)
  final double salePrice;

  /// Tồn kho riêng của SKU này
  final int stockLeft;

  /// URL ảnh riêng cho SKU này (ví dụ: ảnh màu đỏ khi chọn màu đỏ)
  final String? imageUrl;

  const ProductSku({
    required this.skuId,
    required this.selections,
    required this.originalPrice,
    required this.salePrice,
    required this.stockLeft,
    this.imageUrl,
  });

  /// Tạo bản sao với stock giảm
  ProductSku copyWith({
    String? skuId,
    Map<String, String>? selections,
    double? originalPrice,
    double? salePrice,
    int? stockLeft,
    String? imageUrl,
  }) => ProductSku(
    skuId: skuId ?? this.skuId,
    selections: selections ?? this.selections,
    originalPrice: originalPrice ?? this.originalPrice,
    salePrice: salePrice ?? this.salePrice,
    stockLeft: stockLeft ?? this.stockLeft,
    imageUrl: imageUrl ?? this.imageUrl,
  );

  Map<String, dynamic> toJson() => {
    'skuId': skuId,
    'selections': selections,
    'originalPrice': originalPrice,
    'salePrice': salePrice,
    'stockLeft': stockLeft,
    'imageUrl': imageUrl,
  };

  factory ProductSku.fromJson(Map<String, dynamic> json) => ProductSku(
    skuId: json['skuId'] as String,
    selections: Map<String, String>.from(json['selections'] as Map),
    originalPrice: (json['originalPrice'] as num).toDouble(),
    salePrice: (json['salePrice'] as num).toDouble(),
    stockLeft: json['stockLeft'] as int,
    imageUrl: json['imageUrl'] as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LiveProduct
// ─────────────────────────────────────────────────────────────────────────────

/// Sản phẩm được hiển thị trong card sản phẩm khi xem livestream.
///
/// NẾU sản phẩm có biến thể: [variantAxes] và [skus] không rỗng.
/// NẾU sản phẩm đơn giản (không biến thể): [variantAxes] rỗng, dùng
///   [stockLeft] và [salePrice] trực tiếp.
class LiveProduct {
  /// ID duy nhất của sản phẩm (product-level, không phải SKU-level)
  final String id;

  /// Tên sản phẩm (tiếng Việt)
  final String name;

  /// URL ảnh sản phẩm mặc định (hiển thị trước khi chọn biến thể)
  final String imageUrl;

  /// Giá gốc hiển thị mặc định – thường là giá thấp nhất hoặc giá SKU đầu tiên
  final double originalPrice;

  /// Giá sale hiển thị mặc định trong live
  final double salePrice;

  /// Phần trăm giảm giá (0-100)
  final int discountPercent;

  /// Tồn kho TỔNG (tổng của tất cả SKU). Dùng khi không có biến thể.
  final int stockLeft;

  /// Số đã bán (tổng tất cả SKU)
  final int soldCount;

  /// Đơn vị sản phẩm (ví dụ: "hộp", "kg", "gói", "đôi", "cái")
  final String unit;

  /// Danh mục sản phẩm
  final String category;

  /// Tính năng đặt hàng tự động có đang bật không
  final bool autoOrderEnabled;

  /// ID thật của products table (khác với id là live_session_products.id)
  final String? productId;

  // ── Variant system ────────────────────────────────────────────────────────

  /// Các trục biến thể (rỗng nếu sản phẩm không có biến thể).
  /// Ví dụ: [Màu sắc axis, Size axis]
  final List<ProductVariantAxis> variantAxes;

  /// Tất cả SKU (rỗng nếu sản phẩm không có biến thể).
  final List<ProductSku> skus;

  const LiveProduct({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.originalPrice,
    required this.salePrice,
    required this.discountPercent,
    required this.stockLeft,
    required this.soldCount,
    required this.unit,
    required this.category,
    this.autoOrderEnabled = false,
    this.productId,
    this.variantAxes = const [],
    this.skus = const [],
  });

  /// Sản phẩm có biến thể không?
  bool get hasVariants => variantAxes.isNotEmpty;

  /// Tổng tồn kho thực (tổng tất cả SKU nếu có biến thể, ngược lại dùng stockLeft)
  int get totalStock {
    if (!hasVariants) return stockLeft;
    return skus.fold(0, (sum, s) => sum + s.stockLeft);
  }

  /// Tìm SKU theo map selections. Trả về null nếu không khớp.
  ProductSku? findSku(Map<String, String> selections) {
    if (skus.isEmpty) return null;
    return skus.where((sku) {
      if (sku.selections.length != selections.length) return false;
      return selections.entries.every(
        (e) => sku.selections[e.key] == e.value,
      );
    }).firstOrNull;
  }

  /// Giá thấp nhất trong tất cả SKU (dùng để hiển thị "Từ X đ")
  double get minSkuPrice {
    if (skus.isEmpty) return salePrice;
    return skus.map((s) => s.salePrice).reduce((a, b) => a < b ? a : b);
  }

  /// Giá cao nhất trong tất cả SKU
  double get maxSkuPrice {
    if (skus.isEmpty) return salePrice;
    return skus.map((s) => s.salePrice).reduce((a, b) => a > b ? a : b);
  }

  /// Có dải giá (min ≠ max) không — dùng để hiển thị "Từ X - Y đ"
  bool get hasPriceRange => minSkuPrice != maxSkuPrice;

  /// Tạo bản sao với một số fields được thay đổi.
  LiveProduct copyWith({
    String? id,
    String? name,
    String? imageUrl,
    double? originalPrice,
    double? salePrice,
    int? discountPercent,
    int? stockLeft,
    int? soldCount,
    String? unit,
    String? category,
    bool? autoOrderEnabled,
    String? productId,
    List<ProductVariantAxis>? variantAxes,
    List<ProductSku>? skus,
  }) {
    return LiveProduct(
      id: id ?? this.id,
      name: name ?? this.name,
      imageUrl: imageUrl ?? this.imageUrl,
      originalPrice: originalPrice ?? this.originalPrice,
      salePrice: salePrice ?? this.salePrice,
      discountPercent: discountPercent ?? this.discountPercent,
      stockLeft: stockLeft ?? this.stockLeft,
      soldCount: soldCount ?? this.soldCount,
      unit: unit ?? this.unit,
      category: category ?? this.category,
      autoOrderEnabled: autoOrderEnabled ?? this.autoOrderEnabled,
      productId: productId ?? this.productId,
      variantAxes: variantAxes ?? this.variantAxes,
      skus: skus ?? this.skus,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'imageUrl': imageUrl,
    'originalPrice': originalPrice,
    'salePrice': salePrice,
    'discountPercent': discountPercent,
    'stockLeft': stockLeft,
    'soldCount': soldCount,
    'unit': unit,
    'category': category,
    'autoOrderEnabled': autoOrderEnabled,
    if (productId != null) 'productId': productId,
    'variantAxes': variantAxes.map((a) => a.toJson()).toList(),
    'skus': skus.map((s) => s.toJson()).toList(),
  };

  factory LiveProduct.fromJson(Map<String, dynamic> json) => LiveProduct(
    id: json['id'] as String,
    name: json['name'] as String,
    imageUrl: json['imageUrl'] as String,
    originalPrice: (json['originalPrice'] as num).toDouble(),
    salePrice: (json['salePrice'] as num).toDouble(),
    discountPercent: json['discountPercent'] as int,
    stockLeft: json['stockLeft'] as int,
    soldCount: json['soldCount'] as int,
    unit: json['unit'] as String,
    category: json['category'] as String,
    autoOrderEnabled: json['autoOrderEnabled'] as bool? ?? false,
    productId: json['productId'] as String?,
    variantAxes: (json['variantAxes'] as List? ?? [])
        .map((a) => ProductVariantAxis.fromJson(a as Map<String, dynamic>))
        .toList(),
    skus: (json['skus'] as List? ?? [])
        .map((s) => ProductSku.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LiveComment
// ─────────────────────────────────────────────────────────────────────────────

/// Một bình luận trong chat của buổi livestream.
class LiveComment {
  /// ID duy nhất của comment
  final String id;

  /// ID người dùng bình luận
  final String userId;

  /// Tên hiển thị của người bình luận
  final String username;

  /// URL avatar người bình luận
  final String? avatarUrl;

  /// Nội dung bình luận
  final String message;

  /// Thời điểm bình luận
  final DateTime timestamp;

  /// Người dùng có phải là chủ cửa hàng/streamer không
  final bool isHost;

  /// Người dùng có phải là người dùng hiện tại không (bản thân)
  final bool isCurrentUser;

  /// Tin nhắn hệ thống từ bot (kết quả xử lý lệnh /mua, /dat, ...)
  final bool isBotMessage;

  /// Màu hiển thị tên (hex string, ví dụ "#FF6B35")
  final String? nameColor;

  const LiveComment({
    required this.id,
    required this.userId,
    required this.username,
    this.avatarUrl,
    required this.message,
    required this.timestamp,
    this.isHost = false,
    this.isCurrentUser = false,
    this.isBotMessage = false,
    this.nameColor,
  });

  LiveComment copyWith({
    String? id,
    String? userId,
    String? username,
    String? avatarUrl,
    String? message,
    DateTime? timestamp,
    bool? isHost,
    bool? isCurrentUser,
    bool? isBotMessage,
    String? nameColor,
  }) {
    return LiveComment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      message: message ?? this.message,
      timestamp: timestamp ?? this.timestamp,
      isHost: isHost ?? this.isHost,
      isCurrentUser: isCurrentUser ?? this.isCurrentUser,
      isBotMessage: isBotMessage ?? this.isBotMessage,
      nameColor: nameColor ?? this.nameColor,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'userId': userId,
    'username': username,
    'avatarUrl': avatarUrl,
    'message': message,
    'timestamp': timestamp.toIso8601String(),
    'isHost': isHost,
    'isCurrentUser': isCurrentUser,
    'isBotMessage': isBotMessage,
    'nameColor': nameColor,
  };

  factory LiveComment.fromJson(Map<String, dynamic> json) => LiveComment(
    id: json['id'] as String,
    userId: json['userId'] as String,
    username: json['username'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    message: json['message'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    isHost: json['isHost'] as bool? ?? false,
    isCurrentUser: json['isCurrentUser'] as bool? ?? false,
    isBotMessage: json['isBotMessage'] as bool? ?? false,
    nameColor: json['nameColor'] as String?,
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// LiveReward
// ─────────────────────────────────────────────────────────────────────────────

/// Phần thưởng xu/điểm trong panel PHẦN THƯỞNG của livestream.
class LiveReward {
  /// Số xu nhận được khi điểm danh
  final int attendanceCoins;

  /// Số xu nhận được sau mỗi phút xem
  final int watchCoins;

  /// Số giây xem hiện tại (dùng để tính xu)
  final int watchSeconds;

  /// Tổng xu đã nhận trong buổi này
  final int totalEarnedCoins;

  /// Đã điểm danh chưa
  final bool hasAttended;

  /// Xu cần để đổi thưởng tiếp theo
  final int nextRewardCoins;

  const LiveReward({
    required this.attendanceCoins,
    required this.watchCoins,
    required this.watchSeconds,
    required this.totalEarnedCoins,
    required this.hasAttended,
    required this.nextRewardCoins,
  });

  LiveReward copyWith({
    int? attendanceCoins,
    int? watchCoins,
    int? watchSeconds,
    int? totalEarnedCoins,
    bool? hasAttended,
    int? nextRewardCoins,
  }) {
    return LiveReward(
      attendanceCoins: attendanceCoins ?? this.attendanceCoins,
      watchCoins: watchCoins ?? this.watchCoins,
      watchSeconds: watchSeconds ?? this.watchSeconds,
      totalEarnedCoins: totalEarnedCoins ?? this.totalEarnedCoins,
      hasAttended: hasAttended ?? this.hasAttended,
      nextRewardCoins: nextRewardCoins ?? this.nextRewardCoins,
    );
  }

  /// Số phút đã xem (để hiển thị)
  int get watchMinutes => watchSeconds ~/ 60;

  /// Progress từ 0.0 đến 1.0 đến mốc xu tiếp theo
  double get progressToNextReward {
    if (nextRewardCoins <= 0) return 1.0;
    return (totalEarnedCoins % nextRewardCoins) / nextRewardCoins;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LiveVoucher
// ─────────────────────────────────────────────────────────────────────────────

/// Voucher/coupon được phát trong buổi livestream.
class LiveVoucher {
  final String id;

  /// Tên voucher (ví dụ: "TROPIA20K")
  final String code;

  /// Mô tả (ví dụ: "Giảm 20.000đ cho đơn từ 100.000đ")
  final String description;

  /// Giá trị giảm (đơn vị VND)
  final double discountValue;

  /// Giảm theo phần trăm hay số tiền cố định
  final bool isPercentage;

  /// Đơn hàng tối thiểu để áp dụng (VND)
  final double minOrderValue;

  /// Ngày hết hạn
  final DateTime expiresAt;

  /// Đã lưu chưa
  final bool isSaved;

  const LiveVoucher({
    required this.id,
    required this.code,
    required this.description,
    required this.discountValue,
    required this.isPercentage,
    required this.minOrderValue,
    required this.expiresAt,
    this.isSaved = false,
  });

  LiveVoucher copyWith({
    String? id,
    String? code,
    String? description,
    double? discountValue,
    bool? isPercentage,
    double? minOrderValue,
    DateTime? expiresAt,
    bool? isSaved,
  }) {
    return LiveVoucher(
      id: id ?? this.id,
      code: code ?? this.code,
      description: description ?? this.description,
      discountValue: discountValue ?? this.discountValue,
      isPercentage: isPercentage ?? this.isPercentage,
      minOrderValue: minOrderValue ?? this.minOrderValue,
      expiresAt: expiresAt ?? this.expiresAt,
      isSaved: isSaved ?? this.isSaved,
    );
  }

  /// Chuỗi hiển thị giá trị giảm
  String get discountDisplay {
    if (isPercentage) {
      return 'Giảm ${discountValue.toInt()}%';
    } else {
      final val = discountValue >= 1000
          ? '${(discountValue / 1000).toStringAsFixed(0)}K'
          : discountValue.toStringAsFixed(0);
      return 'Giảm ${val}đ'; // ignore: unnecessary_brace_in_string_interps
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// LiveStream (model chính)
// ─────────────────────────────────────────────────────────────────────────────

/// Model đại diện cho một buổi livestream đầy đủ.
///
/// Chứa tất cả thông tin cần thiết để render [LiveStreamScreen]:
///   - Thông tin người phát (seller/host)
///   - Trạng thái luồng, số người xem, like
///   - Danh sách sản phẩm đang bán
///   - Voucher đang phát
///   - Phần thưởng
///   - Bình luận
class LiveStream {
  /// ID duy nhất của buổi live
  final String id;

  /// ID của cửa hàng / streamer
  final String sellerId;

  /// Tên cửa hàng / streamer
  final String sellerName;

  /// URL avatar cửa hàng
  final String sellerAvatarUrl;

  /// Có dấu tick xanh xác minh không
  final bool isVerified;

  /// Tiêu đề buổi phát sóng
  final String title;

  /// Mô tả ngắn
  final String description;

  /// URL thumbnail (ảnh xem trước khi chưa vào)
  final String thumbnailUrl;

  /// URL video stream (HLS m3u8 from SRS) — populated by LiveRepository.fetchPlayback().
  final String? streamUrl;

  /// Trạng thái: live / ended / upcoming
  final StreamStatus status;

  /// Số người đang xem
  final int viewerCount;

  /// Số lượt thích
  final int likeCount;

  /// Người dùng hiện tại đã like chưa
  final bool isLiked;

  /// Người dùng hiện tại đã follow chưa
  final bool isFollowing;

  /// Danh mục cửa hàng (ví dụ: "Thực phẩm", "Thời trang", "Mẹ & Bé")
  final String category;

  /// Màu gradient nền (dùng khi không có video thực)
  final List<String> gradientColors;

  /// Sản phẩm đang được featured trong live
  final List<LiveProduct> products;

  /// Voucher đang được phát
  final List<LiveVoucher> vouchers;

  /// Phần thưởng
  final LiveReward reward;

  /// Danh sách bình luận hiện tại (50 bình luận gần nhất)
  final List<LiveComment> comments;

  /// Thời điểm bắt đầu phát
  final DateTime startedAt;

  /// Tag nổi bật (ví dụ: "Top nhà sáng tạo", "Hot", "Trending")
  final String? featuredBadge;

  /// ID của shop (lấy từ shops.id qua seller_id, null nếu chưa có)
  final String? shopId;

  /// ID các sản phẩm đang được ghim bởi host (để viewer + AI biết focus vào đâu)
  final List<String> pinnedProductIds;

  const LiveStream({
    required this.id,
    required this.sellerId,
    required this.sellerName,
    required this.sellerAvatarUrl,
    required this.isVerified,
    required this.title,
    required this.description,
    required this.thumbnailUrl,
    this.streamUrl,
    required this.status,
    required this.viewerCount,
    required this.likeCount,
    required this.isLiked,
    required this.isFollowing,
    required this.category,
    required this.gradientColors,
    required this.products,
    required this.vouchers,
    required this.reward,
    required this.comments,
    required this.startedAt,
    this.featuredBadge,
    this.shopId,
    this.pinnedProductIds = const [],
  });

  /// Sản phẩm đang được ghim đầu tiên (dùng cho AI suggestion)
  LiveProduct? get primaryPinnedProduct {
    if (pinnedProductIds.isEmpty) return products.firstOrNull;
    return products.where((p) => pinnedProductIds.contains(p.id)).firstOrNull
        ?? products.firstOrNull;
  }

  LiveStream copyWith({
    String? id,
    String? sellerId,
    String? sellerName,
    String? sellerAvatarUrl,
    bool? isVerified,
    String? title,
    String? description,
    String? thumbnailUrl,
    String? streamUrl,
    StreamStatus? status,
    int? viewerCount,
    int? likeCount,
    bool? isLiked,
    bool? isFollowing,
    String? category,
    List<String>? gradientColors,
    List<LiveProduct>? products,
    List<LiveVoucher>? vouchers,
    LiveReward? reward,
    List<LiveComment>? comments,
    DateTime? startedAt,
    String? featuredBadge,
    String? shopId,
    List<String>? pinnedProductIds,
  }) {
    return LiveStream(
      id: id ?? this.id,
      sellerId: sellerId ?? this.sellerId,
      sellerName: sellerName ?? this.sellerName,
      sellerAvatarUrl: sellerAvatarUrl ?? this.sellerAvatarUrl,
      isVerified: isVerified ?? this.isVerified,
      title: title ?? this.title,
      description: description ?? this.description,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      streamUrl: streamUrl ?? this.streamUrl,
      status: status ?? this.status,
      viewerCount: viewerCount ?? this.viewerCount,
      likeCount: likeCount ?? this.likeCount,
      isLiked: isLiked ?? this.isLiked,
      isFollowing: isFollowing ?? this.isFollowing,
      category: category ?? this.category,
      gradientColors: gradientColors ?? this.gradientColors,
      products: products ?? this.products,
      vouchers: vouchers ?? this.vouchers,
      reward: reward ?? this.reward,
      comments: comments ?? this.comments,
      startedAt: startedAt ?? this.startedAt,
      featuredBadge: featuredBadge ?? this.featuredBadge,
      shopId: shopId ?? this.shopId,
      pinnedProductIds: pinnedProductIds ?? this.pinnedProductIds,
    );
  }

  /// Định dạng số người xem (ví dụ: 1200 → "1.2K")
  String get viewerCountFormatted {
    if (viewerCount >= 1000000) {
      return '${(viewerCount / 1000000).toStringAsFixed(1)}M';
    } else if (viewerCount >= 1000) {
      return '${(viewerCount / 1000).toStringAsFixed(1)}K';
    }
    return viewerCount.toString();
  }

  /// Định dạng số like
  String get likeCountFormatted {
    if (likeCount >= 1000000) {
      return '${(likeCount / 1000000).toStringAsFixed(1)}M';
    } else if (likeCount >= 1000) {
      return '${(likeCount / 1000).toStringAsFixed(1)}K';
    }
    return likeCount.toString();
  }

  /// Kiểm tra đang phát live
  bool get isLive => status == StreamStatus.live;
}

// ─── SRS publish / playback URL bundles ──────────────────────────────────────
// Returned by the Go backend's POST /api/live/streams (publish) and
// GET /api/live/streams/:id/playback endpoints. Used by RtmpPublishInfo
// widget and HlsViewer.

class PublishURLs {
  final String rtmp;
  final String whip;
  final String srt;

  const PublishURLs({required this.rtmp, required this.whip, required this.srt});

  factory PublishURLs.fromJson(Map<String, dynamic> json) => PublishURLs(
        rtmp: json['rtmp'] as String? ?? '',
        whip: json['whip'] as String? ?? '',
        srt:  json['srt']  as String? ?? '',
      );
}

class PlaybackURLs {
  final String hls;
  final String flv;
  final String whep;

  const PlaybackURLs({required this.hls, required this.flv, required this.whep});

  factory PlaybackURLs.fromJson(Map<String, dynamic> json) => PlaybackURLs(
        hls:  json['hls']  as String? ?? '',
        flv:  json['flv']  as String? ?? '',
        whep: json['whep'] as String? ?? '',
      );
}
