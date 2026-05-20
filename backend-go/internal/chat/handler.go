package chat

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/redis/go-redis/v9"

	"github.com/tropia/backend-go/internal/auth"
)

type Message struct {
	ID        uuid.UUID `json:"id"`
	StreamID  uuid.UUID `json:"stream_id"`
	UserID    uuid.UUID `json:"user_id"`
	Content   string    `json:"content"`
	CreatedAt time.Time `json:"created_at"`
}

type Handler struct {
	db    *pgxpool.Pool
	rds   *redis.Client
}

func NewHandler(db *pgxpool.Pool, rds *redis.Client) *Handler {
	return &Handler{db: db, rds: rds}
}

func (h *Handler) Register(r *gin.RouterGroup, authMw gin.HandlerFunc) {
	r.GET("/streams/:id/messages", h.list) // public read

	authed := r.Group("/streams/:id/messages", authMw)
	authed.POST("", h.send)
}

type sendReq struct {
	Content string `json:"content" binding:"required,min=1,max=500"`
}

func (h *Handler) send(c *gin.Context) {
	claims, _ := auth.ClaimsFrom(c)
	userID, err := uuid.Parse(claims.UserID)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid user id"})
		return
	}
	streamID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stream id"})
		return
	}

	var req sendReq
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	const q = `
		INSERT INTO live_messages (stream_id, user_id, content)
		VALUES ($1, $2, $3)
		RETURNING id, stream_id, user_id, content, created_at
	`
	var msg Message
	row := h.db.QueryRow(c.Request.Context(), q, streamID, userID, req.Content)
	if err := row.Scan(&msg.ID, &msg.StreamID, &msg.UserID, &msg.Content, &msg.CreatedAt); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	// Publish to Redis for real-time fanout (future: SSE / WebSocket)
	if payload, err := json.Marshal(msg); err == nil {
		_ = h.rds.Publish(c.Request.Context(), chatChannel(streamID), payload).Err()
	}

	c.JSON(http.StatusCreated, msg)
}

func (h *Handler) list(c *gin.Context) {
	streamID, err := uuid.Parse(c.Param("id"))
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid stream id"})
		return
	}

	const q = `
		SELECT id, stream_id, user_id, content, created_at
		FROM live_messages
		WHERE stream_id = $1
		ORDER BY created_at DESC
		LIMIT 50
	`
	rows, err := h.db.Query(c.Request.Context(), q, streamID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	defer rows.Close()

	out := make([]Message, 0, 50)
	for rows.Next() {
		var m Message
		if err := rows.Scan(&m.ID, &m.StreamID, &m.UserID, &m.Content, &m.CreatedAt); err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		out = append(out, m)
	}

	c.JSON(http.StatusOK, gin.H{"messages": out})
}

func chatChannel(streamID uuid.UUID) string {
	return fmt.Sprintf("chat:stream:%s", streamID.String())
}

// for future SSE handler
var _ = context.Background
