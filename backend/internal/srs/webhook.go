package srs

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/tropia/backend-go/internal/live"
)

// SRS webhook handler
// Reference: https://github.com/ossrs/srs/wiki/v4_EN_HTTPCallback
//
// SRS POSTs to these endpoints when events happen:
// - on_publish:   stream started by host
// - on_unpublish: stream ended
// - on_play:      viewer connected
// - on_stop:      viewer disconnected
// - on_dvr:       recording file finished

type Handler struct {
	repo *live.SessionRepository
}

func NewHandler(repo *live.SessionRepository) *Handler {
	return &Handler{repo: repo}
}

func (h *Handler) Register(r *gin.RouterGroup) {
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
//   "stream": "live_abc123",   <-- this is our agora_channel
//   "param": "?token=xxx"
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
	// Reject unknown streams
	if _, err := h.repo.GetByChannel(c.Request.Context(), p.Stream); err != nil {
		deny(c, 1)
		return
	}
	_ = h.repo.MarkLive(c.Request.Context(), p.Stream)
	ok(c)
}

func (h *Handler) onUnpublish(c *gin.Context) {
	var p webhookPayload
	if err := c.ShouldBindJSON(&p); err != nil {
		ok(c)
		return
	}
	_ = h.repo.EndByChannel(c.Request.Context(), p.Stream)
	ok(c)
}

func (h *Handler) onPlay(c *gin.Context)    { ok(c) }
func (h *Handler) onStop(c *gin.Context)    { ok(c) }
func (h *Handler) onDvr(c *gin.Context) {
	// TODO: enqueue R2 upload job
	ok(c)
}
