package live

import (
	"crypto/rand"
	"encoding/hex"
	"errors"
	"net/http"
	"strconv"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/cache"
	"github.com/tropia/backend/internal/httpx"
)

type Handler struct {
	svc   *Service
	repo  *SessionRepository
	cache *cache.Cache
}

func NewHandler(svc *Service, repo *SessionRepository, c *cache.Cache) *Handler {
	return &Handler{svc: svc, repo: repo, cache: c}
}

func (h *Handler) Register(r *gin.RouterGroup, authMw, sellerMw gin.HandlerFunc) {
	r.GET("/streams", h.listActive)
	r.GET("/streams/:id", h.getOne)
	r.GET("/streams/:id/stats", h.getStats)
	r.GET("/streams/:id/chat", h.listChat)
	r.GET("/streams/:id/products", h.listProducts)
	r.GET("/streams/:id/playback", h.getPlayback)
	r.POST("/streams/:id/like", h.likeAnon)

	authed := r.Group("/streams", authMw)
	authed.POST("/:id/join", h.join)
	authed.POST("/:id/leave", h.leave)
	authed.POST("/:id/chat", h.postChat)
	authed.POST("/:id/track-cart-add", h.trackCartAdd)
	authed.POST("/:id/track-follow", h.trackFollow)

	seller := r.Group("/streams", authMw, sellerMw)
	seller.POST("", h.create)
	seller.POST("/:id/end", h.end)
	seller.GET("/:id/publish", h.getPublish)
}

// ---------- Create / End ----------

type createReq struct {
	Title         string `json:"title" binding:"required,min=1,max=200"`
	Description   string `json:"description"`
	CoverImageURL string `json:"cover_image_url"`
	Category      string `json:"category"`
}

func (h *Handler) create(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	sellerID, _ := uuid.Parse(claims.UserID)
	var req createReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	channel := generateChannelName()
	sess, err := h.repo.Create(c.Request.Context(), sellerID, req.Title, req.Description, req.CoverImageURL, req.Category, channel)
	if err != nil {
		c.Error(httpx.NewInternal("create session", err))
		return
	}
	_ = h.cache.InvalidatePattern(c.Request.Context(), "live:sessions:*")
	c.JSON(http.StatusCreated, gin.H{
		"session": sess,
		"publish": h.svc.BuildPublishURLs(&Stream{StreamKey: channel}),
	})
}

func (h *Handler) end(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	if sess.SellerID != uid && claims.Role != auth.RoleAdmin {
		c.Error(httpx.NewForbidden("not the owner"))
		return
	}
	if err := h.repo.End(c.Request.Context(), id); err != nil {
		c.Error(httpx.NewInternal("end session", err))
		return
	}
	_ = h.cache.InvalidatePattern(c.Request.Context(), "live:session*")
	c.Status(http.StatusNoContent)
}

// ---------- Lists / Single ----------

func (h *Handler) listActive(c *gin.Context) {
	sessions, err := h.repo.ListActive(c.Request.Context(), 50)
	if err != nil {
		c.Error(httpx.NewInternal("list active", err))
		return
	}
	// Hide stream keys from public listings
	for i := range sessions {
		sessions[i].AgoraChannel = ""
	}
	c.JSON(http.StatusOK, gin.H{"sessions": sessions})
}

func (h *Handler) getOne(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	// Hide stream key
	sess.AgoraChannel = ""
	c.JSON(http.StatusOK, gin.H{"session": sess})
}

func (h *Handler) getPlayback(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	playback := h.svc.BuildPlaybackURLs(&Stream{StreamKey: sess.AgoraChannel})
	sess.AgoraChannel = ""
	c.JSON(http.StatusOK, gin.H{"session": sess, "playback": playback})
}

func (h *Handler) getPublish(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	if sess.SellerID != uid && claims.Role != auth.RoleAdmin {
		c.Error(httpx.NewForbidden("not the owner"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"session": sess,
		"publish": h.svc.BuildPublishURLs(&Stream{StreamKey: sess.AgoraChannel}),
	})
}

func (h *Handler) getStats(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"viewer_count":   sess.ViewerCount,
		"like_count":     sess.LikeCount,
		"order_count":    sess.OrderCount,
		"revenue":        sess.Revenue,
		"cart_add_count": sess.CartAddCount,
		"follow_count":   sess.FollowCount,
		"status":         sess.Status,
	})
}

// ---------- Viewer tracking ----------

func (h *Handler) join(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	_ = h.repo.UpsertViewer(c.Request.Context(), id, uid)
	c.Status(http.StatusNoContent)
}

func (h *Handler) leave(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	_ = h.repo.RemoveViewer(c.Request.Context(), id, uid)
	c.Status(http.StatusNoContent)
}

func (h *Handler) likeAnon(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	_ = h.repo.IncrementLikes(c.Request.Context(), id)
	c.Status(http.StatusNoContent)
}

func (h *Handler) trackCartAdd(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	_ = h.repo.IncrementCartAdd(c.Request.Context(), id)
	c.Status(http.StatusNoContent)
}

func (h *Handler) trackFollow(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	_ = h.repo.IncrementFollow(c.Request.Context(), id)
	c.Status(http.StatusNoContent)
}

// ---------- Chat ----------

func (h *Handler) listChat(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	limit, _ := strconv.Atoi(c.DefaultQuery("limit", "50"))
	msgs, err := h.repo.RecentChats(c.Request.Context(), id, limit)
	if err != nil {
		c.Error(httpx.NewInternal("list chat", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"messages": msgs})
}

type chatReq struct {
	Message string `json:"message" binding:"required,min=1,max=500"`
	Type    string `json:"type"`
	IsHost  bool   `json:"is_host"`
}

func (h *Handler) postChat(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	var req chatReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	username := "Viewer"
	if req.IsHost {
		username = "Trợ lý AI"
	}
	var isHost *bool
	if req.IsHost {
		isHost = &req.IsHost
	}
	m, err := h.repo.InsertChat(c.Request.Context(), ChatMessage{
		SessionID: id, UserID: uid, Username: username, Message: req.Message,
		Type: req.Type, IsHost: isHost,
	})
	if err != nil {
		c.Error(httpx.NewInternal("send chat", err))
		return
	}
	c.JSON(http.StatusCreated, m)
}

// ---------- Products ----------

func (h *Handler) listProducts(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	items, err := h.repo.ListProducts(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewInternal("list products", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"products": items})
}

// ---------- Helpers ----------

func generateChannelName() string {
	b := make([]byte, 8)
	_, _ = rand.Read(b)
	return "live_" + hex.EncodeToString(b)
}

// Make ErrSessionNotFound check accessible to other handlers
func IsNotFound(err error) bool {
	return errors.Is(err, ErrSessionNotFound)
}
