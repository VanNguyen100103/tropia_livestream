package live

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
)

// ─────────────────────────────────────────────────────────────────────────
// Spec layer (LIVESTREAM_API.md)
//
// These types + queries back the mobile API contract: integer ids (the
// BIGSERIAL `seq` columns added in migration 0010), stream_key-addressed
// sessions, publish tokens, and the host{} embed. They live alongside the
// richer internal Session/ChatMessage model rather than replacing it, so
// scanSession and the existing repo methods stay untouched.
// ─────────────────────────────────────────────────────────────────────────

// apiTime serialises to the spec's "YYYY-MM-DD HH:MM:SS" date format
// (LIVESTREAM_API.md) instead of RFC3339, and marshals a zero time as
// null. It implements sql.Scanner so pgx can scan timestamptz columns
// straight into it.
type apiTime struct{ t time.Time }

const apiTimeLayout = "2006-01-02 15:04:05"

func (a apiTime) MarshalJSON() ([]byte, error) {
	if a.t.IsZero() {
		return []byte("null"), nil
	}
	return []byte(`"` + a.t.Format(apiTimeLayout) + `"`), nil
}

func (a *apiTime) Scan(src any) error {
	switch v := src.(type) {
	case nil:
		a.t = time.Time{}
	case time.Time:
		a.t = v
	case *time.Time:
		if v != nil {
			a.t = *v
		}
	default:
		return fmt.Errorf("apiTime: cannot scan %T", src)
	}
	return nil
}

// SpecHost is the host{} object embedded in list/watch responses.
type SpecHost struct {
	ID       int64  `json:"id"`
	Username string `json:"username"`
	FullName string `json:"full_name"`
	Avatar   string `json:"avatar"`
	// uid is the internal UUID — not serialised, used for self-gift checks.
	uid uuid.UUID `json:"-"`
}

// SpecSession is the session view the spec exposes. `id` is the integer
// seq; the internal UUID is kept unexported for repo lookups.
type SpecSession struct {
	ID                    int64      `json:"id"`
	StreamKey             string     `json:"stream_key"`
	Status                string     `json:"status"`
	Title                 string    `json:"title"`
	PublishToken          string    `json:"publish_token,omitempty"`
	PublishTokenExpiresAt apiTime   `json:"publish_token_expires_at"`
	StartedAt             apiTime   `json:"started_at"`
	CreatedAt             apiTime   `json:"created_at"`
	ViewerCount           int       `json:"viewer_count"`
	Host                  *SpecHost `json:"host,omitempty"`

	// uuid is the internal session id — used to address chat/gift tables.
	uuid     uuid.UUID `json:"-"`
	sellerID uuid.UUID `json:"-"`
}

// SessionUUID exposes the internal UUID for callers that need to touch
// the chat/gift tables keyed by session_id.
func (s *SpecSession) SessionUUID() uuid.UUID { return s.uuid }

// SellerID exposes the host's internal UUID (self-gift / ownership checks).
func (s *SpecSession) SellerID() uuid.UUID { return s.sellerID }

var ErrNoOpenSession = errors.New("no open session")

// generatePublishToken returns a 64-char hex token bound into the RTMP
// publish URL and validated by SRS on_publish.
func generatePublishToken() (string, error) {
	b := make([]byte, 32)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return hex.EncodeToString(b), nil
}

// buildStreamKey produces the spec's user_{id}_{ts} stream key. We don't
// have integer user ids (PKs are UUID), so a short hex slice of the UUID
// stands in for {id} — still unique per seller and SRS-safe.
func buildStreamKey(sellerID uuid.UUID) string {
	short := hex.EncodeToString(sellerID[:4])
	return fmt.Sprintf("user_%s_%d", short, time.Now().Unix())
}

// StartSpecSession closes any open (ready/live) session for the seller,
// then creates a fresh 'ready' session with a publish token. Returns the
// created session (token included).
func (r *SessionRepository) StartSpecSession(ctx context.Context, sellerID uuid.UUID, title string) (*SpecSession, error) {
	token, err := generatePublishToken()
	if err != nil {
		return nil, err
	}
	streamKey := buildStreamKey(sellerID)
	expires := time.Now().Add(2 * time.Hour)
	if title == "" {
		title = "Live"
	}

	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer tx.Rollback(ctx)

	// Close previous open sessions (spec: start replaces ready/live).
	if _, err := tx.Exec(ctx,
		`UPDATE live_sessions SET status = 'offline', ended_at = NOW(), publish_token = NULL
		   WHERE seller_id = $1 AND status IN ('ready', 'live')`, sellerID); err != nil {
		return nil, err
	}

	var s SpecSession
	err = tx.QueryRow(ctx, `
		INSERT INTO live_sessions (seller_id, title, stream_key, status, publish_token, publish_token_expires_at)
		VALUES ($1, $2, $3, 'ready', $4, $5)
		RETURNING seq, id, stream_key, status, title, publish_token, publish_token_expires_at, created_at
	`, sellerID, title, streamKey, token, expires).Scan(
		&s.ID, &s.uuid, &s.StreamKey, &s.Status, &s.Title,
		&s.PublishToken, &s.PublishTokenExpiresAt, &s.CreatedAt,
	)
	if err != nil {
		return nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	s.sellerID = sellerID
	return &s, nil
}

// StopSpecSession marks the seller's open session offline and revokes its
// publish token. Returns ErrNoOpenSession if there's nothing open.
func (r *SessionRepository) StopSpecSession(ctx context.Context, sellerID uuid.UUID) (streamKey string, endedAt time.Time, err error) {
	row := r.pool.QueryRow(ctx, `
		UPDATE live_sessions
		   SET status = 'offline', ended_at = NOW(), publish_token = NULL
		 WHERE seller_id = $1 AND status IN ('ready', 'live')
		 RETURNING stream_key, ended_at
	`, sellerID)
	err = row.Scan(&streamKey, &endedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", time.Time{}, ErrNoOpenSession
	}
	return streamKey, endedAt, err
}

// MySpecSession returns the seller's current ready/live session (token
// included since only the owner sees it). ErrNoOpenSession if none.
func (r *SessionRepository) MySpecSession(ctx context.Context, sellerID uuid.UUID) (*SpecSession, error) {
	var s SpecSession
	err := r.pool.QueryRow(ctx, `
		SELECT seq, id, stream_key, status, title, publish_token, publish_token_expires_at, started_at,
		       COALESCE(viewer_count, 0)
		  FROM live_sessions
		 WHERE seller_id = $1 AND status IN ('ready', 'live')
		 ORDER BY created_at DESC
		 LIMIT 1
	`, sellerID).Scan(
		&s.ID, &s.uuid, &s.StreamKey, &s.Status, &s.Title,
		&s.PublishToken, &s.PublishTokenExpiresAt, &s.StartedAt, &s.ViewerCount,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNoOpenSession
	}
	if err != nil {
		return nil, err
	}
	s.sellerID = sellerID
	return &s, nil
}

// SpecByStreamKey returns the public view of a session (host embedded).
// Returns ErrSessionNotFound when the stream_key is unknown.
func (r *SessionRepository) SpecByStreamKey(ctx context.Context, streamKey string) (*SpecSession, error) {
	var s SpecSession
	var h SpecHost
	err := r.pool.QueryRow(ctx, `
		SELECT ls.seq, ls.id, ls.stream_key, ls.status, ls.title, ls.started_at,
		       COALESCE(vc.cnt, ls.viewer_count, 0) AS viewer_count,
		       ls.seller_id, COALESCE(p.seq, 0), COALESCE(p.name, ''), COALESCE(p.phone, p.email, ''), COALESCE(p.avatar_url, '')
		  FROM live_sessions ls
		  LEFT JOIN profiles p ON p.id = ls.seller_id
		  LEFT JOIN (SELECT session_id, COUNT(*) AS cnt FROM live_viewers GROUP BY session_id) vc
		         ON vc.session_id = ls.id
		 WHERE ls.stream_key = $1
	`, streamKey).Scan(
		&s.ID, &s.uuid, &s.StreamKey, &s.Status, &s.Title, &s.StartedAt, &s.ViewerCount,
		&h.uid, &h.ID, &h.FullName, &h.Username, &h.Avatar,
	)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrSessionNotFound
	}
	if err != nil {
		return nil, err
	}
	s.sellerID = h.uid
	s.Host = &h
	return &s, nil
}

// ListLiveSpec returns sessions currently 'live' with host + viewer count.
func (r *SessionRepository) ListLiveSpec(ctx context.Context, limit int) ([]SpecSession, error) {
	if limit <= 0 || limit > 50 {
		limit = 20
	}
	rows, err := r.pool.Query(ctx, `
		SELECT ls.seq, ls.id, ls.stream_key, ls.status, ls.title, ls.started_at,
		       COALESCE(vc.cnt, ls.viewer_count, 0) AS viewer_count,
		       ls.seller_id, COALESCE(p.seq, 0), COALESCE(p.name, ''), COALESCE(p.phone, p.email, ''), COALESCE(p.avatar_url, '')
		  FROM live_sessions ls
		  LEFT JOIN profiles p ON p.id = ls.seller_id
		  LEFT JOIN (SELECT session_id, COUNT(*) AS cnt FROM live_viewers GROUP BY session_id) vc
		         ON vc.session_id = ls.id
		 WHERE ls.status = 'live'
		 ORDER BY ls.started_at DESC NULLS LAST, ls.seq DESC
		 LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	out := make([]SpecSession, 0)
	for rows.Next() {
		var s SpecSession
		var h SpecHost
		if err := rows.Scan(
			&s.ID, &s.uuid, &s.StreamKey, &s.Status, &s.Title, &s.StartedAt, &s.ViewerCount,
			&h.uid, &h.ID, &h.FullName, &h.Username, &h.Avatar,
		); err != nil {
			return nil, err
		}
		s.sellerID = h.uid
		s.Host = &h
		out = append(out, s)
	}
	return out, rows.Err()
}

// ValidatePublishToken reports whether SRS should accept a publish for
// streamKey. Sessions created via the spec live/start path carry a
// publish_token and the supplied ?token= must match (unexpired). Legacy
// sessions created without a token (the old /streams flow) carry no token
// and are accepted unconditionally — so both the spec and legacy host
// flows keep working side by side.
func (r *SessionRepository) ValidatePublishToken(ctx context.Context, streamKey, token string) bool {
	var stored string
	var expires *time.Time
	err := r.pool.QueryRow(ctx,
		`SELECT COALESCE(publish_token, ''), publish_token_expires_at
		   FROM live_sessions WHERE stream_key = $1 AND status NOT IN ('ended')`,
		streamKey).Scan(&stored, &expires)
	if err != nil {
		return false
	}
	if stored == "" {
		return true // legacy / unprotected session — no token required
	}
	if token == "" || stored != token {
		return false
	}
	if expires != nil && expires.Before(time.Now()) {
		return false
	}
	return true
}

// MarkLiveSpec flips a 'ready' (or already 'live') session to 'live' on a
// valid publish. Unlike MarkLive it refuses to resurrect 'offline'/'ended'
// rows, so a stale stream_key can't be republished after stop.
func (r *SessionRepository) MarkLiveSpec(ctx context.Context, streamKey string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE live_sessions
		    SET status = 'live', started_at = COALESCE(started_at, NOW()), ended_at = NULL
		  WHERE stream_key = $1 AND status IN ('ready', 'live')`, streamKey)
	return err
}

// EndByChannelSpec marks a session offline when SRS reports the publisher
// gone. Only affects ready/live rows.
func (r *SessionRepository) EndByChannelSpec(ctx context.Context, streamKey string) error {
	_, err := r.pool.Exec(ctx,
		`UPDATE live_sessions SET status = 'offline', ended_at = NOW(), publish_token = NULL
		   WHERE stream_key = $1 AND status IN ('ready', 'live')`, streamKey)
	return err
}
