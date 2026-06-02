package srs

import (
	"context"
	"crypto/subtle"
	"log/slog"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/redis/go-redis/v9"

	"github.com/tropia/backend/internal/cache"
	"github.com/tropia/backend/internal/live"
)

// SRS webhook handler
// Reference: https://github.com/ossrs/srs/wiki/v4_EN_HTTPCallback
//
// SRS POSTs to these endpoints when events happen:
// - on_publish:   stream started by host
// - on_unpublish: stream ended
// - on_play:      viewer connected
// - on_stop:      viewer disconnected
// - on_dvr:       recording file finished — triggers FFmpeg remux + R2 upload

// EventPublisher mirrors events.EventBus.
type EventPublisher interface {
	Publish(ctx context.Context, eventType string, payload any) error
}

type noopPublisher struct{}

func (noopPublisher) Publish(context.Context, string, any) error { return nil }

type Handler struct {
	repo   *live.SessionRepository
	events EventPublisher
	// Shared secret SRS must include as `?secret=...` on every webhook
	// URL. Without this anyone can POST forged on_publish (mark fake
	// streams live), on_dvr (trigger junk R2 uploads), etc. Set via
	// SRS_WEBHOOK_SECRET env + matching `?secret=…` in srs.conf
	// http_hooks URLs.
	secret string
	// cache is used to track active publishers per stream_key so a
	// second publisher trying to push to a stream that's already live
	// (threat 1 — stream hijack) is rejected at on_publish. Optional;
	// nil disables duplicate detection (the repo-level status check
	// still applies). See onPublish.
	cache *cache.Cache
}

func NewHandler(repo *live.SessionRepository) *Handler {
	return &Handler{repo: repo, events: noopPublisher{}}
}

// WithCache enables Redis-backed duplicate-publisher detection. Should
// be wired in production.
func (h *Handler) WithCache(c *cache.Cache) *Handler {
	h.cache = c
	return h
}

// publisherLockTTL is how long the publisher-claim key survives without
// being refreshed. SRS reconnect-on-blip is the dominant case here: a
// short network drop, RTMP reconnect within seconds, on_publish fires
// again. The TTL has to outlast that gap (so the rightful publisher's
// reconnect is treated as renewal, not collision) but stay short enough
// that on_unpublish failure doesn't permanently lock the stream.
const publisherLockTTL = 60 * time.Second

// WithSecret enables shared-secret auth on webhook routes. Empty string
// disables the check (useful in dev where SRS is on the same host and
// the port is firewalled). Production MUST set a non-empty secret.
func (h *Handler) WithSecret(secret string) *Handler {
	h.secret = secret
	return h
}

// WithEvents wires an event bus so on_dvr can hand recordings off to the
// background worker for FFmpeg remux + R2 upload.
func (h *Handler) WithEvents(p EventPublisher) *Handler {
	if p != nil {
		h.events = p
	}
	return h
}

// verifySecret middleware — drops any webhook missing `?secret=…` that
// matches the configured shared secret. Uses constant-time compare so a
// timing attack can't reveal the secret one byte at a time. Returns
// HTTP 200 with body "1" (deny code) so SRS treats the rejection as
// "stream not allowed" rather than retrying.
func (h *Handler) verifySecret(c *gin.Context) {
	if h.secret == "" {
		c.Next()
		return
	}
	got := c.Query("secret")
	if subtle.ConstantTimeCompare([]byte(got), []byte(h.secret)) != 1 {
		deny(c, 1)
		c.Abort()
		return
	}
	c.Next()
}

func (h *Handler) Register(r *gin.RouterGroup) {
	r.Use(h.verifySecret)
	r.POST("/on_publish", h.onPublish)
	r.POST("/on_unpublish", h.onUnpublish)
	r.POST("/on_play", h.onPlay)
	r.POST("/on_stop", h.onStop)
	r.POST("/on_dvr", h.onDvr)
}

// SRS webhook payload
// {
//   "action": "on_publish",
//   "client_id": "108",
//   "ip": "127.0.0.1",
//   "vhost": "__defaultVhost__",
//   "app": "live",
//   "stream": "live_abc123",   <-- this is our stream_key
//   "param": "?token=xxx",
//   "file": "./objs/nginx/html/dvr/live/live_abc.1234.flv",  // on_dvr only
//   "duration": 67                                            // on_dvr only (seconds)
// }
type webhookPayload struct {
	Action   string `json:"action"`
	ClientID string `json:"client_id"`
	IP       string `json:"ip"`
	Vhost    string `json:"vhost"`
	App      string `json:"app"`
	Stream   string `json:"stream"`
	Param    string `json:"param"`
	File     string `json:"file,omitempty"`
	Duration int    `json:"duration,omitempty"`
}

// SRS expects HTTP 200 with body "0" to allow; non-zero to deny.
func ok(c *gin.Context) {
	c.String(http.StatusOK, "0")
}

func deny(c *gin.Context, code int) {
	c.String(http.StatusOK, "%d", code)
}

func (h *Handler) onPublish(c *gin.Context) {
	var p webhookPayload
	if err := c.ShouldBindJSON(&p); err != nil {
		deny(c, 1)
		return
	}
	ctx := c.Request.Context()
	// Reject unknown streams
	if _, err := h.repo.GetByChannel(ctx, p.Stream); err != nil {
		deny(c, 1)
		return
	}
	// Duplicate-publisher gate (threat 1). The first publisher claims a
	// Redis key keyed by stream_key, valued with their SRS client_id; if
	// a second client_id later tries to claim the same key while the
	// first is still alive we deny + alert. Same client_id reconnecting
	// (RTMP blip, app put to background) renews the TTL and is allowed.
	// Skipped when no cache is wired or SRS forgot to send a client_id.
	if h.cache != nil && p.ClientID != "" {
		rds := h.cache.Client()
		key := "live:publisher:" + p.Stream
		// Try to claim the slot; if it exists, fetch and compare.
		setOK, err := rds.SetNX(ctx, key, p.ClientID, publisherLockTTL).Result()
		if err == nil && !setOK {
			existing, gerr := rds.Get(ctx, key).Result()
			if gerr == nil && existing != p.ClientID {
				slog.Default().Warn("srs: duplicate publisher rejected — possible stream hijack",
					"stream", p.Stream, "existing_client", existing, "new_client", p.ClientID, "ip", p.IP)
				deny(c, 1)
				return
			}
			// Same client reconnecting — extend the lease.
			_ = rds.Expire(ctx, key, publisherLockTTL).Err()
		}
	}
	_ = h.repo.MarkLive(ctx, p.Stream)
	ok(c)
}

func (h *Handler) onUnpublish(c *gin.Context) {
	var p webhookPayload
	if err := c.ShouldBindJSON(&p); err != nil {
		ok(c)
		return
	}
	ctx := c.Request.Context()
	// Release the publisher lock only if the unpublishing client is the
	// one currently holding it. Otherwise an attacker's spurious
	// on_unpublish from a denied attempt could free the slot for the
	// next hijack try.
	if h.cache != nil && p.ClientID != "" {
		rds := h.cache.Client()
		key := "live:publisher:" + p.Stream
		existing, err := rds.Get(ctx, key).Result()
		if err == nil && existing == p.ClientID {
			_ = rds.Del(ctx, key).Err()
		} else if err != nil && err != redis.Nil {
			slog.Default().Warn("srs: publisher lock lookup failed", "err", err)
		}
	}
	_ = h.repo.EndByChannel(ctx, p.Stream)
	ok(c)
}

func (h *Handler) onPlay(c *gin.Context) { ok(c) }
func (h *Handler) onStop(c *gin.Context) { ok(c) }

// onDvr — fired by SRS when DVR finishes writing the .flv recording.
// We publish a `recording.created` event to Redis Streams; the background
// worker (cmd/worker) picks it up, remuxes FLV → MP4 with FFmpeg, uploads
// to R2, and updates live_sessions.vod_mp4_url.
func (h *Handler) onDvr(c *gin.Context) {
	var p webhookPayload
	if err := c.ShouldBindJSON(&p); err != nil {
		ok(c)
		return
	}

	// SRS file path is INSIDE the container, e.g.
	//   ./objs/nginx/html/dvr/live/live_abc.1234.flv
	// We bind-mount the DVR folder to ./infra/dvr on the host, so strip
	// the container prefix and the worker can find the file under its
	// own DVR_HOST_PATH (set via env).
	relPath := strings.TrimPrefix(p.File, "./objs/nginx/html/dvr/")
	relPath = strings.TrimPrefix(relPath, "objs/nginx/html/dvr/")

	// Look up the session UUID from the stream key.
	sess, err := h.repo.GetByChannel(c.Request.Context(), p.Stream)
	if err != nil {
		// Recording for an unknown stream — still 200 OK to SRS (file is
		// still on disk; manual cleanup if needed).
		ok(c)
		return
	}

	_ = h.events.Publish(c.Request.Context(), "recording.created", map[string]any{
		"session_id":    sess.ID.String(),
		"stream_key":    p.Stream,
		"srs_file_path": filepath.ToSlash(relPath), // relative to DVR root
		"duration_sec":  p.Duration,
	})

	ok(c)
}
