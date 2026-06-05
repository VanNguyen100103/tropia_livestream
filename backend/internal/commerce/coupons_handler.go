package commerce

import (
	"context"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

// CouponHandler exposes public + buyer-facing coupon endpoints. Host-only
// coupon CRUD (create / announce within a live session) lives in
// internal/live/handler.go and is intentionally not duplicated here —
// these routes only let buyers discover and validate codes.
// ShopForSeller resolves the shop a seller owns. Returns ok=false when the
// seller hasn't created a shop yet. Provided by main (adapts shops.Repository)
// so this package doesn't import shops.
type ShopForSeller func(ctx context.Context, sellerID uuid.UUID) (uuid.UUID, bool, error)

type CouponHandler struct {
	repo  *CouponRepository
	shops ShopForSeller
}

func NewCouponHandler(repo *CouponRepository) *CouponHandler {
	return &CouponHandler{repo: repo}
}

// WithShopResolver enables the seller voucher routes (create / list mine).
func (h *CouponHandler) WithShopResolver(f ShopForSeller) *CouponHandler {
	h.shops = f
	return h
}

// Register wires:
//   GET  /available       — platform-wide coupons (session_id IS NULL).
//                           Public; surfaced in the cart's "Tropia Voucher" row.
//   GET  /shop/:shopId    — coupons from any live session owned by this shop.
//                           Public so the cart screen can preload without a token.
//   POST /validate        — auth required so the buyer is identified for
//                           the order-time RecordUsage trail. The validate
//                           result itself no longer varies per user (the
//                           per-user "already used" check was removed — 1b);
//                           a coupon is gated only by max_uses / expiry /
//                           min-order.
func (h *CouponHandler) Register(r *gin.RouterGroup, authMw, sellerMw gin.HandlerFunc) {
	r.GET("/available", h.listPlatform)
	r.GET("/shop/:shopId", h.listShop)
	r.POST("/validate", authMw, h.validate)

	// Seller-owned shop vouchers ("Mua với Voucher"). Only wired when a shop
	// resolver is attached (WithShopResolver).
	if h.shops != nil {
		r.POST("", authMw, sellerMw, h.createShopVoucher)
		r.GET("/mine", authMw, sellerMw, h.listMine)
	}
}

func (h *CouponHandler) listPlatform(c *gin.Context) {
	coupons, err := h.repo.ListPlatformActive(c.Request.Context())
	if err != nil {
		c.Error(httpx.NewInternal("list platform coupons", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": coupons})
}

func (h *CouponHandler) listShop(c *gin.Context) {
	shopID, err := uuid.Parse(c.Param("shopId"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid shop id", nil))
		return
	}
	coupons, err := h.repo.ListByShop(c.Request.Context(), shopID)
	if err != nil {
		c.Error(httpx.NewInternal("list shop coupons", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": coupons})
}

type validateReq struct {
	Code       string `json:"code"       binding:"required"`
	OrderTotal int    `json:"orderTotal" binding:"required,min=1"`
}

func (h *CouponHandler) validate(c *gin.Context) {
	var req validateReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)

	res, err := ApplyCoupon(c.Request.Context(), h.repo,
		strings.ToUpper(strings.TrimSpace(req.Code)), uid, req.OrderTotal)
	if err != nil {
		c.Error(err)
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"couponId":       res.Coupon.ID,
		"code":           res.Coupon.Code,
		"discountType":   res.Coupon.DiscountType,
		"discountValue":  res.Coupon.DiscountValue,
		"discountAmount": res.DiscountAmount,
	})
}

// ── Seller shop vouchers ──────────────────────────────────────────────────────

// resolveShop returns the caller's shop, or writes a client error + false when
// they have no shop yet.
func (h *CouponHandler) resolveShop(c *gin.Context) (uuid.UUID, bool) {
	claims, _ := auth.ClaimsFrom(c)
	sellerID, _ := uuid.Parse(claims.UserID)
	shopID, ok, err := h.shops(c.Request.Context(), sellerID)
	if err != nil {
		c.Error(httpx.NewInternal("resolve shop", err))
		return uuid.Nil, false
	}
	if !ok {
		c.Error(httpx.NewValidation("bạn chưa có shop để tạo voucher", nil))
		return uuid.Nil, false
	}
	return shopID, true
}

type createVoucherReq struct {
	Code          string  `json:"code" binding:"required,min=2,max=50"`
	DiscountType  string  `json:"discount_type" binding:"required,oneof=percent fixed"`
	DiscountValue float64 `json:"discount_value" binding:"required,gt=0"`
	MinOrderValue float64 `json:"min_order_value"`
	MaxDiscount   *int    `json:"max_discount"`
	MaxUses       *int    `json:"max_uses"`
	ExpiresAt     string  `json:"expires_at" binding:"required"`
}

func (h *CouponHandler) createShopVoucher(c *gin.Context) {
	shopID, ok := h.resolveShop(c)
	if !ok {
		return
	}
	var req createVoucherReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	expires, err := time.Parse(time.RFC3339, req.ExpiresAt)
	if err != nil {
		c.Error(httpx.NewValidation("expires_at must be RFC3339", nil))
		return
	}
	if expires.Before(time.Now()) {
		c.Error(httpx.NewValidation("thời hạn voucher đã ở quá khứ", nil))
		return
	}
	if req.DiscountType == "percent" && req.DiscountValue > 100 {
		c.Error(httpx.NewValidation("phần trăm giảm tối đa 100", nil))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	sellerID, _ := uuid.Parse(claims.UserID)
	coupon, err := h.repo.Create(c.Request.Context(),
		strings.ToUpper(strings.TrimSpace(req.Code)), req.DiscountType,
		req.DiscountValue, req.MinOrderValue,
		req.MaxDiscount, req.MaxUses,
		expires, nil, &shopID, sellerID)
	if err != nil {
		if strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "duplicate") {
			c.Error(httpx.NewConflict("mã voucher đã tồn tại"))
			return
		}
		c.Error(httpx.NewInternal("create voucher", err))
		return
	}
	c.JSON(http.StatusCreated, coupon)
}

func (h *CouponHandler) listMine(c *gin.Context) {
	shopID, ok := h.resolveShop(c)
	if !ok {
		return
	}
	coupons, err := h.repo.ListByShop(c.Request.Context(), shopID)
	if err != nil {
		c.Error(httpx.NewInternal("list my vouchers", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"data": coupons})
}
