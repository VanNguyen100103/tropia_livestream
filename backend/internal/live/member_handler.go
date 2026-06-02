package live

import (
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

// ─────────────────────────────────────────────────────────────────────────
// Live-permission gate + shop member management
// ─────────────────────────────────────────────────────────────────────────

// RequireLivePermission gates livestream creation: only an admin, a shop
// owner, or an approved member with can_live may pass. Everyone else gets
// 403 — the platform's core rule that not just anyone can go live.
// Must run after the auth middleware (needs claims).
func RequireLivePermission(repo *ShopMemberRepository) gin.HandlerFunc {
	return func(c *gin.Context) {
		claims, ok := auth.ClaimsFrom(c)
		if !ok {
			c.Error(httpx.NewAuth("Thiếu Authorization token"))
			c.Abort()
			return
		}
		if claims.Role == auth.RoleAdmin {
			c.Next()
			return
		}
		uid, err := uuid.Parse(claims.UserID)
		if err != nil {
			c.Error(httpx.NewAuth("token không hợp lệ"))
			c.Abort()
			return
		}
		_, allowed, err := repo.AuthorizedShop(c.Request.Context(), uid)
		if err != nil {
			c.Error(httpx.NewInternal("check live permission", err))
			c.Abort()
			return
		}
		if !allowed {
			c.Error(httpx.NewForbidden("Tài khoản chưa được cấp quyền livestream. Liên hệ chủ shop để được duyệt."))
			c.Abort()
			return
		}
		c.Next()
	}
}

// MemberHandler exposes the shop owner's member-management endpoints under
// /api/live/members. The caller must own a shop; they may grant/approve
// staff and collaborators of their own shop only.
type MemberHandler struct {
	repo *ShopMemberRepository
}

func NewMemberHandler(repo *ShopMemberRepository) *MemberHandler {
	return &MemberHandler{repo: repo}
}

func (h *MemberHandler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc) {
	g := r.Group("/members", authMw)
	g.GET("", h.list)
	g.POST("", h.add)
	g.PATCH("/:userSeq", h.update)
	g.DELETE("/:userSeq", h.remove)
}

// ownerShop resolves the calling owner's shop, or writes a 403 and returns
// false when they own no shop.
func (h *MemberHandler) ownerShop(c *gin.Context) (uuid.UUID, uuid.UUID, bool) {
	uid, ok := callerUUID(c)
	if !ok {
		c.Error(httpx.NewAuth("Thiếu Authorization token"))
		return uuid.Nil, uuid.Nil, false
	}
	shopID, err := h.repo.ShopByOwner(c.Request.Context(), uid)
	if errors.Is(err, ErrShopNotFound) {
		c.Error(httpx.NewForbidden("Bạn chưa có shop để quản lý cộng tác viên"))
		return uuid.Nil, uuid.Nil, false
	}
	if err != nil {
		c.Error(httpx.NewInternal("resolve shop", err))
		return uuid.Nil, uuid.Nil, false
	}
	return shopID, uid, true
}

func (h *MemberHandler) list(c *gin.Context) {
	shopID, _, ok := h.ownerShop(c)
	if !ok {
		return
	}
	items, err := h.repo.ListMembers(c.Request.Context(), shopID)
	if err != nil {
		c.Error(httpx.NewInternal("list members", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

type addMemberReq struct {
	// Identifier is the member's email or phone (SĐT).
	Identifier string `json:"identifier" binding:"required"`
	MemberType string `json:"member_type"` // staff | collaborator (default collaborator)
	CanLive    *bool  `json:"can_live"`    // default true
	Status     string `json:"status"`      // default approved (owner self-approves)
}

func (h *MemberHandler) add(c *gin.Context) {
	shopID, ownerID, ok := h.ownerShop(c)
	if !ok {
		return
	}
	var req addMemberReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewBadRequest(err.Error()))
		return
	}
	memberType := req.MemberType
	if memberType != "staff" && memberType != "collaborator" {
		memberType = "collaborator"
	}
	canLive := true
	if req.CanLive != nil {
		canLive = *req.CanLive
	}
	status := req.Status
	if status != "pending" && status != "approved" && status != "rejected" {
		status = "approved" // owner adding a member approves them by default
	}
	userID, err := h.repo.ResolveUser(c.Request.Context(), req.Identifier)
	if errors.Is(err, ErrMemberUserNotFound) {
		c.Error(httpx.NewNotFound("Không tìm thấy người dùng với email/SĐT này"))
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("resolve user", err))
		return
	}
	if userID == ownerID {
		c.Error(httpx.NewBadRequest("Bạn là chủ shop, không cần thêm chính mình"))
		return
	}
	m, err := h.repo.UpsertMember(c.Request.Context(), shopID, userID, memberType, canLive, status, ownerID)
	if err != nil {
		c.Error(httpx.NewInternal("add member", err))
		return
	}
	httpx.SetMessage(c, "Đã cấp quyền livestream")
	c.JSON(http.StatusOK, m)
}

type updateMemberReq struct {
	Status  string `json:"status"`   // approved | rejected | pending
	CanLive *bool  `json:"can_live"`
}

func (h *MemberHandler) update(c *gin.Context) {
	shopID, ownerID, ok := h.ownerShop(c)
	if !ok {
		return
	}
	userID, ok := h.resolveUserSeq(c)
	if !ok {
		return
	}
	var req updateMemberReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewBadRequest(err.Error()))
		return
	}
	// Default to the member's current values for any field omitted.
	cur, err := h.repo.GetMember(c.Request.Context(), shopID, userID)
	if errors.Is(err, ErrMemberNotFound) {
		c.Error(httpx.NewNotFound("Thành viên không thuộc shop của bạn"))
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("get member", err))
		return
	}
	status := req.Status
	if status != "pending" && status != "approved" && status != "rejected" {
		status = cur.Status
	}
	canLive := cur.CanLive
	if req.CanLive != nil {
		canLive = *req.CanLive
	}
	m, err := h.repo.UpdateStatus(c.Request.Context(), shopID, userID, status, canLive, ownerID)
	if err != nil {
		c.Error(httpx.NewInternal("update member", err))
		return
	}
	c.JSON(http.StatusOK, m)
}

func (h *MemberHandler) remove(c *gin.Context) {
	shopID, _, ok := h.ownerShop(c)
	if !ok {
		return
	}
	userID, ok := h.resolveUserSeq(c)
	if !ok {
		return
	}
	if err := h.repo.RemoveMember(c.Request.Context(), shopID, userID); err != nil {
		if errors.Is(err, ErrMemberNotFound) {
			c.Error(httpx.NewNotFound("Thành viên không thuộc shop của bạn"))
			return
		}
		c.Error(httpx.NewInternal("remove member", err))
		return
	}
	c.Status(http.StatusNoContent)
}

// resolveUserSeq turns the :userSeq path param (profile integer id) into a
// uuid, writing the appropriate error and returning false on failure.
func (h *MemberHandler) resolveUserSeq(c *gin.Context) (uuid.UUID, bool) {
	seq, err := strconv.ParseInt(c.Param("userSeq"), 10, 64)
	if err != nil {
		c.Error(httpx.NewBadRequest("userSeq không hợp lệ"))
		return uuid.Nil, false
	}
	userID, err := h.repo.UserBySeq(c.Request.Context(), seq)
	if errors.Is(err, ErrMemberUserNotFound) {
		c.Error(httpx.NewNotFound("Không tìm thấy người dùng"))
		return uuid.Nil, false
	}
	if err != nil {
		c.Error(httpx.NewInternal("resolve user", err))
		return uuid.Nil, false
	}
	return userID, true
}
