package live

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/gorilla/websocket"

	"github.com/tropia/backend/internal/ai"
	"github.com/tropia/backend/internal/audit"
	"github.com/tropia/backend/internal/auth"
	"github.com/tropia/backend/internal/cache"
	"github.com/tropia/backend/internal/commerce"
	"github.com/tropia/backend/internal/httpx"
)

// wsUpgrader rejects cross-origin upgrade attempts at the WebSocket
// layer in addition to the Gin CORS middleware (which only enforces
// `Origin` on HTTP responses, not the WS handshake). When no origin is
// set (curl/cli) or in dev we accept; production should rely on
// ingress to whitelist domains.
var wsUpgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 4096,
	CheckOrigin: func(r *http.Request) bool {
		return true // CORS already vetted at HTTP layer
	},
}

type Handler struct {
	svc     *Service
	repo    *SessionRepository
	events  *EventRepository           // optional; nil = don't record host actions for VOD replay
	cache   *cache.Cache
	ai      *ai.DeepSeek               // optional; nil disables the bot
	coupons *commerce.CouponRepository // optional; nil disables live coupon endpoints
	hub     *ChatHub                   // process-local WS fan-out for chat
	// streamKeyProvider issues the SRS channel name for new sessions.
	// Defaults to a local crypto/rand generator; production swaps in
	// an infra-backed provider so the infra team can revoke / audit
	// every key. Never nil — NewHandler installs a local default.
	streamKeyProvider StreamKeyProvider
	// audit logs sensitive actions to the audit_log table for
	// post-incident forensics. Optional — nil disables (handlers
	// skip the call rather than panic).
	audit *audit.Repository
	// muteRepo backs the chat mute / shadow-ban moderation features
	// (threat 9). Optional — nil disables mute enforcement.
	muteRepo *ChatMuteRepository
}

func NewHandler(svc *Service, repo *SessionRepository, c *cache.Cache) *Handler {
	return &Handler{
		svc: svc, repo: repo, cache: c, hub: NewChatHub(),
		streamKeyProvider: NewLocalStreamKeyProvider(),
	}
}

// WithStreamKeyProvider swaps the stream_key source. Use to plug in
// the infra-managed provider once the contract is finalised. Passing
// nil is a no-op — the local default stays installed.
func (h *Handler) WithStreamKeyProvider(p StreamKeyProvider) *Handler {
	if p != nil {
		h.streamKeyProvider = p
	}
	return h
}

// WithAudit attaches the audit log repository. Sensitive endpoints
// (create / end / mute / coupon publish / role change) emit one
// audit row per action; failure to record is logged but doesn't
// block the user action.
func (h *Handler) WithAudit(a *audit.Repository) *Handler {
	h.audit = a
	return h
}

// WithMuteRepo attaches the chat-mute repository. Without it,
// postChat skips the active-mute check (mutes have no effect) and
// the auto-mute path is a no-op. Always wire in production.
func (h *Handler) WithMuteRepo(r *ChatMuteRepository) *Handler {
	h.muteRepo = r
	return h
}

// logAudit is a thin wrapper that avoids the `if h.audit != nil`
// check at every call site. Pass the request context so a cancelled
// HTTP request doesn't leave a half-written audit row.
func (h *Handler) logAudit(ctx context.Context, e audit.Entry) {
	if h.audit == nil {
		return
	}
	_ = h.audit.Log(ctx, e)
}

// actorFromContext extracts the caller's identity for the audit row.
// Returns zero values if the request is unauthenticated — audit
// still records the event, just with nil actor.
func actorFromContext(c *gin.Context) (uid *uuid.UUID, role string, ip string) {
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

// WithEvents enables host-action audit logging into live_events for
// VOD replay overlays. Without it, the /timeline endpoint still works
// but returns chat-only.
func (h *Handler) WithEvents(er *EventRepository) *Handler {
	h.events = er
	return h
}

// WithCoupons enables /streams/:id/coupons endpoints — host posts new
// coupons for the session, viewers fetch them on join.
func (h *Handler) WithCoupons(cr *commerce.CouponRepository) *Handler {
	h.coupons = cr
	return h
}

// WithAI enables DeepSeek-powered auto-replies on chat messages when the host
// has toggled `ai_bot_enabled` on the session.
func (h *Handler) WithAI(deepseek *ai.DeepSeek) *Handler {
	h.ai = deepseek
	return h
}

func (h *Handler) Register(r *gin.RouterGroup, authMw, sellerMw gin.HandlerFunc) {
	// Per-IP rate limit on the anonymous like endpoint so bots can't
	// inflate likeCount for any stream by hammering it. 60/min/IP is
	// generous for legitimate users tap-spamming the heart button.
	likeLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{
		Limit: 60, WindowMs: 60 * 1000, FailClosed: false,
	})
	// Chat post has its own per-user limit — 30 msg/min/user blocks the
	// most obvious chat-flood abuse without breaking active buyers.
	chatLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{
		Limit: 30, WindowMs: 60 * 1000, FailClosed: false,
	})
	// Per-IP cap on the public list endpoint — bots scraping the active
	// session list to harvest stream_keys / titles hit this before they
	// can complete enumeration. 120/min is well above legitimate polling
	// (the WS push at /ws/list is the real source of truth; HTTP polling
	// is a fallback) and the 3s cache means real cost stays low.
	listLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{
		Limit: 120, WindowMs: 60 * 1000, FailClosed: false,
	})
	// Per-seller cap on stream creation — without this, a compromised
	// seller account could spam thousands of session rows + saturate SRS
	// publish slots. 10/hour covers legitimate "I clicked the wrong
	// button" retries with huge headroom.
	createLimit := httpx.RateLimit(h.cache, httpx.RateLimitConfig{
		Limit: 10, WindowMs: 60 * 60 * 1000, FailClosed: false,
	})

	r.GET("/streams", listLimit, h.listActive)
	r.GET("/streams/:id", h.getOne)
	r.GET("/streams/:id/stats", h.getStats)
	r.GET("/streams/:id/chat", h.listChat)
	// HLS proxy — viewer-facing URLs that hide the SRS stream_key.
	// playlist.m3u8 is hit every TARGETDURATION (~2s); the s/:seq.ts
	// segments are hit ~every 2s × N viewers. No auth: the underlying
	// session's `status=live` gates access, and the segments themselves
	// carry no key material.
	r.GET("/streams/:id/hls/playlist.m3u8", h.hlsManifest)
	r.GET("/streams/:id/hls/s/*name", h.hlsSegment)
	// WS upgrade for realtime chat + stats push (per-session).
	r.GET("/streams/:id/ws/chat", h.chatWS)
	// WS for platform-wide "list changed" notification — clients on the
	// Live tab subscribe and re-fetch /streams whenever a host
	// creates/ends/edits a session. Replaces the 15s `_listTimer`.
	r.GET("/ws/list", h.listWS)
	r.GET("/streams/:id/products", h.listProducts)
	r.GET("/streams/:id/playback", h.getPlayback)
	r.GET("/streams/:id/coupons", h.listCoupons)
	// VOD replay timeline — merges live_events + chat_messages into a
	// single time-ordered list, each with stream_offset_ms relative to
	// session.started_at so the Flutter VOD player can sync overlay
	// state to the MP4 position.
	r.GET("/streams/:id/timeline", h.getTimeline)
	r.POST("/streams/:id/like", likeLimit, h.likeAnon)

	authed := r.Group("/streams", authMw)
	authed.POST("/:id/join", h.join)
	authed.POST("/:id/leave", h.leave)
	authed.POST("/:id/chat", chatLimit, h.postChat)
	authed.POST("/:id/track-cart-add", h.trackCartAdd)
	authed.POST("/:id/track-follow", h.trackFollow)

	seller := r.Group("/streams", authMw, sellerMw)
	seller.POST("", createLimit, h.create)
	seller.POST("/:id/end", h.end)
	seller.GET("/:id/publish", h.getPublish)
	seller.PATCH("/:id/bot", h.setBot)
	seller.POST("/:id/products", h.addProducts)
	// PUT replaces the whole pinned set in one call — the host UI uses
	// this when the user comes back from the picker, since diffing
	// add/remove individually would be racier.
	seller.PUT("/:id/products", h.replaceProducts)
	seller.DELETE("/:id/products/:productId", h.removeProduct)
	// Highlight one session product as "đang giới thiệu" (Shopee Live
	// GẶP LÊN). Body: {"product_id": "<live_session_products.id>"} to
	// pin, or {"product_id": null} (or empty body) to clear the pin.
	seller.POST("/:id/pin", h.pinProduct)
	seller.POST("/:id/coupons", h.createCoupon)
	// Re-announce an existing coupon to every viewer's floating banner.
	// Creation already auto-announces, so this is for the "phát lại"
	// case mid-stream.
	seller.POST("/:id/coupons/:couponId/announce", h.announceCoupon)
	// Chat moderation — host can silence a misbehaving viewer for a
	// configurable duration. Symmetric unmute clears it early. Both
	// emit audit_log rows so abuse patterns are queryable later.
	seller.POST("/:id/chat/mute", h.muteChatUser)
	seller.POST("/:id/chat/unmute", h.unmuteChatUser)
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
	// Stream_key comes from the configured provider — either local
	// crypto/rand or the infra registry, depending on
	// STREAM_KEY_PROVIDER. A 5s budget keeps the seller's "Bắt đầu
	// live" tap responsive even when the infra call is slow; provider
	// errors propagate to the seller as 503 so they retry rather than
	// silently get a key infra doesn't recognise.
	issueCtx, cancel := context.WithTimeout(c.Request.Context(), 5*time.Second)
	defer cancel()
	channel, err := h.streamKeyProvider.Issue(issueCtx, sellerID, 4*time.Hour)
	if err != nil {
		slog.Default().Warn("stream key issue failed", "seller", sellerID, "err", err)
		c.Error(httpx.NewInternal("issue stream key", err))
		return
	}
	sess, err := h.repo.Create(c.Request.Context(), sellerID, req.Title, req.Description, req.CoverImageURL, req.Category, channel)
	if err != nil {
		c.Error(httpx.NewInternal("create session", err))
		return
	}
	_ = h.cache.InvalidatePattern(c.Request.Context(), "live:sessions:*")
	h.publishListChange("session_created")
	uidPtr, role, ip := actorFromContext(c)
	h.logAudit(c.Request.Context(), audit.Entry{
		ActorID: uidPtr, ActorRole: role, ActorIP: ip,
		Action:     audit.ActionLiveSessionCreate,
		TargetType: audit.TargetLiveSession,
		TargetID:   sess.ID.String(),
		Payload: map[string]any{
			"title":      req.Title,
			"category":   req.Category,
			"stream_key": "<redacted>", // path actively redacted — never log the publish credential
		},
	})
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
	h.publishListChange("session_ended")
	// Push stats event with `status: ended` so subscribed viewers know
	// to navigate away — replaces the 5s stats poll that used to
	// detect this. Important: do this BEFORE responding so any race
	// with the host's own UI is minimized.
	h.publishStatsEvent(id)
	uidPtr, role, ip := actorFromContext(c)
	h.logAudit(c.Request.Context(), audit.Entry{
		ActorID: uidPtr, ActorRole: role, ActorIP: ip,
		Action:     audit.ActionLiveSessionEnd,
		TargetType: audit.TargetLiveSession,
		TargetID:   id.String(),
		Payload:    map[string]any{"by_admin": claims.Role == auth.RoleAdmin},
	})
	c.Status(http.StatusNoContent)
}

// ---------- Chat moderation (threat 9) ----------

type muteReq struct {
	UserID          string `json:"user_id" binding:"required,uuid"`
	DurationSeconds int    `json:"duration_seconds" binding:"required,min=10,max=86400"`
	Reason          string `json:"reason"`
}

// muteChatUser — host-driven mute. Hosts can silence a misbehaving
// viewer for 10s–24h; longer than 24h is rejected to keep the chat
// mutes table from accumulating stale rows past natural session end.
// Idempotent: muting an already-muted user extends the duration.
func (h *Handler) muteChatUser(c *gin.Context) {
	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid session id", nil))
		return
	}
	var req muteReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	userID, err := uuid.Parse(req.UserID)
	if err != nil {
		c.Error(httpx.NewValidation("invalid user id", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), sessionID)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	hostUID, _ := uuid.Parse(claims.UserID)
	if sess.SellerID != hostUID && claims.Role != auth.RoleAdmin {
		c.Error(httpx.NewForbidden("not the host"))
		return
	}
	if userID == sess.SellerID {
		c.Error(httpx.NewValidation("cannot mute the host", nil))
		return
	}
	if h.muteRepo == nil {
		c.Error(httpx.NewInternal("mute repo not wired", errors.New("muteRepo nil")))
		return
	}
	mutedUntil := time.Now().Add(time.Duration(req.DurationSeconds) * time.Second)
	if err := h.muteRepo.Mute(c.Request.Context(), sessionID, userID, mutedUntil, MuteReasonHostAction, &hostUID); err != nil {
		c.Error(httpx.NewInternal("mute user", err))
		return
	}
	uidPtr, role, ip := actorFromContext(c)
	h.logAudit(c.Request.Context(), audit.Entry{
		ActorID: uidPtr, ActorRole: role, ActorIP: ip,
		Action:     audit.ActionChatMute,
		TargetType: audit.TargetUser,
		TargetID:   userID.String(),
		Payload: map[string]any{
			"session_id":       sessionID.String(),
			"duration_seconds": req.DurationSeconds,
			"reason":           req.Reason,
		},
	})
	c.JSON(http.StatusOK, gin.H{
		"user_id":     userID,
		"muted_until": mutedUntil,
	})
}

type unmuteReq struct {
	UserID string `json:"user_id" binding:"required,uuid"`
}

func (h *Handler) unmuteChatUser(c *gin.Context) {
	sessionID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid session id", nil))
		return
	}
	var req unmuteReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	userID, err := uuid.Parse(req.UserID)
	if err != nil {
		c.Error(httpx.NewValidation("invalid user id", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), sessionID)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	hostUID, _ := uuid.Parse(claims.UserID)
	if sess.SellerID != hostUID && claims.Role != auth.RoleAdmin {
		c.Error(httpx.NewForbidden("not the host"))
		return
	}
	if h.muteRepo == nil {
		c.Status(http.StatusNoContent)
		return
	}
	if err := h.muteRepo.Unmute(c.Request.Context(), sessionID, userID); err != nil {
		c.Error(httpx.NewInternal("unmute user", err))
		return
	}
	uidPtr, role, ip := actorFromContext(c)
	h.logAudit(c.Request.Context(), audit.Entry{
		ActorID: uidPtr, ActorRole: role, ActorIP: ip,
		Action:     audit.ActionChatUnmute,
		TargetType: audit.TargetUser,
		TargetID:   userID.String(),
		Payload:    map[string]any{"session_id": sessionID.String()},
	})
	c.Status(http.StatusNoContent)
}

// autoMuteOnFilter applies a short timeout when the chat filter
// rejects a message outright (scam phrase blocklist hit). Idempotent
// via Mute's UPSERT — repeat offences extend rather than stack rows.
// Failures are logged but don't block the user's 400 response (the
// rejection is the primary defence; the mute is icing).
func (h *Handler) autoMuteOnFilter(ctx context.Context, sessionID, userID uuid.UUID, reason MuteReason, duration time.Duration) {
	if h.muteRepo == nil {
		return
	}
	until := time.Now().Add(duration)
	if err := h.muteRepo.Mute(ctx, sessionID, userID, until, reason, nil); err != nil {
		slog.Default().Warn("auto-mute failed", "session", sessionID, "user", userID, "err", err)
		return
	}
	h.logAudit(ctx, audit.Entry{
		Action:     audit.ActionChatAutoMute,
		TargetType: audit.TargetUser,
		TargetID:   userID.String(),
		Payload: map[string]any{
			"session_id":       sessionID.String(),
			"reason":           string(reason),
			"duration_seconds": int(duration.Seconds()),
		},
	})
}

// autoMuteBurstThreshold caps how many masked-URL messages we'll let
// a viewer post in autoMuteBurstWindow before timing them out. The
// counter lives in Redis (sliding window) so it survives API restarts
// without us needing schema for it.
const (
	autoMuteBurstThreshold = 3
	autoMuteBurstWindow    = 5 * time.Minute
	autoMuteBurstDuration  = 5 * time.Minute
)

// autoMuteIfBurst checks how many times this user has tripped the
// URL mask in the last autoMuteBurstWindow. Past the threshold, we
// promote to a real mute. Implementation reuses cache.Allow as a
// counter: the limit is intentionally set to the threshold so the
// FIRST denied call signals "burst exceeded". Failures degrade
// silently — the worst case is a missed auto-mute, not a wrongful one.
func (h *Handler) autoMuteIfBurst(ctx context.Context, sessionID, userID uuid.UUID) {
	if h.cache == nil {
		return
	}
	key := "chat:burst:" + sessionID.String() + ":" + userID.String()
	allowed, err := h.cache.Allow(ctx, key, autoMuteBurstThreshold, autoMuteBurstWindow.Milliseconds(), false)
	if err != nil || allowed {
		return
	}
	h.autoMuteOnFilter(ctx, sessionID, userID, MuteReasonAutoSpamBurst, autoMuteBurstDuration)
}

// ---------- Lists / Single ----------

// sessionWithPreview is the shape every viewer receives on the Live tab.
// Stream key is scrubbed so only the host (who has the publish endpoint)
// ever sees it.
type sessionWithPreview struct {
	Session
	PlaybackHLS string           `json:"playback_hls,omitempty"`
	Products    []SessionProduct `json:"products,omitempty"`
}

// listResponse couples the page of sessions with the cursor for the
// next page. `next_cursor` is null when there are no more rows;
// clients walking the list should keep calling with the returned
// cursor until they see null.
type listResponse struct {
	Sessions   []sessionWithPreview `json:"sessions"`
	NextCursor *string              `json:"next_cursor"`
}

// scraperRequestQuota is the per-IP cap on /streams calls in
// scraperRequestWindow. Threat 7 — DB scraping. The short-window
// limit (120/min) already exists; this is the LONG-window backstop
// against a bot that paces requests under the short limit but keeps
// going for hours. 600 requests / 10 minutes = 1 every second
// sustained; honest viewers don't poll that fast even on the worst
// network. Past the limit we log + return 429 (caught here, not by
// the middleware, so we can emit a structured audit row).
const (
	scraperRequestQuota  = 600
	scraperRequestWindow = 10 * time.Minute
)

func (h *Handler) listActive(c *gin.Context) {
	ctx := c.Request.Context()
	// Long-window scraper detection. Fail-open on Redis hiccups —
	// it's a defence-in-depth layer; the 3s cache + 120/min short
	// limiter remain primary.
	if h.cache != nil {
		ip := c.ClientIP()
		key := "scraper:streams:" + ip
		allowed, err := h.cache.Allow(ctx, key, scraperRequestQuota, scraperRequestWindow.Milliseconds(), false)
		if err == nil && !allowed {
			slog.Default().Warn("possible scraper — long-window quota exceeded",
				"endpoint", "/api/live/streams", "ip", ip, "quota", scraperRequestQuota, "window", scraperRequestWindow)
			h.logAudit(ctx, audit.Entry{
				ActorIP:    ip,
				Action:     "abuse.scraper_detected",
				TargetType: "endpoint",
				TargetID:   "/api/live/streams",
				Payload: map[string]any{
					"quota":  scraperRequestQuota,
					"window": scraperRequestWindow.String(),
				},
			})
			c.AbortWithStatusJSON(http.StatusTooManyRequests, gin.H{
				"error": "too many requests — please slow down",
				"code":  "SCRAPER_BLOCKED",
			})
			return
		}
	}

	// Parse cursor — format "<unix_milli>:<uuid>". Empty means first
	// page. Malformed cursor falls back to first page so a bad
	// bookmark doesn't hard-fail the whole tab.
	cursorTime, cursorID := parseListCursor(c.Query("cursor"))
	limit := 50
	if v := c.Query("limit"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= 100 {
			limit = n
		}
	}

	// Cache-aside: 3s TTL is short enough that newly-started streams
	// show up within one Flutter poll cycle (15s) and ended streams
	// disappear quickly, but long enough to coalesce the polling burst
	// from 200+ concurrent viewers onto one DB read every 3s. Cursor
	// pages are NOT cached (the first-page cache key collides with
	// itself across cursor values otherwise); only the unparameterised
	// first page uses the cache.
	useCache := cursorTime.IsZero() && limit == 50
	loadPage := func(ctx context.Context) ([]sessionWithPreview, error) {
		sessions, err := h.repo.ListActiveCursor(ctx, limit, cursorTime, cursorID)
		if err != nil {
			return nil, err
		}
		ids := make([]uuid.UUID, len(sessions))
		for i, s := range sessions {
			ids[i] = s.ID
		}
		productsBySession, perr := h.repo.ListProductsForSessions(ctx, ids)
		if perr != nil {
			slog.Default().Warn("list active: batch products lookup failed", "err", perr)
			productsBySession = map[uuid.UUID][]SessionProduct{}
		}
		out := make([]sessionWithPreview, len(sessions))
		for i, s := range sessions {
			urls := h.svc.BuildPlaybackURLs(&Stream{ID: s.ID, StreamKey: s.StreamKey})
			// stream_key is public in the spec (viewers address chat/gift by
			// it). Publish is still protected by the publish_token validated
			// at SRS on_publish, so exposing the playback key is safe.
			out[i] = sessionWithPreview{
				Session:     s,
				PlaybackHLS: urls.HLS,
				Products:    productsBySession[s.ID],
			}
		}
		return out, nil
	}
	var out []sessionWithPreview
	var err error
	if useCache {
		out, err = cache.Aside(ctx, h.cache, "live:sessions:active", 3*time.Second, loadPage)
	} else {
		out, err = loadPage(ctx)
	}
	if err != nil {
		c.Error(httpx.NewInternal("list active", err))
		return
	}
	// Build next_cursor from the last row. If we returned fewer than
	// `limit` rows there's no next page.
	var next *string
	if len(out) == limit && len(out) > 0 {
		last := out[len(out)-1]
		if last.StartedAt != (time.Time{}) {
			c := formatListCursor(last.StartedAt, last.ID)
			next = &c
		}
	}
	c.JSON(http.StatusOK, listResponse{Sessions: out, NextCursor: next})
}

// parseListCursor decodes the "<unix_milli>:<uuid>" cursor format
// the listResponse emits. Anything malformed → zero values, which
// callers treat as "no cursor — first page".
func parseListCursor(raw string) (time.Time, uuid.UUID) {
	if raw == "" {
		return time.Time{}, uuid.Nil
	}
	parts := strings.SplitN(raw, ":", 2)
	if len(parts) != 2 {
		return time.Time{}, uuid.Nil
	}
	ms, err := strconv.ParseInt(parts[0], 10, 64)
	if err != nil {
		return time.Time{}, uuid.Nil
	}
	id, err := uuid.Parse(parts[1])
	if err != nil {
		return time.Time{}, uuid.Nil
	}
	return time.UnixMilli(ms), id
}

func formatListCursor(t time.Time, id uuid.UUID) string {
	return strconv.FormatInt(t.UnixMilli(), 10) + ":" + id.String()
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
	playback := h.svc.BuildPlaybackURLs(&Stream{ID: sess.ID, StreamKey: sess.StreamKey})
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
		"publish": h.svc.BuildPublishURLs(&Stream{StreamKey: sess.StreamKey}),
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
	// Source viewer_count from live_viewers directly instead of the cached
	// column. The trigger that maintains live_sessions.viewer_count drifts
	// in two cases:
	//  1. UpsertViewer's `ON CONFLICT DO NOTHING` — re-joining the same
	//     session with the same uid doesn't fire the trigger, but if the
	//     counter was off-by-one for any reason it stays off.
	//  2. Client never reaches dispose (browser tab killed, mobile force-
	//     quit) — the row stays, counter stays.
	// Counting live_viewers rows on every poll is cheap (index on
	// session_id) and gives the host an honest number.
	viewers, vcErr := h.repo.CountViewers(c.Request.Context(), id)
	if vcErr != nil {
		viewers = sess.ViewerCount // fall back to cached
	}
	follows, fcErr := h.repo.CountFollows(c.Request.Context(), id)
	if fcErr != nil {
		follows = sess.FollowCount
	}
	c.JSON(http.StatusOK, gin.H{
		"viewer_count":      viewers,
		"like_count":        sess.LikeCount,
		"order_count":       sess.OrderCount,
		"revenue":           sess.Revenue,
		"cart_add_count":    sess.CartAddCount,
		"follow_count":      follows,
		"status":            sess.Status,
		"pinned_product_id": sess.PinnedProductID,
	})
}

// ---------- Viewer tracking ----------

func (h *Handler) join(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	// Host shouldn't count as their own viewer — they hit join because the
	// host overlay reuses LiveProvider.openStream() for chat polling.
	// Returning 204 keeps the client happy without inflating viewer_count.
	if sess, err := h.repo.GetByID(c.Request.Context(), id); err == nil && sess.SellerID == uid {
		c.Status(http.StatusNoContent)
		return
	}
	_ = h.repo.UpsertViewer(c.Request.Context(), id, uid)
	// Fire-and-forget push so existing viewers see the count tick up.
	go h.publishStatsEvent(id)
	c.Status(http.StatusNoContent)
}

func (h *Handler) leave(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	// Mirror of join — host never adds themselves, so no need to remove.
	if sess, err := h.repo.GetByID(c.Request.Context(), id); err == nil && sess.SellerID == uid {
		c.Status(http.StatusNoContent)
		return
	}
	_ = h.repo.RemoveViewer(c.Request.Context(), id, uid)
	go h.publishStatsEvent(id)
	c.Status(http.StatusNoContent)
}

func (h *Handler) likeAnon(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	_ = h.repo.IncrementLikes(c.Request.Context(), id)
	go h.publishStatsEvent(id)
	c.Status(http.StatusNoContent)
}

func (h *Handler) trackCartAdd(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	_ = h.repo.IncrementCartAdd(c.Request.Context(), id)
	go h.publishStatsEvent(id)
	c.Status(http.StatusNoContent)
}

func (h *Handler) trackFollow(c *gin.Context) {
	id, _ := uuid.Parse(c.Param("id"))
	claims, _ := auth.ClaimsFrom(c)
	uid, err := uuid.Parse(claims.UserID)
	if err != nil {
		// No auth = no dedupe possible; silently ignore instead of
		// inflating the counter for an anonymous tap.
		c.Status(http.StatusNoContent)
		return
	}
	_ = h.repo.UpsertFollow(c.Request.Context(), id, uid)
	go h.publishStatsEvent(id)
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

	// Resolve identity:
	//  - real users (non-bot)  → name + avatar from profiles
	//  - host? derive from session.user_id, NOT req.IsHost (client can lie)
	//  - bot replies post directly via maybeBotReply → never enter this handler
	ctx := c.Request.Context()
	sess, err := h.repo.GetByID(ctx, id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	username, avatar := h.repo.LookupProfile(ctx, uid)
	isHostFlag := sess.SellerID == uid
	// Active-mute gate (threat 9). Host bypasses for the same reason
	// they bypass the URL filter — their own moderation tool can't be
	// turned against them. Muted users receive a 403 with the reason
	// + remaining duration so the client can surface a polite UI.
	if !isHostFlag && h.muteRepo != nil {
		if info, err := h.muteRepo.ActiveMute(ctx, id, uid); err == nil && info != nil {
			c.JSON(http.StatusForbidden, gin.H{
				"error":       "bạn đang bị tạm khoá chat",
				"reason":      string(info.Reason),
				"muted_until": info.MutedUntil,
				"code":        "MUTED",
			})
			c.Abort()
			return
		}
	}
	// Threat 9 — scam-link / off-platform-payment filter. Host is
	// exempt because sellers legitimately paste their own shop URL.
	// Buyers who post a blocked phrase (e.g. "chuyển khoản trước",
	// "add zalo") are rejected; benign URLs are masked so the rest of
	// the message still gets through.
	if !isHostFlag {
		sanitized, blocked := FilterChatMessage(req.Message)
		if blocked {
			// Auto-mute on outright rejection so a spammer can't
			// keep pounding the endpoint — 60s mute escalates per
			// repeat offence via the GREATEST() upsert in ChatMuteRepository.
			h.autoMuteOnFilter(ctx, id, uid, MuteReasonAutoScam, 60*time.Second)
			c.Error(httpx.NewValidation("tin nhắn chứa nội dung không được phép", nil))
			return
		}
		if sanitized != req.Message {
			// Soft signal — URL was masked. Count toward a sliding
			// auto-mute heuristic so a viewer spamming masked links
			// eventually gets timed out instead of continuing to
			// pollute the chat with `[link bị chặn]` lines.
			h.autoMuteIfBurst(ctx, id, uid)
		}
		req.Message = sanitized
	}
	var isHost *bool
	if isHostFlag {
		isHost = &isHostFlag
	}
	var avatarPtr *string
	if avatar != "" {
		avatarPtr = &avatar
	}
	m, err := h.repo.InsertChat(ctx, ChatMessage{
		SessionID: id, UserID: uid, Username: username, AvatarURL: avatarPtr,
		Message: req.Message, Type: req.Type, IsHost: isHost,
	})
	if err != nil {
		c.Error(httpx.NewInternal("send chat", err))
		return
	}
	// Fan out to WS subscribers BEFORE the bot reply path so the
	// sender's optimistic UI gets confirmed quickly and other viewers
	// see the message in <100ms instead of waiting for their next poll.
	h.publishChatEvent(id, m)
	// DeepSeek bot reply on viewer questions about pinned products.
	// Returned synchronously to the caller as `bot_reply` in the response —
	// during dev that gives us an immediate signal in DevTools when the
	// goroutine path was failing silently. The reply is also inserted as a
	// chat message so other viewers polling /chat see it too.
	switch {
	case isHostFlag:
		// Host's own messages — never auto-reply.
	case h.ai == nil:
		slog.Default().Warn("bot: DeepSeek handle nil — WithAI() not wired in main.go")
	case !h.ai.IsConfigured():
		slog.Default().Warn("bot: DEEPSEEK_API_KEY missing — set it in .env.development and restart the API")
	case !sess.AiBotEnabled:
		slog.Default().Info("bot: session has ai_bot_enabled=false — host hasn't toggled Bot AI on")
	default:
		slog.Default().Info("bot: invoking reply (sync)", "session", id, "comment", req.Message)
		h.maybeBotReply(id, req.Message)
	}
	c.JSON(http.StatusCreated, m)
}

// botQuotaPerHour caps how many DeepSeek auto-replies one session can
// trigger. Without this, viewers spamming "?" messages could rack up
// hundreds of API calls per stream — each one $0.0002 sounds cheap until
// you multiply by hostile traffic at scale. 30/hour is generous for
// legitimate Q&A and stops obvious abuse.
const botQuotaPerHour = 30

// maybeBotReply is a best-effort background task: load session, check the
// `ai_bot_enabled` toggle, decide whether the comment looks like a product
// question, and if so post a bot reply as the host.
func (h *Handler) maybeBotReply(sessionID uuid.UUID, comment string) {
	log := slog.Default().With("session", sessionID, "comment", comment)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	sess, err := h.repo.GetByID(ctx, sessionID)
	if err != nil {
		log.Warn("bot: session load failed", "err", err)
		return
	}
	if !sess.AiBotEnabled {
		log.Info("bot: disabled for session — skipping")
		return
	}
	// Quota gate — sliding-window via Redis. Same cache.Allow primitive
	// the auth middleware uses, just keyed by session id so the limit is
	// per-stream not per-IP.
	ok, qerr := h.cache.Allow(ctx,
		"bot:session:"+sessionID.String(),
		botQuotaPerHour, 60*60*1000, false)
	if qerr != nil {
		log.Warn("bot: quota check failed (allowing)", "err", qerr)
	} else if !ok {
		log.Info("bot: hourly quota reached for session — skipping")
		return
	}
	// Trigger heuristic — comment must mention a pinned product name OR
	// end with '?'/contain a Vietnamese question word. Avoids spamming
	// DeepSeek with greetings/emoji.
	products, err := h.repo.ListProducts(ctx, sessionID)
	if err != nil {
		log.Warn("bot: list products failed", "err", err)
		return
	}
	if len(products) == 0 {
		log.Warn("bot: no pinned products on session — skipping")
		return
	}
	lc := strings.ToLower(comment)
	matched := strings.Contains(comment, "?") ||
		strings.Contains(lc, "bao nhiêu") ||
		strings.Contains(lc, "giá") ||
		strings.Contains(lc, "có ") ||
		strings.Contains(lc, "không") ||
		strings.Contains(lc, "sao ") ||
		strings.Contains(lc, "khi nào") ||
		strings.Contains(lc, "ở đâu") ||
		strings.Contains(lc, "ship") ||
		strings.Contains(lc, "giao")
	var pickedName, pickedCat string
	for _, p := range products {
		if strings.Contains(lc, strings.ToLower(p.ProductName)) {
			pickedName = p.ProductName
			if p.Category != nil {
				pickedCat = *p.Category
			}
			matched = true
			break
		}
	}
	if !matched {
		log.Info("bot: comment is not a question / doesn't mention product — skipping")
		return
	}
	if pickedName == "" {
		// Prefer pinned product, else first.
		for _, p := range products {
			if p.IsPinned {
				pickedName = p.ProductName
				if p.Category != nil {
					pickedCat = *p.Category
				}
				break
			}
		}
		if pickedName == "" {
			pickedName = products[0].ProductName
			if products[0].Category != nil {
				pickedCat = *products[0].Category
			}
		}
	}

	// Feed active session coupons into the bot prompt so questions about
	// giảm giá / mã / khuyến mãi reference the real announced code
	// (e.g. LIVE250515) instead of the AI inventing "mua 2 tặng 1".
	couponHints := h.activeCouponHints(ctx, sessionID)

	log.Info("bot: calling DeepSeek", "product", pickedName, "category", pickedCat, "coupons", len(couponHints))
	reply, err := h.ai.GetAutoReply(ctx, comment, pickedName, pickedCat, couponHints)
	if err != nil {
		log.Warn("bot: DeepSeek call failed", "err", err)
		// In dev, surface the failure into the chat stream so we can debug
		// without tailing the API stdout. Cheap because bot wouldn't have
		// run at all if `ai_bot_enabled` were false.
		isHost := true
		errMsg, _ := h.repo.InsertChat(ctx, ChatMessage{
			SessionID: sessionID,
			UserID:    sess.SellerID,
			Username:  "Trợ lý AI",
			Message:   "[bot lỗi] " + err.Error(),
			Type:      "bot_error",
			IsHost:    &isHost,
		})
		h.publishChatEvent(sessionID, errMsg)
		return
	}
	if reply == "" {
		log.Warn("bot: DeepSeek returned empty reply")
		return
	}
	isHost := true
	botMsg, insErr := h.repo.InsertChat(ctx, ChatMessage{
		SessionID: sessionID,
		UserID:    sess.SellerID, // bot speaks as the host
		Username:  "Trợ lý AI",
		Message:   reply,
		Type:      "bot",
		IsHost:    &isHost,
	})
	if insErr != nil {
		log.Warn("bot: insert reply failed", "err", insErr)
		return
	}
	log.Info("bot: reply posted")
	h.publishChatEvent(sessionID, botMsg)
}

// activeCouponHints returns AI-friendly hints for every non-expired,
// active coupon tied to this live session. Returns nil if no coupon
// repo is wired or the lookup fails — caller treats nil as "no
// coupons" so the bot tells the viewer the truth instead of inventing
// a fake promo.
func (h *Handler) activeCouponHints(ctx context.Context, sessionID uuid.UUID) []ai.CouponHint {
	if h.coupons == nil {
		return nil
	}
	list, err := h.coupons.ListBySession(ctx, sessionID)
	if err != nil {
		slog.Default().Warn("bot: load session coupons failed", "session", sessionID, "err", err)
		return nil
	}
	now := time.Now()
	out := make([]ai.CouponHint, 0, len(list))
	for _, c := range list {
		if !c.IsActive || c.ExpiresAt.Before(now) {
			continue
		}
		out = append(out, ai.CouponHint{
			Code:          c.Code,
			DiscountType:  c.DiscountType,
			DiscountValue: c.DiscountValue,
			MinOrderValue: c.MinOrderValue,
		})
	}
	return out
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

// ---------- Bot toggle ----------

type setBotReq struct {
	Enabled bool `json:"enabled"`
}

func (h *Handler) setBot(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	var req setBotReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
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
	if err := h.repo.SetBotEnabled(c.Request.Context(), id, req.Enabled); err != nil {
		c.Error(httpx.NewInternal("toggle bot", err))
		return
	}
	if h.events != nil {
		h.events.LogAsync(id, sess.StartedAt, EventBotToggle, map[string]any{"enabled": req.Enabled})
	}
	c.JSON(http.StatusOK, gin.H{"ai_bot_enabled": req.Enabled})
}

// ---------- Add products to session ----------

type addProductsReq struct {
	Products []addProductItem `json:"products" binding:"required,min=1"`
}

type addProductItem struct {
	ProductID     *uuid.UUID `json:"product_id"`
	ProductName   string     `json:"product_name" binding:"required"`
	ImageURL      string     `json:"image_url"`
	OriginalPrice float64    `json:"original_price"`
	SalePrice     float64    `json:"sale_price"`
	DiscountPct   float64    `json:"discount_pct"`
	StockLeft     int        `json:"stock_left"`
	Unit          string     `json:"unit"`
	IsPinned      bool       `json:"is_pinned"`
}

func (h *Handler) addProducts(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	var req addProductsReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
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
	items := make([]SessionProduct, 0, len(req.Products))
	for _, p := range req.Products {
		var imgURL *string
		if p.ImageURL != "" {
			img := p.ImageURL
			imgURL = &img
		}
		items = append(items, SessionProduct{
			ProductID:     p.ProductID,
			ProductName:   p.ProductName,
			ImageURL:      imgURL,
			OriginalPrice: p.OriginalPrice,
			SalePrice:     p.SalePrice,
			DiscountPct:   p.DiscountPct,
			StockLeft:     p.StockLeft,
			Unit:          p.Unit,
			IsPinned:      p.IsPinned,
		})
	}
	if err := h.repo.AddProducts(c.Request.Context(), id, items); err != nil {
		c.Error(httpx.NewInternal("add products", err))
		return
	}
	// Bust the listActive cache + nudge global subscribers so the new
	// pin shows up on viewer Live tab cards in <100ms instead of
	// waiting for the cache TTL.
	_ = h.cache.InvalidatePattern(c.Request.Context(), "live:sessions:*")
	h.publishListChange("products_changed")
	products, _ := h.repo.ListProducts(c.Request.Context(), id)
	c.JSON(http.StatusOK, gin.H{"products": products})
}

// replaceProducts swaps the entire pinned set in one transaction. The
// host UI uses this on return from the picker so the server-side list
// matches exactly what the host last confirmed — diffing add/remove
// from the client would race against the bot reply heuristic that
// reads products in a background goroutine.
func (h *Handler) replaceProducts(c *gin.Context) {
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
	// Accept the same payload shape as POST — but allow empty list so the
	// host can clear all pins.
	var req struct {
		Products []addProductItem `json:"products"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	items := make([]SessionProduct, 0, len(req.Products))
	for _, p := range req.Products {
		var imgURL *string
		if p.ImageURL != "" {
			img := p.ImageURL
			imgURL = &img
		}
		items = append(items, SessionProduct{
			ProductID:     p.ProductID,
			ProductName:   p.ProductName,
			ImageURL:      imgURL,
			OriginalPrice: p.OriginalPrice,
			SalePrice:     p.SalePrice,
			DiscountPct:   p.DiscountPct,
			StockLeft:     p.StockLeft,
			Unit:          p.Unit,
			IsPinned:      p.IsPinned,
		})
	}
	if err := h.repo.ReplaceProducts(c.Request.Context(), id, items); err != nil {
		c.Error(httpx.NewInternal("replace products", err))
		return
	}
	_ = h.cache.InvalidatePattern(c.Request.Context(), "live:sessions:*")
	h.publishListChange("products_changed")
	products, _ := h.repo.ListProducts(c.Request.Context(), id)
	c.JSON(http.StatusOK, gin.H{"products": products})
}

// removeProduct unpins a single live_session_products row. Path param
// is the live_session_products.id (not the catalog product_id) since the
// host UI works with the session-specific records.
func (h *Handler) removeProduct(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	productID, err := uuid.Parse(c.Param("productId"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid productId", nil))
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
	if err := h.repo.RemoveProduct(c.Request.Context(), id, productID); err != nil {
		c.Error(httpx.NewInternal("remove product", err))
		return
	}
	_ = h.cache.InvalidatePattern(c.Request.Context(), "live:sessions:*")
	h.publishListChange("products_changed")
	c.Status(http.StatusNoContent)
}

// ---------- Pinned product (Shopee Live "GẶP LÊN") ----------

type pinReq struct {
	// Null/omitted clears the pin. When set, must reference a
	// live_session_products.id belonging to this session — repo enforces.
	ProductID *uuid.UUID `json:"product_id"`
}

func (h *Handler) pinProduct(c *gin.Context) {
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	var req pinReq
	// Empty body is allowed (means "clear the pin"), so ShouldBindJSON
	// errors only on malformed JSON, not missing fields.
	if c.Request.ContentLength > 0 {
		if err := c.ShouldBindJSON(&req); err != nil {
			c.Error(httpx.NewValidation(err.Error(), nil))
			return
		}
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
	if err := h.repo.SetPinnedProduct(c.Request.Context(), id, req.ProductID); err != nil {
		if errors.Is(err, ErrNotFound) {
			c.Error(httpx.NewNotFound("product not in this session"))
			return
		}
		c.Error(httpx.NewInternal("set pin", err))
		return
	}
	// Audit-log the pin/unpin for VOD replay. For a pin we load the
	// product so replay overlays don't need a second round-trip; for
	// unpin we emit a dedicated event with empty payload.
	if h.events != nil {
		if req.ProductID == nil {
			h.events.LogAsync(id, sess.StartedAt, EventProductUnpin, nil)
		} else if p, perr := h.repo.GetSessionProduct(c.Request.Context(), *req.ProductID); perr == nil {
			h.events.LogAsync(id, sess.StartedAt, EventProductPin, map[string]any{
				"product_id":   p.ID,
				"product_name": p.ProductName,
				"image_url":    p.ImageURL,
				"sale_price":   p.SalePrice,
			})
		}
	}
	// Tell every viewer to refresh — pin change is a stats-style event
	// (same channel as viewer_count, like_count) so the overlay updates
	// without polling. We piggyback on the existing stats event so the
	// frontend only listens to one channel.
	h.publishStatsEvent(id)
	_ = h.cache.InvalidatePattern(c.Request.Context(), "live:sessions:*")
	c.JSON(http.StatusOK, gin.H{
		"pinned_product_id": req.ProductID,
	})
}

// ---------- Coupons ----------

type createCouponReq struct {
	Code          string  `json:"code" binding:"required,min=3,max=32"`
	DiscountType  string  `json:"discount_type" binding:"required,oneof=percent fixed"`
	DiscountValue float64 `json:"discount_value" binding:"required,gt=0"`
	MinOrderValue float64 `json:"min_order_value"`
	// Required (option 1b): per-user dedup was removed, so the total cap
	// is the only thing bounding coupon abuse. A null max_uses would mean
	// a single buyer could redeem the same discount on unlimited orders.
	MaxUses   *int   `json:"max_uses" binding:"required,min=1"`
	ExpiresAt string `json:"expires_at" binding:"required"` // ISO 8601
}

// createCoupon — host creates a coupon attached to this live session.
// Session ownership is enforced (only the seller of the session can post).
func (h *Handler) createCoupon(c *gin.Context) {
	if h.coupons == nil {
		c.Error(httpx.NewInternal("coupons disabled", nil))
		return
	}
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
	if sess.SellerID != uid {
		c.Error(httpx.NewForbidden("not session owner"))
		return
	}
	var req createCouponReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.Error(httpx.NewValidation(err.Error(), nil))
		return
	}
	expires, err := time.Parse(time.RFC3339, req.ExpiresAt)
	if err != nil {
		c.Error(httpx.NewValidation("expires_at must be RFC3339", nil))
		return
	}
	coupon, err := h.coupons.Create(c.Request.Context(),
		strings.ToUpper(req.Code), req.DiscountType,
		req.DiscountValue, req.MinOrderValue,
		nil, req.MaxUses,
		expires, &id, uid)
	if err != nil {
		c.Error(httpx.NewInternal("create coupon", err))
		return
	}
	// Broadcast to every viewer's WS so the Shopee-style floating banner
	// appears within ~1 round-trip of the host hitting "Tạo coupon".
	// Shopee Live treats "create" = "publish" — there's no separate
	// announce step at coupon-creation time. Hosts can re-announce
	// existing coupons via /coupons/:cid/announce.
	h.publishCouponAnnounce(id, coupon)
	if h.events != nil {
		h.events.LogAsync(id, sess.StartedAt, EventCouponPublish, map[string]any{
			"coupon_id":      coupon.ID,
			"code":           coupon.Code,
			"discount_type":  coupon.DiscountType,
			"discount_value": coupon.DiscountValue,
		})
	}
	uidPtr, role, ip := actorFromContext(c)
	maxUsesVal := -1
	if req.MaxUses != nil {
		maxUsesVal = *req.MaxUses
	}
	h.logAudit(c.Request.Context(), audit.Entry{
		ActorID: uidPtr, ActorRole: role, ActorIP: ip,
		Action:     audit.ActionCouponPublish,
		TargetType: audit.TargetCoupon,
		TargetID:   coupon.ID.String(),
		Payload: map[string]any{
			"session_id":     id.String(),
			"code":           coupon.Code,
			"discount_type":  coupon.DiscountType,
			"discount_value": coupon.DiscountValue,
			"max_uses":       maxUsesVal,
			"expires_at":     coupon.ExpiresAt,
		},
	})
	c.JSON(http.StatusCreated, gin.H{"coupon": coupon})
}

// announceCoupon — host re-broadcasts an already-existing coupon to
// pull viewers' attention back to it (Shopee Live "Phát coupon" button
// in the host coupon manager). Same payload shape as create.
func (h *Handler) announceCoupon(c *gin.Context) {
	if h.coupons == nil {
		c.Error(httpx.NewInternal("coupons disabled", nil))
		return
	}
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	cid, err := uuid.Parse(c.Param("couponId"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid couponId", nil))
		return
	}
	sess, err := h.repo.GetByID(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewNotFound("session not found"))
		return
	}
	claims, _ := auth.ClaimsFrom(c)
	uid, _ := uuid.Parse(claims.UserID)
	if sess.SellerID != uid {
		c.Error(httpx.NewForbidden("not session owner"))
		return
	}
	// Reuse listBySession + find — coupons.GetByID would be cleaner but
	// the repo doesn't have one yet and the list is bounded to ≤5 per
	// session per CLAUDE.md, so a linear scan is cheap.
	list, err := h.coupons.ListBySession(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewInternal("list coupons", err))
		return
	}
	var found *commerce.Coupon
	for i := range list {
		// Linear scan — list bounded to ≤5 per session per CLAUDE.md so
		// this is cheap, and we avoid adding a GetByID just for this.
		if list[i].ID == cid {
			found = &list[i]
			break
		}
	}
	if found == nil {
		c.Error(httpx.NewNotFound("coupon not found in session"))
		return
	}
	h.publishCouponAnnounce(id, found)
	if h.events != nil {
		h.events.LogAsync(id, sess.StartedAt, EventCouponPublish, map[string]any{
			"coupon_id":      found.ID,
			"code":           found.Code,
			"discount_type":  found.DiscountType,
			"discount_value": found.DiscountValue,
		})
	}
	c.Status(http.StatusNoContent)
}

// listCoupons — public list of coupons tied to this session, for viewers.
func (h *Handler) listCoupons(c *gin.Context) {
	if h.coupons == nil {
		c.JSON(http.StatusOK, gin.H{"coupons": []any{}})
		return
	}
	id, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.Error(httpx.NewValidation("invalid id", nil))
		return
	}
	list, err := h.coupons.ListBySession(c.Request.Context(), id)
	if err != nil {
		c.Error(httpx.NewInternal("list coupons", err))
		return
	}
	c.JSON(http.StatusOK, gin.H{"coupons": list})
}

// ---------- VOD replay timeline ----------

// timelineEntry is one row in the merged replay timeline. `t` is the
// stream offset in ms from session.started_at — the Flutter VOD player
// uses it as the video position at which to surface this entry.
type timelineEntry struct {
	T       int64           `json:"t"`
	Type    string          `json:"type"`
	Payload json.RawMessage `json:"payload"`
}

// getTimeline returns the merged ordered list of host actions
// (live_events) + chat messages (chat_messages) for one session.
// Public (no auth) because the VOD itself is public on R2 — gating the
// overlay timeline would only hurt replay UX without protecting any
// secret. Chat is bounded to 10k entries so an abusive session can't
// blow up the JSON response.
func (h *Handler) getTimeline(c *gin.Context) {
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
	startedAt := sess.StartedAt

	entries := make([]timelineEntry, 0, 256)

	// Host action events (bot toggle, pin/unpin, coupon).
	if h.events != nil {
		evs, err := h.events.ListBySession(c.Request.Context(), id)
		if err == nil {
			for _, e := range evs {
				entries = append(entries, timelineEntry{
					T: e.StreamOffsetMs, Type: e.EventType, Payload: e.Payload,
				})
			}
		} else {
			slog.Default().Warn("timeline: list events failed", "session_id", id, "err", err)
		}
	}

	// Chat messages — compute offset from created_at vs session start.
	chats, err := h.repo.TimelineChats(c.Request.Context(), id, 10000)
	if err == nil {
		for _, m := range chats {
			off := m.CreatedAt.Sub(startedAt).Milliseconds()
			if off < 0 {
				off = 0
			}
			payload, _ := json.Marshal(map[string]any{
				"id":         m.ID,
				"username":   m.Username,
				"avatar_url": m.AvatarURL,
				"message":    m.Message,
				"is_host":    m.IsHost,
				"type":       m.Type,
			})
			entries = append(entries, timelineEntry{
				T: off, Type: "chat", Payload: payload,
			})
		}
	} else {
		slog.Default().Warn("timeline: list chats failed", "session_id", id, "err", err)
	}

	// Stable sort by t (host actions already sorted, chats already sorted —
	// merge by simple sort since the two sequences are small enough).
	sortTimeline(entries)

	c.JSON(http.StatusOK, gin.H{
		"session_id":   id,
		"started_at":   startedAt,
		"vod_mp4_url":  sess.VodMp4URL,
		"duration_sec": sessDurationSec(sess),
		"entries":      entries,
	})
}

func sortTimeline(entries []timelineEntry) {
	sort.SliceStable(entries, func(i, j int) bool { return entries[i].T < entries[j].T })
}

// sessDurationSec returns recording duration in seconds, falling back to
// (ended_at - started_at) if VOD wasn't recorded yet (or live still in
// progress, in which case ended_at is nil → 0).
func sessDurationSec(s *Session) int {
	if s.EndedAt != nil {
		return int(s.EndedAt.Sub(s.StartedAt).Seconds())
	}
	return 0
}

// ---------- Helpers ----------

// generateChannelName is the legacy in-handler key generator. The
// active path goes through h.streamKeyProvider (see create()) so we
// can swap to the infra-managed provider without touching handler
// code. Kept here for tests and as a documentation breadcrumb.
func generateChannelName() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return "live_" + hex.EncodeToString(b)
}

var _ = generateChannelName // referenced by tests + kept for legacy callers

// Make ErrSessionNotFound check accessible to other handlers
func IsNotFound(err error) bool {
	return errors.Is(err, ErrSessionNotFound)
}

// ---------- WebSocket chat ----------

const (
	wsReadDeadline    = 65 * time.Second // expect a pong every 60s
	wsWriteDeadline   = 10 * time.Second
	wsPingInterval    = 30 * time.Second
	wsMaxMessageBytes = 4 * 1024 // viewers don't send anything substantial over the WS
)

// chatWS upgrades the request to a WebSocket and registers it with the
// ChatHub. The server only PUSHES messages (chat events broadcast from
// postChat / maybeBotReply); the client never sends through this
// socket — they still POST /chat for writes (so rate-limit and bot
// trigger logic stay in one place). The reader goroutine just handles
// pings and detects disconnects.
func (h *Handler) chatWS(c *gin.Context) {
	sessionID := c.Param("id")
	if _, err := uuid.Parse(sessionID); err != nil {
		c.AbortWithStatus(http.StatusBadRequest)
		return
	}
	// Verify the session exists (and is the right kind). Cheap lookup,
	// keeps junk WS conns from sitting on memory forever.
	if _, err := h.repo.GetByID(c.Request.Context(), uuid.MustParse(sessionID)); err != nil {
		c.AbortWithStatus(http.StatusNotFound)
		return
	}
	conn, err := wsUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		// Upgrade writes the error response itself.
		return
	}
	client := h.hub.NewClient(sessionID, 32)
	conn.SetReadLimit(wsMaxMessageBytes)
	_ = conn.SetReadDeadline(time.Now().Add(wsReadDeadline))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(wsReadDeadline))
	})

	// Writer goroutine: drain hub → ws + send pings on a timer.
	go func() {
		ping := time.NewTicker(wsPingInterval)
		defer ping.Stop()
		defer conn.Close()
		for {
			select {
			case msg, ok := <-client.Send():
				_ = conn.SetWriteDeadline(time.Now().Add(wsWriteDeadline))
				if !ok {
					_ = conn.WriteMessage(websocket.CloseMessage, []byte{})
					return
				}
				if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
					return
				}
			case <-ping.C:
				_ = conn.SetWriteDeadline(time.Now().Add(wsWriteDeadline))
				if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
					return
				}
			case <-client.Done():
				return
			}
		}
	}()

	// Reader: throw away anything the client sends, but keep reading
	// so we detect disconnects + reset the read deadline via pong.
	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			h.hub.Disconnect(client)
			return
		}
	}
}

// publishChatEvent JSON-marshals a chat message envelope and fans it
// out to every WS subscriber of `sessionID`. Called by postChat (real
// viewer message) and maybeBotReply (DeepSeek auto-reply) after the
// message is committed to Postgres.
func (h *Handler) publishChatEvent(sessionID uuid.UUID, msg *ChatMessage) {
	if h.hub == nil || msg == nil {
		return
	}
	payload, err := json.Marshal(map[string]any{
		"type":    "chat",
		"message": msg,
	})
	if err != nil {
		return
	}
	h.hub.Publish(sessionID.String(), payload)
}

// listWS — global subscriber for "list changed" pings. Same lifecycle
// pattern as chatWS (writer goroutine drains send chan + heartbeat
// ping; reader detects disconnect via pong/close).
func (h *Handler) listWS(c *gin.Context) {
	conn, err := wsUpgrader.Upgrade(c.Writer, c.Request, nil)
	if err != nil {
		return
	}
	client := h.hub.NewGlobalClient(8) // bursty refresh OK to drop
	conn.SetReadLimit(wsMaxMessageBytes)
	_ = conn.SetReadDeadline(time.Now().Add(wsReadDeadline))
	conn.SetPongHandler(func(string) error {
		return conn.SetReadDeadline(time.Now().Add(wsReadDeadline))
	})

	go func() {
		ping := time.NewTicker(wsPingInterval)
		defer ping.Stop()
		defer conn.Close()
		for {
			select {
			case msg, ok := <-client.Send():
				_ = conn.SetWriteDeadline(time.Now().Add(wsWriteDeadline))
				if !ok {
					_ = conn.WriteMessage(websocket.CloseMessage, []byte{})
					return
				}
				if err := conn.WriteMessage(websocket.TextMessage, msg); err != nil {
					return
				}
			case <-ping.C:
				_ = conn.SetWriteDeadline(time.Now().Add(wsWriteDeadline))
				if err := conn.WriteMessage(websocket.PingMessage, nil); err != nil {
					return
				}
			case <-client.Done():
				return
			}
		}
	}()

	for {
		if _, _, err := conn.ReadMessage(); err != nil {
			h.hub.Disconnect(client)
			return
		}
	}
}

// publishListChange notifies every global subscriber that the live
// list has changed. Payload is intentionally tiny — clients re-fetch
// `/streams` themselves (the 3s Redis cache absorbs the burst).
func (h *Handler) publishListChange(reason string) {
	if h.hub == nil {
		return
	}
	payload, err := json.Marshal(map[string]any{
		"type":   "list_change",
		"reason": reason,
	})
	if err != nil {
		return
	}
	h.hub.PublishGlobal(payload)
}

// publishStatsEvent broadcasts a fresh counters snapshot. Called on
// every mutate path that changes a counter (join/leave, like, cart-add,
// follow, end). Viewers get push updates in <100ms instead of waiting
// for the old 5s polling cycle, and we skip the per-viewer Postgres
// round-trip entirely.
//
// `status` lets clients detect "host ended the stream" and pop back to
// the list without their own polling.
// publishCouponAnnounce pushes a Shopee Live-style "host đang phát
// coupon" event to every viewer subscribed to this session. Viewers'
// LiveSocket decodes type=coupon_announce and surfaces the floating
// banner with this coupon's values. Fire-and-forget — slow consumers
// get dropped by the hub.
func (h *Handler) publishCouponAnnounce(sessionID uuid.UUID, coupon *commerce.Coupon) {
	if h.hub == nil {
		return
	}
	payload, err := json.Marshal(map[string]any{
		"type":   "coupon_announce",
		"coupon": coupon,
	})
	if err != nil {
		return
	}
	h.hub.Publish(sessionID.String(), payload)
}

func (h *Handler) publishStatsEvent(sessionID uuid.UUID) {
	if h.hub == nil {
		return
	}
	// Fire-and-forget context — we don't want a viewer's slow disconnect
	// to wait on the DB.
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	sess, err := h.repo.GetByID(ctx, sessionID)
	if err != nil {
		return
	}
	viewers, _ := h.repo.CountViewers(ctx, sessionID)
	follows, _ := h.repo.CountFollows(ctx, sessionID)
	payload, err := json.Marshal(map[string]any{
		"type":              "stats",
		"viewer_count":      viewers,
		"like_count":        sess.LikeCount,
		"order_count":       sess.OrderCount,
		"cart_add_count":    sess.CartAddCount,
		"follow_count":      follows,
		"status":            sess.Status,
		"pinned_product_id": sess.PinnedProductID,
	})
	if err != nil {
		return
	}
	h.hub.Publish(sessionID.String(), payload)
}
