package commerce

import (
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

// CouponHandler exposes public + buyer-facing coupon endpoints. Host-only
// coupon CRUD (create / announce within a live session) lives in
// internal/live/handler.go and is intentionally not duplicated here —
// these routes only let buyers discover and validate codes.
type CouponHandler struct {
	repo *CouponRepository
}

func NewCouponHandler(repo *CouponRepository) *CouponHandler {
	return &CouponHandler{repo: repo}
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
func (h *CouponHandler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc) {
	r.GET("/available", h.listPlatform)
	r.GET("/shop/:shopId", h.listShop)
	r.POST("/validate", authMw, h.validate)
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
