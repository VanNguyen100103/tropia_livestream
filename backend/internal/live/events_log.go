package live

import (
	"context"
	"encoding/json"
	"log/slog"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// EventType values stored in live_events.event_type. Keep these short and
// stable — the Flutter VOD replay player switches on them.
const (
	EventBotToggle      = "bot_toggle"
	EventProductPin     = "product_pin"
	EventProductUnpin   = "product_unpin"
	EventCouponPublish  = "coupon_publish"
)

// LiveEvent is one row of live_events. stream_offset_ms is wall-clock
// (now - session.started_at) at write time, in ms. The replay player
// uses it as the video position at which to surface this event.
//
// Known drift: started_at is set when the session row is created (host
// taps "Tạo live"), not when SRS receives the first publish frame. If
// the host creates the session and only starts pushing RTMP minutes
// later, every offset will be ahead of the MP4 timeline by that gap.
// In practice the gap is seconds — small enough to ignore for replay UX.
type LiveEvent struct {
	ID             int64           `json:"id"`
	SessionID      uuid.UUID       `json:"session_id"`
	EventType      string          `json:"event_type"`
	Payload        json.RawMessage `json:"payload"`
	StreamOffsetMs int64           `json:"stream_offset_ms"`
	CreatedAt      time.Time       `json:"created_at"`
}

type EventRepository struct{ pool *pgxpool.Pool }

func NewEventRepository(pool *pgxpool.Pool) *EventRepository {
	return &EventRepository{pool: pool}
}

// Record inserts one row. Caller passes the session's StartedAt so we
// don't need to re-query — handlers already hold the session (loaded
// for permission check) before any of the action endpoints fire.
//
// Failures are returned but callers should NOT fail the user-facing
// action on a logging error — wrap with logAsync below for fire-and-forget.
func (r *EventRepository) Record(ctx context.Context, sessionID uuid.UUID, startedAt time.Time, eventType string, payload any) error {
	offsetMs := time.Since(startedAt).Milliseconds()
	if offsetMs < 0 {
		offsetMs = 0
	}
	var raw []byte
	if payload == nil {
		raw = []byte("{}")
	} else {
		b, err := json.Marshal(payload)
		if err != nil {
			return err
		}
		raw = b
	}
	_, err := r.pool.Exec(ctx,
		`INSERT INTO live_events (session_id, event_type, payload, stream_offset_ms)
		 VALUES ($1, $2, $3::jsonb, $4)`,
		sessionID, eventType, raw, offsetMs)
	return err
}

// LogAsync fires Record in a background goroutine with a detached
// context that survives the request's lifetime. Use this in handlers —
// the user's action must NOT fail because the audit row didn't insert,
// and we don't want to add request latency for a log write.
func (r *EventRepository) LogAsync(sessionID uuid.UUID, startedAt time.Time, eventType string, payload any) {
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := r.Record(ctx, sessionID, startedAt, eventType, payload); err != nil {
			slog.Default().Warn("live event log failed",
				"session_id", sessionID, "event_type", eventType, "err", err)
		}
	}()
}

// ListBySession returns every event for a session, oldest first. Used
// by the /timeline endpoint to merge with chat_messages.
func (r *EventRepository) ListBySession(ctx context.Context, sessionID uuid.UUID) ([]LiveEvent, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT id, session_id, event_type, payload, stream_offset_ms, created_at
		   FROM live_events
		  WHERE session_id = $1
		  ORDER BY stream_offset_ms ASC, id ASC`,
		sessionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]LiveEvent, 0, 64)
	for rows.Next() {
		var e LiveEvent
		if err := rows.Scan(&e.ID, &e.SessionID, &e.EventType, &e.Payload, &e.StreamOffsetMs, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}
