package live

import (
	"errors"
	"net/http"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend-go/internal/auth"
)

type Handler struct {
	svc *Service
}

func NewHandler(svc *Service) *Handler {
	return &Handler{svc: svc}
}

func (h *Handler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc) {
	r.GET("/streams", h.listLive)             // public
	r.GET("/streams/:id/playback", h.getPlayback) // public

	authed := r.Group("/streams", authMw)
	authed.POST("", auth.RequireRole(auth.RoleSeller, auth.RoleAdmin), h.createStream)
	authed.GET("/:id/publish", h.getPublish) // owner only
}

type createReq struct {
	Title         string `json:"title" binding:"required,min=1,max=200"`
	Description   string `json:"description" binding:"max=2000"`
	CoverImageURL string `json:"cover_image_url"`
	Category      string `json:"category"`
}

func (h *Handler) createStream(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	sellerID, err := uuid.Parse(claims.UserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}

	var req createReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	stream, err := h.svc.CreateStream(c.Request.Context(), sellerID, req.Title, req.Description, req.CoverImageURL, req.Category)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	c.JSON(http.StatusCreated, gin.H{
		"stream":  stream,
		"publish": h.svc.BuildPublishURLs(stream),
	})
}

func (h *Handler) listLive(c *gin.Context) {
	streams, err := h.svc.ListLive(c.Request.Context(), 20)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"streams": streams})
}

func (h *Handler) getPlayback(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stream id"})
		return
	}
	stream, err := h.svc.GetStream(c.Request.Context(), id)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "stream not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	playback := h.svc.BuildPlaybackURLs(stream)
	// Hide stream_key from public response (don't expose secret in JSON)
	stream.StreamKey = ""

	c.JSON(http.StatusOK, gin.H{
		"stream":   stream,
		"playback": playback,
	})
}

func (h *Handler) getPublish(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	sellerID, err := uuid.Parse(claims.UserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}

	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stream id"})
		return
	}

	stream, err := h.svc.GetStream(c.Request.Context(), id)
	if err != nil {
		if errors.Is(err, ErrNotFound) {
			c.JSON(http.StatusNotFound, gin.H{"error": "stream not found"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Only the seller who owns the stream can get publish URLs
	if stream.SellerID != sellerID && claims.Role != auth.RoleAdmin {
		c.JSON(http.StatusForbidden, gin.H{"error": "not the owner of this stream"})
		return
	}

	c.JSON(http.StatusOK, gin.H{
		"stream":  stream,
		"publish": h.svc.BuildPublishURLs(stream),
	})
}
