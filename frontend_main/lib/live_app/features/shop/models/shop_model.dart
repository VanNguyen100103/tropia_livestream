class ShopModel {
  final String id;
  final String slug;
  final String name;
  final String? description;
  final String? bannerUrl;
  final String? logoUrl;
  final String? avatarUrl;
  final String? ownerId;
  final bool isVerified;
  final double rating;
  final int totalSales;
  final int followerCount;
  final bool isFollowing;

  const ShopModel({
    required this.id,
    required this.slug,
    required this.name,
    this.description,
    this.bannerUrl,
    this.logoUrl,
    this.avatarUrl,
    this.ownerId,
    this.isVerified = false,
    this.rating = 0,
    this.totalSales = 0,
    this.followerCount = 0,
    this.isFollowing = false,
  });

  factory ShopModel.fromJson(Map<String, dynamic> j) => ShopModel(
        id:            j['id']             as String,
        slug:          j['slug']           as String,
        name:          j['name']           as String,
        description:   j['description']    as String?,
        bannerUrl:     j['banner_url']     as String?,
        logoUrl:       j['logo_url']       as String?,
        avatarUrl:     (j['avatar_url'] ?? j['logo_url']) as String?,
        ownerId:       j['owner_id']       as String?,
        isVerified:    j['is_verified']    as bool? ?? false,
        rating:        (j['rating']        as num?)?.toDouble() ?? 0,
        totalSales:    (j['total_sales']   as num?)?.toInt() ?? 0,
        followerCount: (j['follower_count'] as num?)?.toInt() ?? 0,
        isFollowing:   j['is_following']   as bool? ?? false,
      );

  ShopModel copyWith({
    bool? isFollowing,
    int? followerCount,
    String? logoUrl,
    String? avatarUrl,
  }) => ShopModel(
        id:            id,
        slug:          slug,
        name:          name,
        description:   description,
        bannerUrl:     bannerUrl,
        logoUrl:       logoUrl       ?? this.logoUrl,
        avatarUrl:     avatarUrl     ?? this.avatarUrl,
        ownerId:       ownerId,
        isVerified:    isVerified,
        rating:        rating,
        totalSales:    totalSales,
        followerCount: followerCount ?? this.followerCount,
        isFollowing:   isFollowing   ?? this.isFollowing,
      );
}
