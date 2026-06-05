package video

import (
	"time"

	"github.com/google/uuid"
)

// Video is a short-form uploaded clip shown in the vertical "for you" feed.
// Counters are denormalised here and kept in sync with the join tables by the
// repository. The Seller* / Shop* / Liked / Following fields are populated by
// JOINs in the read queries (zero values on a bare insert row).
type Video struct {
	ID           uuid.UUID  `json:"id"`
	UserID       uuid.UUID  `json:"user_id"`
	ShopID       *uuid.UUID `json:"shop_id,omitempty"`
	VideoURL     string     `json:"video_url"`
	ThumbnailURL *string    `json:"thumbnail_url,omitempty"`
	Caption      *string    `json:"caption,omitempty"`
	Hashtags     []string   `json:"hashtags"`
	DurationSec  int        `json:"duration_sec"`
	Width        int        `json:"width"`
	Height       int        `json:"height"`
	AllowReuse   bool       `json:"allow_reuse"`
	Status       string     `json:"status"`
	ViewCount    int        `json:"view_count"`
	LikeCount    int        `json:"like_count"`
	CommentCount int        `json:"comment_count"`
	ShareCount   int        `json:"share_count"`
	CreatedAt    time.Time  `json:"created_at"`

	// Joined from profiles + shops.
	UserName   *string `json:"user_name,omitempty"`
	UserAvatar *string `json:"user_avatar,omitempty"`
	ShopName   *string `json:"shop_name,omitempty"`
	ShopSlug   *string `json:"shop_slug,omitempty"`

	// Catalog products tagged on the clip (Shopee Video "Xem sản phẩm"),
	// in display order. Always non-nil ([] when none) so the JSON field is a
	// list, never null.
	Products []VideoProduct `json:"products"`

	// Seller coupons featured on the clip (Shopee Video "Voucher"), in display
	// order. Read live from `coupons`, so an expired/deactivated one drops out.
	// Always non-nil ([] when none) so the JSON field is a list, never null.
	Coupons []VideoCoupon `json:"coupons"`

	// Viewer-relative flags (only meaningful when the request is authenticated).
	// Following  = viewer follows the CREATOR (user_follows).
	// ShopFollowing = viewer follows the video's SHOP (shop_follows); always
	// false when the clip has no shop. The feed card's (+) follows the shop when
	// one exists, else falls back to following the creator.
	Liked         bool `json:"liked"`
	Following     bool `json:"following"`
	ShopFollowing bool `json:"shop_following"`
	// ShopHasVoucher = the video's shop has at least one active seller voucher
	// → the card shows "Mua với Voucher". Not viewer-relative (same for all).
	ShopHasVoucher bool `json:"shop_has_voucher"`
}

// VideoProduct is a catalog product tagged on a video. Its display fields are
// read live from `products` (not snapshotted), so the feed card always shows
// the current name / price / sold count. ProductID drives navigation to the
// product detail screen.
type VideoProduct struct {
	ProductID   uuid.UUID `json:"product_id"`
	Name        string    `json:"name"`
	Slug        string    `json:"slug"`
	ImageURL    *string   `json:"image_url,omitempty"`
	BasePrice   int       `json:"base_price"`
	SalePrice   *int      `json:"sale_price,omitempty"`
	TotalSold   int       `json:"total_sold"`
	Rating      float64   `json:"rating"`
	ReviewCount int       `json:"review_count"`

	// Active flash-sale price (Shopee "Flash Sale"), populated when the product
	// is in a sale whose window currently covers now. FlashEndsAt drives the
	// countdown on the card. Both nil when there's no active flash sale.
	FlashPrice   *int       `json:"flash_price,omitempty"`
	FlashEndsAt  *time.Time `json:"flash_ends_at,omitempty"`
}

// VideoCoupon is a seller coupon featured on a video. Its display fields are
// read live from `coupons` (not snapshotted), so the chip always reflects the
// current code / discount / expiry. Code is what the viewer copies to redeem at
// checkout; the cart already knows how to apply it (commerce.ApplyCoupon).
type VideoCoupon struct {
	CouponID      uuid.UUID `json:"coupon_id"`
	Code          string    `json:"code"`
	DiscountType  string    `json:"discount_type"` // percent | fixed
	DiscountValue float64   `json:"discount_value"`
	MinOrderValue int       `json:"min_order_value"`
	MaxDiscount   *int      `json:"max_discount,omitempty"`
	ExpiresAt     time.Time `json:"expires_at"`
}

// VideoReport is a viewer report on a video, joined with display info for the
// admin moderation queue.
type VideoReport struct {
	ID         uuid.UUID  `json:"id"`
	VideoID    uuid.UUID  `json:"video_id"`
	ReporterID uuid.UUID  `json:"reporter_id"`
	Reason     string     `json:"reason"`
	Status     string     `json:"status"`
	Action     *string    `json:"action,omitempty"`
	CreatedAt  time.Time  `json:"created_at"`

	// Joined for the admin list.
	ReporterName  *string `json:"reporter_name,omitempty"`
	VideoCaption  *string `json:"video_caption,omitempty"`
	VideoThumb    *string `json:"video_thumbnail_url,omitempty"`
	VideoStatus   *string `json:"video_status,omitempty"`
	OwnerName     *string `json:"owner_name,omitempty"`
}

// VideoComment is one comment on a video, with its author's display info.
type VideoComment struct {
	ID         uuid.UUID `json:"id"`
	VideoID    uuid.UUID `json:"video_id"`
	UserID     uuid.UUID `json:"user_id"`
	Content    string    `json:"content"`
	LikeCount  int       `json:"like_count"`
	CreatedAt  time.Time `json:"created_at"`
	UserName   *string   `json:"user_name,omitempty"`
	UserAvatar *string   `json:"user_avatar,omitempty"`
}
