package live

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ChatMuteRepository persists host-driven and auto-triggered mutes
// for live chat (threat 9 — chat manipulation).
//
// Schema design:
//   - One row per (session_id, user_id). Re-muting an already-muted
//     user extends muted_until rather than inserting a duplicate.
//   - Permanent bans don't exist as a concept here — every mute has
//     an explicit muted_until. A "session-long ban" is just
//     muted_until = session.scheduled_end_at, capped at 24h. This
//     means a stale row can never outlive a session.
type ChatMuteRepository struct{ pool *pgxpool.Pool }

func NewChatMuteRepository(pool *pgxpool.Pool) *ChatMuteRepository {
	return &ChatMuteRepository{pool: pool}
}

// MuteReason classifies why the user was muted, surfaced both in the
// audit log and in 403 responses to the muted client so support can
// triage abuse reports.
type MuteReason string

const (
	MuteReasonHostAction    MuteReason = "host_action"
	MuteReasonAutoURL       MuteReason = "auto_filter:url"
	MuteReasonAutoScam      MuteReason = "auto_filter:scam_phrase"
	MuteReasonAutoSpamBurst MuteReason = "auto_filter:spam_burst"
)

// Mute creates or extends a mute. mutedBy is nil for auto-mutes.
// The UNIQUE(session_id, user_id) constraint means UPSERT semantics —
// we want the later of (existing muted_until, new muted_until) so a
// burst of auto-mutes doesn't accidentally shorten a host-imposed ban.
func (r *ChatMuteRepository) Mute(ctx context.Context, sessionID, userID uuid.UUID, mutedUntil time.Time, reason MuteReason, mutedBy *uuid.UUID) error {
	const q = `
		INSERT INTO chat_mutes (session_id, user_id, muted_until, reason, muted_by)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (session_id, user_id) DO UPDATE
		SET muted_until = GREATEST(chat_mutes.muted_until, EXCLUDED.muted_until),
		    reason      = EXCLUDED.reason,
		    muted_by    = COALESCE(EXCLUDED.muted_by, chat_mutes.muted_by)
	`
	_, err := r.pool.Exec(ctx, q, sessionID, userID, mutedUntil, string(reason), mutedBy)
	return err
}

// Unmute removes the mute row entirely. We don't soft-delete because
// the audit_log already records the unmute event — the live state
// table only needs the current truth.
func (r *ChatMuteRepository) Unmute(ctx context.Context, sessionID, userID uuid.UUID) error {
	_, err := r.pool.Exec(ctx,
		`DELETE FROM chat_mutes WHERE session_id = $1 AND user_id = $2`,
		sessionID, userID)
	return err
}

// MuteInfo is the slice of mute state postChat needs to make a decision.
type MuteInfo struct {
	MutedUntil time.Time
	Reason     MuteReason
}

// ActiveMute returns the mute that's currently in effect for this
// user on this session, or pgx.ErrNoRows if there is none. Callers
// should treat ErrNoMute as "not muted" rather than a real error.
var ErrNoMute = errors.New("chat mute: not muted")

func (r *ChatMuteRepository) ActiveMute(ctx context.Context, sessionID, userID uuid.UUID) (*MuteInfo, error) {
	const q = `
		SELECT muted_until, reason
		FROM chat_mutes
		WHERE session_id = $1 AND user_id = $2 AND muted_until > NOW()
		LIMIT 1
	`
	var info MuteInfo
	var reasonStr string
	if err := r.pool.QueryRow(ctx, q, sessionID, userID).Scan(&info.MutedUntil, &reasonStr); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNoMute
		}
		return nil, err
	}
	info.Reason = MuteReason(reasonStr)
	return &info, nil
}
