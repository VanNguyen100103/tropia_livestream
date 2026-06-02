package live

import (
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"

	"github.com/tropia/backend/internal/audit"
	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/httpx"
)

// ─────────────────────────────────────────────────────────────────────────
// Spec endpoint surface (LIVESTREAM_API.md)
//
// These handlers implement the mobile API contract verbatim and reuse the
// Handler's existing wiring (service, repo, cache, mute repo, audit). They
// are registered by RegisterSpec instead of the legacy Register.
// ─────────────────────────────────────────────────────────────────────────

// RegisterSpec wires the LIVESTREAM_API.md endpoint surface under the
// group (mounted at /api/live). authMw is applied to host/chat/gift
// actions; the rest are public.
func (h *Handler) RegisterSpec(r *gin.RouterGroup, authMw gin.HandlerFunc) {
	startLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{Limit: 10, WindowMs: 60 * 60 * 1000, FailClosed: false})
	chatLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{Limit: 8, WindowMs: 3 * 1000, FailClosed: false})
	listLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{Limit: 120, WindowMs: 60 * 1000, FailClosed: false})

	// Public (viewer) endpoints.
	r.GET("/list", listLimit, h.specList)
	r.GET("/watch", h.specWatch)
	r.GET("/chat/history", h.specChatHistory)
	r.GET("/gifts", h.specGifts)
	r.GET("/gifts/recent", h.specGiftsRecent)

	// Authenticated (host / buyer) endpoints.
	a := r.Group("", authMw)
	a.POST("/start", startLimit, h.specStart)
	a.POST("/stop", h.specStop)
	a.GET("/my", h.specMy)
	a.POST("/chat/send", chatLimit, h.specChatSend)
	a.POST("/gift/send", h.specGiftSend)
}

// callerUUID parses the authenticated user's UUID from the JWT claims.
func callerUUID(c *gin.Context) (uuid.UUID, bool) {
	claims, ok := auth.ClaimsFrom(c)
	if !ok {
		return uuid.Nil, false
	}
	uid, err := uuid.Parse(claims.UserID)
	if err != nil {
		return uuid.Nil, false
	}
	return uid, true
}

// redisChannel mirrors the spec's sanitised channel name
// (live:room:{stream_key without underscores}).
func redisChannel(streamKey string) string {
	return "live:room:" + strings.ReplaceAll(streamKey, "_", "")
}

// ───────────────────────── Host ─────────────────────────

type specStartReq struct {
	Title string `json:"title"`
}

func (h *Handler) specStart(c *gin.Context) {
	uid, ok := callerUUID(c)
	if !ok {
		c.Error(httpx.NewAuth("Thiếu Authorization token"))
		return
	}
	var req specStartReq
	_ = c.ShouldBindJSON(&req) // title optional; ignore bind errors on empty body
	sess, err := h.repo.StartSpecSession(c.Request.Context(), uid, strings.TrimSpace(req.Title))
	if err != nil {
		c.Error(httpx.NewInternal("start live", err))
		return
	}
	urls := h.svc.SpecPublishURLs(sess.StreamKey, sess.PublishToken)
	uidPtr, role, ip := actorFromContext(c)
	h.logAudit(c.Request.Context(), audit.Entry{
		ActorID: uidPtr, ActorRole: role, ActorIP: ip,
		Action:     audit.ActionLiveSessionCreate,
		TargetType: audit.TargetLiveSession,
		TargetID:   strconv.FormatInt(sess.ID, 10),
		Payload:    map[string]any{"title": sess.Title, "stream_key": "<redacted>"},
	})
	httpx.SetMessage(c, "Tạo phiên live thành công")
	c.JSON(http.StatusOK, gin.H{
		"id":                       sess.ID,
		// session_id is the internal UUID — not part of the mobile spec, but
		// the in-app host UI uses it to address the legacy product / coupon /
		// stats endpoints (which key by session UUID, not the integer id).
		"session_id":               sess.SessionUUID(),
		"stream_key":               sess.StreamKey,
		"publish_token":            sess.PublishToken,
		"publish_token_expires_at": sess.PublishTokenExpiresAt,
		"rtmp_url":                 urls.RTMPURL,
		"rtmp_base":                urls.RTMPBase,
		"hls_url":                  urls.HLSURL,
		"status":                   sess.Status,
		"title":                    sess.Title,
		"created_at":               sess.CreatedAt,
	})
}

func (h *Handler) specStop(c *gin.Context) {
	uid, ok := callerUUID(c)
	if !ok {
		c.Error(httpx.NewAuth("Thiếu Authorization token"))
		return
	}
	streamKey, endedAt, err := h.repo.StopSpecSession(c.Request.Context(), uid)
	if errors.Is(err, ErrNoOpenSession) {
		c.JSON(http.StatusOK, gin.H{"success": true, "message": "Không có phiên live đang mở"})
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("stop live", err))
		return
	}
	h.publishListChange("session_ended")
	uidPtr, role, ip := actorFromContext(c)
	h.logAudit(c.Request.Context(), audit.Entry{
		ActorID: uidPtr, ActorRole: role, ActorIP: ip,
		Action:     audit.ActionLiveSessionEnd,
		TargetType: audit.TargetLiveSession,
		TargetID:   streamKey,
	})
	c.JSON(http.StatusOK, gin.H{
		"success":    true,
		"stream_key": streamKey,
		"ended_at":   endedAt,
	})
}

func (h *Handler) specMy(c *gin.Context) {
	uid, ok := callerUUID(c)
	if !ok {
		c.Error(httpx.NewAuth("Thiếu Authorization token"))
		return
	}
	sess, err := h.repo.MySpecSession(c.Request.Context(), uid)
	if errors.Is(err, ErrNoOpenSession) {
		httpx.SetMessage(c, "Không có phiên live")
		c.JSON(http.StatusOK, gin.H(nil))
		return
	}
	if err != nil {
		c.Error(httpx.NewInternal("my live", err))
		return
	}
	urls := h.svc.SpecPublishURLs(sess.StreamKey, sess.PublishToken)
	c.JSON(http.StatusOK, gin.H{
		"id":                       sess.ID,
		"session_id":               sess.SessionUUID(),
		"stream_key":               sess.StreamKey,
		"rtmp_url":                 urls.RTMPURL,
		"rtmp_base":                urls.RTMPBase,
		"hls_url":                  urls.HLSURL,
		"publish_token":            sess.PublishToken,
		"publish_token_expires_at": sess.PublishTokenExpiresAt,
		"status":                   sess.Status,
		"title":                    sess.Title,
		"started_at":               sess.StartedAt,
	})
}

// ───────────────────────── Viewer ─────────────────────────

func (h *Handler) specList(c *gin.Context) {
	limit := 20
	if v := c.Query("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			limit = n
		}
	}
	sessions, err := h.repo.ListLiveSpec(c.Request.Context(), limit)
	if err != nil {
		c.Error(httpx.NewInternal("list live", err))
		return
	}
	items := make([]gin.H, 0, len(sessions))
	for i := range sessions {
		items = append(items, h.specSessionView(&sessions[i], false))
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

func (h *Handler) specWatch(c *gin.Context) {
	streamKey := strings.TrimSpace(c.Query("stream_key"))
	if streamKey == "" {
		c.Error(httpx.NewValidation("Thiếu stream_key", nil))
		return
	}
	sess, err := h.repo.SpecByStreamKey(c.Request.Context(), streamKey)
	if err != nil || sess.Status == "offline" || sess.Status == "ended" {
		c.Error(httpx.NewNotFound("Stream không live hoặc không tồn tại"))
		return
	}
	c.JSON(http.StatusOK, h.specSessionView(sess, true))
}

// specSessionView renders a session into the spec's list/watch item shape.
// withReady keeps 'ready' sessions visible (watch shows "Chờ host lên
// sóng"); the list view only ever passes live rows.
func (h *Handler) specSessionView(s *SpecSession, _ bool) gin.H {
	view := gin.H{
		"stream_key":   s.StreamKey,
		"hls_url":      h.svc.SpecHLSURL(s.StreamKey),
		"status":       s.Status,
		"title":        s.Title,
		"started_at":   s.StartedAt,
		"viewer_count": s.ViewerCount,
	}
	if s.Host != nil {
		view["host"] = gin.H{
			"id":        s.Host.ID,
			"username":  s.Host.Username,
			"full_name": s.Host.FullName,
			"avatar":    s.Host.Avatar,
		}
	}
	return view
}

// ───────────────────────── Chat ─────────────────────────

type specChatSendReq struct {
	StreamKey string `json:"stream_key" binding:"required"`
	Message   string `json:"message" binding:"required,max=500"`
}

func (h *Handler) specChatSend(c *gin.Context) {
	uid, ok := callerUUID(c)
	if !ok {
		c.Error(httpx.NewAuth("Thiếu Authorization token"))
		return
	}
	var req specChatSendReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	if strings.TrimSpace(req.Message) == "" {
		c.Error(httpx.NewValidation("Nội dung trống", nil))
		return
	}
	ctx := c.Request.Context()
	sess, err := h.repo.SpecByStreamKey(ctx, req.StreamKey)
	if err != nil || sess.Status == "offline" || sess.Status == "ended" {
		c.Error(httpx.NewValidation("Phiên live không tồn tại hoặc đã kết thúc", nil))
		return
	}
	isHost := sess.SellerID() == uid

	// Mute gate (host exempt).
	if !isHost && h.muteRepo != nil {
		if info, mErr := h.muteRepo.ActiveMute(ctx, sess.SessionUUID(), uid); mErr == nil && info != nil {
			c.Error(httpx.NewForbidden("Bạn đang bị tạm khoá chat"))
			return
		}
	}
	// Scam-link filter (host exempt — sellers paste their own shop URL).
	message := req.Message
	if !isHost {
		sanitized, blocked := FilterChatMessage(message)
		if blocked {
			h.autoMuteOnFilter(ctx, sess.SessionUUID(), uid, MuteReasonAutoScam, 60*time.Second)
			c.Error(httpx.NewValidation("Tin nhắn chứa nội dung không được phép", nil))
			return
		}
		message = sanitized
	}

	m, err := h.repo.InsertSpecChat(ctx, sess.SessionUUID(), req.StreamKey, uid, message, isHost)
	if err != nil {
		c.Error(httpx.NewInternal("send chat", err))
		return
	}
	// Fan out to any WS subscribers on the legacy hub + Redis.
	h.publishChatEvent(sess.SessionUUID(), &ChatMessage{
		ID: uuid.Nil, SessionID: sess.SessionUUID(), UserID: uid,
		Username: m.DisplayName, Message: m.Message, Type: "text",
	})
	c.JSON(http.StatusOK, m)
}

func (h *Handler) specChatHistory(c *gin.Context) {
	streamKey := strings.TrimSpace(c.Query("stream_key"))
	if streamKey == "" {
		c.Error(httpx.NewValidation("Thiếu stream_key", nil))
		return
	}
	sess, err := h.repo.SpecByStreamKey(c.Request.Context(), streamKey)
	if err != nil {
		c.Error(httpx.NewNotFound("Stream không tồn tại"))
		return
	}
	limit := 50
	if v := c.Query("limit"); v != "" {
		if n, e := strconv.Atoi(v); e == nil && n > 0 {
			limit = n
		}
	}
	var beforeSeq int64
	if v := c.Query("before_id"); v != "" {
		if n, e := strconv.ParseInt(v, 10, 64); e == nil && n > 0 {
			beforeSeq = n
		}
	}
	items, err := h.repo.ChatHistory(c.Request.Context(), sess.SessionUUID(), streamKey, limit, beforeSeq)
	if err != nil {
		c.Error(httpx.NewInternal("chat history", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"stream_key":    streamKey,
		"items":         items,
		"redis_channel": redisChannel(streamKey),
		"redis_enabled": false,
	})
}

// ───────────────────────── Gifts ─────────────────────────

func (h *Handler) specGifts(c *gin.Context) {
	items, err := h.repo.ListGiftCatalog(c.Request.Context())
	if err != nil {
		c.Error(httpx.NewInternal("list gifts", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"items": items})
}

type specGiftSendReq struct {
	StreamKey string `json:"stream_key" binding:"required"`
	GiftID    int64  `json:"gift_id" binding:"required"`
	Quantity  int    `json:"quantity"`
}

func (h *Handler) specGiftSend(c *gin.Context) {
	uid, ok := callerUUID(c)
	if !ok {
		c.Error(httpx.NewAuth("Thiếu Authorization token"))
		return
	}
	var req specGiftSendReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	if req.Quantity <= 0 {
		req.Quantity = 1
	}
	if req.Quantity > 99 {
		req.Quantity = 99
	}
	ctx := c.Request.Context()
	sess, err := h.repo.SpecByStreamKey(ctx, req.StreamKey)
	if err != nil {
		c.Error(httpx.NewNotFound("Stream không tồn tại"))
		return
	}
	if sess.Status != "live" {
		c.Error(httpx.NewValidation("Chỉ tặng quà khi stream đang live", nil))
		return
	}
	if sess.SellerID() == uid {
		c.Error(httpx.NewValidation("Không thể tự tặng quà cho chính mình", nil))
		return
	}
	gift, remaining, need, err := h.repo.SendGift(ctx, sess.SessionUUID(), req.StreamKey, uid, req.GiftID, req.Quantity)
	switch {
	case errors.Is(err, ErrGiftNotFound):
		c.Error(httpx.NewValidation("Quà không tồn tại", nil))
		return
	case errors.Is(err, ErrNoLoyaltyAccount):
		c.Error(httpx.NewValidation("Bạn chưa có điểm tích lũy", nil))
		return
	case errors.Is(err, ErrInsufficientPoint):
		c.Error(httpx.NewValidation("Không đủ điểm. Cần "+strconv.Itoa(need)+" điểm.", nil))
		return
	case err != nil:
		c.Error(httpx.NewInternal("send gift", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{
		"gift":             gift,
		"points_remaining": remaining,
		"redis_channel":    redisChannel(req.StreamKey),
	})
}

func (h *Handler) specGiftsRecent(c *gin.Context) {
	streamKey := strings.TrimSpace(c.Query("stream_key"))
	if streamKey == "" {
		c.Error(httpx.NewValidation("Thiếu stream_key", nil))
		return
	}
	sess, err := h.repo.SpecByStreamKey(c.Request.Context(), streamKey)
	if err != nil {
		c.Error(httpx.NewNotFound("Stream không tồn tại"))
		return
	}
	limit := 30
	if v := c.Query("limit"); v != "" {
		if n, e := strconv.Atoi(v); e == nil && n > 0 {
			limit = n
		}
	}
	items, err := h.repo.RecentGifts(c.Request.Context(), sess.SessionUUID(), limit)
	if err != nil {
		c.Error(httpx.NewInternal("recent gifts", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"stream_key": streamKey, "items": items})
}
