// Package admin exposes admin-only user management: change a user's system
// role and credit loyalty points. Both routes are gated by adminMw in main.go
// and every action is recorded in audit_log.
package admin

import (
	"context"
	"errors"
	"net/http"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/audit"
	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

type Handler struct {
	repo  *Repository
	audit *audit.Repository
}

func NewHandler(repo *Repository, auditRepo *audit.Repository) *Handler {
	return &Handler{repo: repo, audit: auditRepo}
}

// Register wires the admin routes under the given group. authMw + adminMw are
// applied here (not on the caller's group) so the mount point stays explicit.
//
//	PATCH /api/admin/users/:id/role     {"role":"seller"}
//	POST  /api/admin/users/:id/loyalty  {"points":100000}
func (h *Handler) Register(r *gin.RouterGroup, authMw, adminMw gin.HandlerFunc) {
	g := r.Group("", authMw, adminMw)
	g.PATCH("/users/:id/role", h.changeRole)
	g.POST("/users/:id/loyalty", h.addLoyalty)
}

// ---------- role ----------

type changeRoleReq struct {
	Role string `json:"role" binding:"required"`
}

func (h *Handler) changeRole(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewBadRequest("user id không hợp lệ"))
		return
	}
	var req changeRoleReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	role := strings.ToLower(strings.TrimSpace(req.Role))
	if role != string(auth.RoleBuyer) && role != string(auth.RoleSeller) && role != string(auth.RoleAdmin) {
		c.Error(httpx.NewValidation("role phải là buyer, seller hoặc admin", nil))
		return
	}

	actorID, actorRole, ip := actorFromContext(c)
	// Guard: don't let an admin strip their own admin rights and lock
	// themselves out of this very endpoint.
	if actorID != nil && *actorID == id && role != string(auth.RoleAdmin) {
		c.Error(httpx.NewBadRequest("Không thể tự hạ quyền admin của chính mình"))
		return
	}

	res, err := h.repo.SetRole(c.Request.Context(), id, role)
	if errors.Is(err, ErrUserNotFound) {
		c.Error(httpx.NewNotFound("Không tìm thấy người dùng"))
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("đổi role", err))
		return
	}

	h.logAudit(c.Request.Context(), audit.Entry{
		ActorID:    actorID,
		ActorRole:  actorRole,
		ActorIP:    ip,
		Action:     audit.ActionRoleChange,
		TargetType: audit.TargetUser,
		TargetID:   id.String(),
		Payload: map[string]any{
			"email":    res.Email,
			"old_role": res.OldRole,
			"new_role": res.NewRole,
		},
	})

	httpx.SetMessage(c, "Đã cập nhật quyền tài khoản")
	c.JSON(http.StatusOK, gin.H{
		"id":       res.ID,
		"email":    res.Email,
		"name":     res.Name,
		"old_role": res.OldRole,
		"role":     res.NewRole,
	})
}

// ---------- loyalty ----------

type addLoyaltyReq struct {
	Points int `json:"points" binding:"required"`
}

func (h *Handler) addLoyalty(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewBadRequest("user id không hợp lệ"))
		return
	}
	var req addLoyaltyReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	if req.Points <= 0 {
		c.Error(httpx.NewValidation("points phải là số nguyên dương", nil))
		return
	}

	res, err := h.repo.AddLoyalty(c.Request.Context(), id, req.Points)
	if errors.Is(err, ErrUserNotFound) {
		c.Error(httpx.NewNotFound("Không tìm thấy người dùng"))
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("cộng điểm loyalty", err))
		return
	}

	actorID, actorRole, ip := actorFromContext(c)
	h.logAudit(c.Request.Context(), audit.Entry{
		ActorID:    actorID,
		ActorRole:  actorRole,
		ActorIP:    ip,
		Action:     audit.ActionLoyaltyCredit,
		TargetType: audit.TargetUser,
		TargetID:   id.String(),
		Payload: map[string]any{
			"email":   res.Email,
			"added":   res.Added,
			"balance": res.Balance,
		},
	})

	httpx.SetMessage(c, "Đã cộng điểm loyalty")
	c.JSON(http.StatusOK, gin.H{
		"user_id": res.UserID,
		"email":   res.Email,
		"added":   res.Added,
		"balance": res.Balance,
	})
}

// ---------- helpers ----------

func (h *Handler) logAudit(ctx context.Context, e audit.Entry) {
	if h.audit == nil {
		return
	}
	_ = h.audit.Log(ctx, e)
}

// actorFromContext extracts the calling admin's identity for the audit row.
func actorFromContext(c *gin.Context) (uid *uuid.UUID, role, ip string) {
	ip = c.ClientIP()
	claims, ok := auth.ClaimsFrom(c)
	if !ok {
		return nil, "", ip
	}
	parsed, err := uuid.Parse(claims.UserID)
	if err != nil {
		return nil, string(claims.Role), ip
	}
	return &parsed, string(claims.Role), ip
}
